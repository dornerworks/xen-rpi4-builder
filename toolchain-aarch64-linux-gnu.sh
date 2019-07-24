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

TOOLCHAIN_WRKDIR=$(pwd)/
TOOLCHAIN_SCRIPTDIR=$(cd $(dirname ${BASH_SOURCE}) && pwd)/

if ! which ccache > /dev/null; then
    sudo apt install ccache
fi

if [ ! -h /usr/lib/ccache/aarch64-linux-gnu-gcc ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/aarch64-linux-gnu-gcc
fi

if [ ! -h /usr/lib/ccache/aarch64-linux-gnu-g++ ]; then
    sudo ln -s ../../bin/ccache /usr/lib/ccache/aarch64-linux-gnu-g++
fi


if [ -z "${LINARO_VERSION-}" ]; then

    LINARO_VERSION=8.3-2019.03
    LINARO_FILENAME=gcc-arm-8.3-2019.03-x86_64-aarch64-linux-gnu

    if [ ! -d ${TOOLCHAIN_SCRIPTDIR}${LINARO_FILENAME} ]; then
        cd ${TOOLCHAIN_SCRIPTDIR}
        if [ ! -s ${LINARO_FILENAME}.tar.xz ]; then
            wget https://developer.arm.com/-/media/Files/downloads/gnu-a/${LINARO_VERSION}/binrel/${LINARO_FILENAME}.tar.xz
        fi
        tar -xf ${LINARO_FILENAME}.tar.xz
        cd ${TOOLCHAIN_WRKDIR}
    fi

    PATH=/usr/lib/ccache:${TOOLCHAIN_SCRIPTDIR}${LINARO_FILENAME}/bin:${PATH}

fi
