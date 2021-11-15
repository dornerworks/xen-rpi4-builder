#!/bin/bash -eux

# SPDX-License-Identifier: MIT

# Copyright (c) 2019, DornerWorks, Ltd.
# Author: Stewart Hildebrand

# Usage:
# $ source toolchain-aarch64-linux-gnu.sh
# or
# $ . toolchain-aarch64-linux-gnu.sh

# This script must reside in a writeable directory

# https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-a/downloads

ARM64_TOOLCHAIN_WRKDIR=$(pwd)/
ARM64_TOOLCHAIN_SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE}) && pwd)/

if ! which ccache > /dev/null; then
    sudo apt install ccache
fi

if [ ! -h /usr/lib/ccache/aarch64-none-linux-gnu-gcc ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/aarch64-none-linux-gnu-gcc
fi

if [ ! -h /usr/lib/ccache/aarch64-none-linux-gnu-g++ ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/aarch64-none-linux-gnu-g++
fi


if [ -z "${ARM64_TOOLCHAIN_VERSION-}" ]; then

    ARM64_TOOLCHAIN_VERSION="9.2-2019.12"
    ARM64_TOOLCHAIN_FILENAME=gcc-arm-${ARM64_TOOLCHAIN_VERSION}-x86_64-aarch64-none-linux-gnu

    if [ ! -d ${ARM64_TOOLCHAIN_SCRIPTDIR}${ARM64_TOOLCHAIN_FILENAME} ]; then
        cd ${ARM64_TOOLCHAIN_SCRIPTDIR}
        if [ ! -s ${ARM64_TOOLCHAIN_FILENAME}.tar.xz ]; then
            wget https://developer.arm.com/-/media/Files/downloads/gnu-a/${ARM64_TOOLCHAIN_VERSION}/binrel/${ARM64_TOOLCHAIN_FILENAME}.tar.xz
        fi
        tar -xf ${ARM64_TOOLCHAIN_FILENAME}.tar.xz
        cd ${ARM64_TOOLCHAIN_WRKDIR}
    fi

    PATH=/usr/lib/ccache:${ARM64_TOOLCHAIN_SCRIPTDIR}${ARM64_TOOLCHAIN_FILENAME}/bin:$(echo ${PATH} | sed 's|/usr/lib/ccache:||g')

fi
