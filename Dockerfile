################################################################################
#' Define default build variables
ARG UBUNTU_VSN='22.04'
ARG TINI_VERSION='0.19.0'
ARG ALPINE_VSN='3.17'
ARG DEBIAN_FRONTEND='noninteractive'
ARG DEBCONF_NONINTERACTIVE_SEEN='true'
ARG UID='1000'
ARG USER='ctng'

ARG BUILD_DIR="/$USER"
ARG CTNG='local'
ARG CTNG_VSN='ee5a4026c3560c6b313313cf78236a60e300ee93'
ARG LIBC='gnu'
ARG APP='eturnal'
ARG TARGETS='x86_64-linux-gnu aarch64-linux-gnu x86_64-linux-musl aarch64-linux-musl'

################################################################################
#' glibc based toolchain - Use ubuntu as github runners are also ubuntu based
FROM ubuntu:${UBUNTU_VSN} AS base-gnu
ARG DEBIAN_FRONTEND
ARG DEBCONF_NONINTERACTIVE_SEEN
RUN apt-get update \
    && apt-get install -y gcc g++ gperf bison flex texinfo help2man make \
        libncurses5-dev python3-dev autoconf automake libtool libtool-bin gawk \
        wget bzip2 xz-utils unzip patch libstdc++6 rsync git meson ninja-build \
        curl makeself vim wget lynx

ARG TINI_VERSION
RUN ARCH=$(uname -m | sed -e 's/x86_64/amd64/;s/aarch64/arm64/') \
    && curl -fL -o /sbin/tini https://github.com/krallin/tini/releases/download/v$TINI_VERSION/tini-$ARCH \
    && chmod +x /sbin/tini

ARG UID
ARG USER
RUN groupadd -g $UID $USER \
    && useradd -d /$USER -m -g $UID -u $UID -s /bin/bash $USER

################################################################################
#' musl-libc based toolchain
FROM alpine:${ALPINE_VSN} AS base-musl
RUN echo https://dl-cdn.alpinelinux.org/alpine/edge/testing >> /etc/apk/repositories
RUN apk -U upgrade --available --no-cache \
    && apk add --no-cache alpine-sdk wget xz git bash autoconf automake bison \
        flex texinfo help2man gawk libtool ncurses-dev gettext-dev python3-dev \
        rsync curl makeself tini vim wget lynx

ARG UID
ARG USER
RUN addgroup -g $UID $USER \
    && adduser -D -h /$USER -G $USER -u $UID -s /bin/bash $USER

################################################################################
#' build toolchain with container build
FROM base-${LIBC} AS build
ARG DEBIAN_FRONTEND
ARG DEBCONF_NONINTERACTIVE_SEEN
ARG BUILD_DIR
ARG UID
COPY --chown=$UID:$UID scripts /scripts

WORKDIR /scripts
ARG USER
USER $USER
ARG APP
ARG TARGETS
RUN chmod +x ctng-$APP \
    && sed -i "s|targets='.*'|targets='$TARGETS'|" ctng-$APP
RUN ./ctng-$APP

################################################################################
#' use compiled toolchains from local machine
## host machine and container's must use the same OS/deps/libc to make it work
FROM base-${LIBC} AS local
ARG BUILD_DIR
ARG UID
COPY --chown=$UID:$UID ctng/x-tools $BUILD_DIR/x-tools

################################################################################
#' final image
FROM ${CTNG} AS ctng
ARG BUILD_DIR
ARG USER
USER $USER
ENV BUILD_DIR=$BUILD_DIR

ENTRYPOINT ["/sbin/tini","--"]
