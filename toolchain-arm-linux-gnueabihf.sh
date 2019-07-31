#!/bin/bash -eux

# SPDX-License-Identifier: MIT

# Copyright (c) 2019, DornerWorks, Ltd.
# Author: Stewart Hildebrand

# Usage:
# $ source toolchain-arm-linux-gnueabihf.sh
# or
# $ . toolchain-arm-linux-gnueabihf.sh

# This script must reside in a writeable directory

# https://developer.arm.com/tools-and-software/open-source-software/developer-tools/gnu-toolchain/gnu-a/downloads

ARM32_TOOLCHAIN_WRKDIR=$(pwd)/
ARM32_TOOLCHAIN_SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE}) && pwd)/

if ! which ccache > /dev/null; then
    sudo apt install ccache
fi

if [ ! -h /usr/lib/ccache/arm-linux-gnueabihf-gcc ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/arm-linux-gnueabihf-gcc
fi

if [ ! -h /usr/lib/ccache/arm-linux-gnueabihf-g++ ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/arm-linux-gnueabihf-g++
fi


if [ -z "${ARM32_TOOLCHAIN_VERSION-}" ]; then

    ARM32_TOOLCHAIN_VERSION=8.3-2019.03
    ARM32_TOOLCHAIN_FILENAME=gcc-arm-8.3-2019.03-x86_64-arm-linux-gnueabihf

    if [ ! -d ${ARM32_TOOLCHAIN_SCRIPTDIR}${ARM32_TOOLCHAIN_FILENAME} ]; then
        cd ${ARM32_TOOLCHAIN_SCRIPTDIR}
        if [ ! -s ${ARM32_TOOLCHAIN_FILENAME}.tar.xz ]; then
            wget https://developer.arm.com/-/media/Files/downloads/gnu-a/${ARM32_TOOLCHAIN_VERSION}/binrel/${ARM32_TOOLCHAIN_FILENAME}.tar.xz
        fi
        tar -xf ${ARM32_TOOLCHAIN_FILENAME}.tar.xz
        cd ${ARM32_TOOLCHAIN_WRKDIR}
    fi

    PATH=/usr/lib/ccache:${ARM32_TOOLCHAIN_SCRIPTDIR}${ARM32_TOOLCHAIN_FILENAME}/bin:$(echo ${PATH} | sed 's|/usr/lib/ccache:||g')

fi
