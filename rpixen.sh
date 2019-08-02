#!/bin/bash -eux

# SPDX-License-Identifier: MIT

# Copyright (c) 2019, DornerWorks, Ltd.
# Author: Stewart Hildebrand

WRKDIR=$(pwd)/
SCRIPTDIR=$(cd $(dirname $0) && pwd)/

USERNAME=dornerworks
PASSWORD=dornerworks
SALT=dw
HASHED_PASSWORD=$(perl -e "print crypt(\"${PASSWORD}\",\"${SALT}\");")
HOSTNAME=ubuntu

BUILD_ARCH=${1:-arm64}

sudo apt install device-tree-compiler tftpd-hpa flex bison qemu-utils kpartx git curl qemu-user-static binfmt-support parted bc libncurses5-dev libssl-dev pkg-config

source ${SCRIPTDIR}toolchain-aarch64-linux-gnu.sh
source ${SCRIPTDIR}toolchain-arm-linux-gnueabihf.sh

DTBFILE=bcm2711-rpi-4-b-xen.dtb
XEN_ADDR=0x00200000

# Clone sources
if [ ! -d firmware ]; then
    git clone --depth 1 https://github.com/raspberrypi/firmware.git
fi

if [ ! -d xen ]; then
    git clone git://xenbits.xen.org/xen.git
    cd xen
    git checkout staging-4.12
    git am ${SCRIPTDIR}patches/xen/0001-ns16550-Add-compatible-string-for-Raspberry-Pi-4.patch
    git am ${SCRIPTDIR}patches/xen/0002-xen-arm-platform-Add-Raspberry-Pi-platform.patch
    cd ${WRKDIR}
fi

if [ ! -d linux ]; then
    git clone --depth 1 --branch rpi-4.19.y https://github.com/raspberrypi/linux.git linux
    cd linux
    git am ${SCRIPTDIR}patches/linux/0001-Add-RPi4-bcm2711-device-tree-for-Xen-64-bit-Linux.patch
    git am ${SCRIPTDIR}patches/linux/0002-Disable-DMA-in-sdhci-driver.patch
    git am ${SCRIPTDIR}patches/linux/0003-Fix-PCIe-in-dom0-for-RPi4.patch
    git am ${SCRIPTDIR}patches/linux/0004-Add-RPi4-bcm2711-device-tree-for-Xen-32-bit-Linux.patch
    cd ${WRKDIR}
fi


# Build xen
if [ ! -s ${WRKDIR}xen/xen/xen ]; then
    cd ${WRKDIR}xen
    if [ ! -s xen/.config ]; then
        echo "CONFIG_DEBUG=y" > xen/arch/arm/configs/arm64_defconfig
        echo "CONFIG_SCHED_ARINC653=y" >> xen/arch/arm/configs/arm64_defconfig
        make -C xen XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CONFIG_EARLY_PRINTK=8250,0xfe215040,2 defconfig
    fi
    make XEN_TARGET_ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- CONFIG_EARLY_PRINTK=8250,0xfe215040,2 dist-xen -j $(nproc)
    cd ${WRKDIR}
fi

# Build Linux
cd ${WRKDIR}linux
if [ "${BUILD_ARCH}" == "arm64" ]; then
    if [ ! -s ${WRKDIR}linux/.build-arm64/.config ]; then
        # utilize kernel/configs/xen.config fragment
        make O=.build-arm64 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- bcm2711_defconfig xen.config
    fi
    make O=.build-arm64 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j $(nproc) broadcom/${DTBFILE}
    if [ ! -s ${WRKDIR}linux/.build-arm64/arch/arm64/boot/Image ]; then
        echo "Building kernel. This takes a while. To monitor progress, open a new terminal and use \"tail -f buildoutput.log\""
        make O=.build-arm64 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- -j $(nproc) > ${WRKDIR}buildoutput.log 2> ${WRKDIR}buildoutput2.log
    fi
elif [ "${BUILD_ARCH}" == "armhf" ]; then
    if [ ! -s ${WRKDIR}linux/.build-arm32/.config ]; then
        # utilize kernel/configs/xen.config fragment
        make O=.build-arm32 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- bcm2711_defconfig xen.config
    fi
    make O=.build-arm32 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(nproc) ${DTBFILE}
    if [ ! -s ${WRKDIR}linux/.build-arm32/arch/arm/boot/zImage ]; then
        echo "Building kernel. This takes a while. To monitor progress, open a new terminal and use \"tail -f buildoutput.log\""
        make O=.build-arm32 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- -j $(nproc) zImage modules dtbs > ${WRKDIR}buildoutput.log 2> ${WRKDIR}buildoutput2.log
    fi
fi
cd ${WRKDIR}


if [ ! -d bootfiles ]; then
    mkdir bootfiles
fi

cp ${WRKDIR}firmware/boot/fixup4*.dat ${WRKDIR}firmware/boot/start4*.elf bootfiles/

if [ "${BUILD_ARCH}" == "arm64" ]; then
cp ${WRKDIR}linux/.build-arm64/arch/arm64/boot/dts/broadcom/${DTBFILE} bootfiles/
elif [ "${BUILD_ARCH}" == "armhf" ]; then
cp ${WRKDIR}linux/.build-arm32/arch/arm/boot/dts/${DTBFILE} bootfiles/
fi

cat > bootfiles/cmdline.txt <<EOF
console=hvc0 clk_ignore_unused root=/dev/mmcblk0p2 rootwait
EOF

# https://www.raspberrypi.org/documentation/configuration/config-txt/boot.md
# the boot image must be named kernel8.img for the fsbl to load it in 64-bit mode
# Xen must be placed on a 2M boundary
cat > bootfiles/config.txt <<EOF
kernel=kernel8.img
arm_64bit=1
kernel_address=${XEN_ADDR}
device_tree=${DTBFILE}
total_mem=1024
enable_gic=1

#disable_overscan=1

# Enable audio (loads snd_bcm2835)
dtparam=audio=on

[pi4]
max_framebuffers=2

[all]

enable_jtag_gpio=1
enable_uart=1
init_uart_baud=115200
EOF

# 18MiB worth of zeros
dd if=/dev/zero of=bootfiles/kernel8.img bs=1024 count=18432

# Assuming xen is less than 2MiB in size
dd if=${WRKDIR}xen/xen/xen of=bootfiles/kernel8.img bs=1024 conv=notrunc

if [ "${BUILD_ARCH}" == "arm64" ]; then
# Assuming linux is less than 15.5MiB in size
# Image is offset by 2.5MiB from the beginning of the file
dd if=${WRKDIR}linux/.build-arm64/arch/arm64/boot/Image of=bootfiles/kernel8.img bs=1024 seek=2560 conv=notrunc
elif [ "${BUILD_ARCH}" == "armhf" ]; then
# Assuming linux is less than 16MiB in size
# Image is offset by 2MiB from the beginning of the file
dd if=${WRKDIR}linux/.build-arm32/arch/arm/boot/zImage of=bootfiles/kernel8.img bs=1024 seek=2048 conv=notrunc
fi

if [ -d /media/${USER}/boot/ ]; then
    cp bootfiles/* /media/${USER}/boot/
    sync
fi

if [ "${BUILD_ARCH}" == "armhf" ]; then
    # The rest of the script assumes aarch64, so just exit for now
    exit
fi

ROOTFS=ubuntu-base-18.04.2-base-arm64-prepped.tar.gz
if [ ! -s ${ROOTFS} ]; then
    ./ubuntu-base-prep.sh
fi


MNTRAMDISK=/mnt/ramdisk/
MNTROOTFS=/mnt/rpi-arm64-rootfs/
MNTBOOT=${MNTROOTFS}boot/
IMGFILE=${MNTRAMDISK}rpixen.img

unmountstuff () {
  sudo umount ${MNTROOTFS}proc || true
  sudo umount ${MNTROOTFS}dev/pts || true
  sudo umount ${MNTROOTFS}dev || true
  sudo umount ${MNTROOTFS}sys || true
  sudo umount ${MNTROOTFS}tmp || true
  sudo umount ${MNTBOOT} || true
  sudo umount ${MNTROOTFS} || true
}

mountstuff () {
  sudo mkdir -p ${MNTROOTFS}
  if ! mount | grep ${LOOPDEVROOTFS}; then
    sudo mount ${LOOPDEVROOTFS} ${MNTROOTFS}
  fi
  sudo mkdir -p ${MNTBOOT}
  sudo mount ${LOOPDEVBOOT} ${MNTBOOT}
  sudo mount -o bind /proc ${MNTROOTFS}proc
  sudo mount -o bind /dev ${MNTROOTFS}dev
  sudo mount -o bind /dev/pts ${MNTROOTFS}dev/pts
  sudo mount -o bind /sys ${MNTROOTFS}sys
  sudo mount -o bind /tmp ${MNTROOTFS}tmp
}

finish () {
  cd ${WRKDIR}
  sudo sync
  unmountstuff
  sudo kpartx -dvs ${IMGFILE} || true
  sudo rmdir ${MNTROOTFS} || true
  mv ${IMGFILE} . || true
  sudo umount ${MNTRAMDISK} || true
  sudo rmdir ${MNTRAMDISK} || true
}

trap finish EXIT


sudo mkdir -p ${MNTRAMDISK}
sudo mount -t tmpfs -o size=3g tmpfs ${MNTRAMDISK}

qemu-img create ${IMGFILE} 2048M
/sbin/parted ${IMGFILE} --script -- mklabel msdos
/sbin/parted ${IMGFILE} --script -- mkpart primary fat32 2048s 264191s
/sbin/parted ${IMGFILE} --script -- mkpart primary ext4 264192s -1s

LOOPDEVS=$(sudo kpartx -avs ${IMGFILE} | awk '{print $3}')
LOOPDEVBOOT=/dev/mapper/$(echo ${LOOPDEVS} | awk '{print $1}')
LOOPDEVROOTFS=/dev/mapper/$(echo ${LOOPDEVS} | awk '{print $2}')

sudo mkfs.vfat ${LOOPDEVBOOT}
sudo mkfs.ext4 ${LOOPDEVROOTFS}

sudo fatlabel ${LOOPDEVBOOT} boot
sudo e2label ${LOOPDEVROOTFS} RpiUbuntu

sudo mkdir -p ${MNTROOTFS}
sudo mount ${LOOPDEVROOTFS} ${MNTROOTFS}

sudo tar -C ${MNTROOTFS} -xf ${ROOTFS}

mountstuff

sudo cp $(which qemu-aarch64-static) ${MNTROOTFS}usr/bin/

sudo cp bootfiles/* ${MNTBOOT}

cd ${WRKDIR}linux
if [ "${BUILD_ARCH}" == "arm64" ]; then
sudo --preserve-env PATH=${PATH} make O=.build-arm64 ARCH=arm64 CROSS_COMPILE=aarch64-linux-gnu- INSTALL_MOD_PATH=${MNTROOTFS} modules_install > ${WRKDIR}modules_install.log
elif [ "${BUILD_ARCH}" == "armhf" ]; then
sudo --preserve-env PATH=${PATH} make O=.build-arm32 ARCH=arm CROSS_COMPILE=arm-linux-gnueabihf- INSTALL_MOD_PATH=${MNTROOTFS} modules_install > ${WRKDIR}modules_install.log
fi
cd ${WRKDIR}

# /etc/resolv.conf is required for internet connectivity in chroot. It will get overwritten by dhcp, so don't get too attached to it.
sudo chroot ${MNTROOTFS} bash -c 'echo "nameserver 8.8.8.8" > /etc/resolv.conf'
sudo chroot ${MNTROOTFS} bash -c 'echo "nameserver 2001:4860:4860::8888" >> /etc/resolv.conf'

sudo sed -i -e "s/# deb /deb /" ${MNTROOTFS}etc/apt/sources.list
sudo chroot ${MNTROOTFS} apt-get update

# Install the dialog package and others first to squelch some warnings
sudo chroot ${MNTROOTFS} apt-get -y install dialog apt-utils
sudo chroot ${MNTROOTFS} apt-get -y upgrade
sudo chroot ${MNTROOTFS} apt-get -y install systemd systemd-sysv sysvinit-utils sudo udev rsyslog kmod util-linux sed netbase dnsutils ifupdown isc-dhcp-client isc-dhcp-common less vim net-tools iproute2 iputils-ping libnss-mdns iw software-properties-common ethtool dmsetup hostname iptables logrotate lsb-base lsb-release plymouth psmisc tar tcpd libsystemd-dev symlinks uuid-dev libc6-dev libncurses-dev libglib2.0-dev build-essential bridge-utils zlib1g-dev patch libpixman-1-dev libyajl-dev libfdt-dev libaio-dev git libusb-1.0-0-dev libpulse-dev

# Change the shared library symlinks to relative instead of absolute so they play nice with cross-compiling
sudo chroot ${MNTROOTFS} symlinks -c /usr/lib/aarch64-linux-gnu/

cd ${WRKDIR}xen

# TODO: --with-xenstored=oxenstored

# Ask the native compiler what system include directories it searches through.
SYSINCDIRS=$(echo $(sudo chroot ${MNTROOTFS} bash -c "echo | gcc -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem${MNTROOTFS}|"))
SYSINCDIRSCXX=$(echo $(sudo chroot ${MNTROOTFS} bash -c "echo | g++ -x c++ -E -Wp,-v -o /dev/null - 2>&1" | grep "^ " | sed "s|^ /| -isystem${MNTROOTFS}|"))

LDFLAGS="-Wl,-rpath-link=${MNTROOTFS}lib/aarch64-linux-gnu -Wl,-rpath-link=${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
./configure \
    PYTHON_PREFIX_ARG=--install-layout=deb \
    --enable-systemd \
    --disable-xen \
    --enable-tools \
    --disable-docs \
    --disable-stubdom \
    --prefix=/usr \
    --with-xenstored=xenstored \
    --build=x86_64-linux-gnu \
    --host=aarch64-linux-gnu \
    CC="aarch64-linux-gnu-gcc --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRS} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    CXX="aarch64-linux-gnu-g++ --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRSCXX} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    PKG_CONFIG_PATH=${MNTROOTFS}usr/lib/aarch64-linux-gnu/pkgconfig:${MNTROOTFS}usr/share/pkgconfig

PKG_CONFIG=pkg-config \
LDFLAGS="-Wl,-rpath-link=${MNTROOTFS}lib/aarch64-linux-gnu -Wl,-rpath-link=${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
make dist-tools \
    CROSS_COMPILE=aarch64-linux-gnu- XEN_TARGET_ARCH=arm64 \
    CC="aarch64-linux-gnu-gcc --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRS} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    CXX="aarch64-linux-gnu-g++ --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRSCXX} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    PKG_CONFIG_PATH=${MNTROOTFS}usr/lib/aarch64-linux-gnu/pkgconfig:${MNTROOTFS}usr/share/pkgconfig \
    QEMU_PKG_CONFIG_FLAGS=--define-variable=prefix=${MNTROOTFS}usr \
    -j $(nproc)

sudo --preserve-env PATH=${PATH} \
PKG_CONFIG=pkg-config \
LDFLAGS="-Wl,-rpath-link=${MNTROOTFS}lib/aarch64-linux-gnu -Wl,-rpath-link=${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
make install-tools \
    CROSS_COMPILE=aarch64-linux-gnu- XEN_TARGET_ARCH=arm64 \
    CC="aarch64-linux-gnu-gcc --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRS} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    CXX="aarch64-linux-gnu-g++ --sysroot=${MNTROOTFS} -nostdinc ${SYSINCDIRSCXX} -B${MNTROOTFS}lib/aarch64-linux-gnu -B${MNTROOTFS}usr/lib/aarch64-linux-gnu" \
    PKG_CONFIG_PATH=${MNTROOTFS}usr/lib/aarch64-linux-gnu/pkgconfig:${MNTROOTFS}usr/share/pkgconfig \
    QEMU_PKG_CONFIG_FLAGS=--define-variable=prefix=${MNTROOTFS}usr \
    DESTDIR=${MNTROOTFS}

sudo chroot ${MNTROOTFS} systemctl enable xen-qemu-dom0-disk-backend.service
sudo chroot ${MNTROOTFS} systemctl enable xen-init-dom0.service
sudo chroot ${MNTROOTFS} systemctl enable xenconsoled.service
sudo chroot ${MNTROOTFS} systemctl enable xendomains.service
sudo chroot ${MNTROOTFS} systemctl enable xen-watchdog.service

cd ${WRKDIR}

# It seems like the xen tools configure script selects a few too many of these backend driver modules, so we override it with a simpler list.
# /usr/lib/modules-load.d/xen.conf
sudo bash -c "cat > ${MNTROOTFS}usr/lib/modules-load.d/xen.conf" <<EOF
xen-evtchn
xen-gntdev
xen-gntalloc
xen-blkback
xen-netback
EOF

# /etc/hostname
sudo bash -c "echo ${HOSTNAME} > ${MNTROOTFS}etc/hostname"

# /etc/hosts
sudo bash -c "cat > ${MNTROOTFS}etc/hosts" <<EOF
127.0.0.1	localhost
127.0.1.1	${HOSTNAME}

# The following lines are desirable for IPv6 capable hosts
::1     ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# /etc/fstab
sudo bash -c "cat > ${MNTROOTFS}etc/fstab" <<EOF
proc            /proc           proc    defaults          0       0
/dev/mmcblk0p1  /boot           vfat    defaults          0       2
/dev/mmcblk0p2  /               ext4    defaults,noatime  0       1
EOF

# /etc/network/interfaces.d/eth0
sudo bash -c "cat > ${MNTROOTFS}etc/network/interfaces.d/eth0" <<EOF
auto eth0
iface eth0 inet manual
EOF
sudo chmod 0644 ${MNTROOTFS}etc/network/interfaces.d/eth0

# /etc/network/interfaces.d/xenbr0
sudo bash -c "cat > ${MNTROOTFS}etc/network/interfaces.d/xenbr0" <<EOF
auto xenbr0
iface xenbr0 inet dhcp
    bridge_ports eth0
EOF
sudo chmod 0644 ${MNTROOTFS}etc/network/interfaces.d/xenbr0

# Don't wait forever and a day for the network to come online
if [ -s ${MNTROOTFS}lib/systemd/system/networking.service ]; then
    sudo sed -i -e "s/TimeoutStartSec=5min/TimeoutStartSec=15sec/" ${MNTROOTFS}lib/systemd/system/networking.service
fi
if [ -s ${MNTROOTFS}lib/systemd/system/ifup@.service ]; then
    sudo bash -c "echo \"TimeoutStopSec=15s\" >> ${MNTROOTFS}lib/systemd/system/ifup@.service"
fi

# User account setup
sudo chroot ${MNTROOTFS} useradd -s /bin/bash -G adm,sudo -l -m -p ${HASHED_PASSWORD} ${USERNAME}
# Password-less sudo
sudo chroot ${MNTROOTFS} /bin/bash -euxc "echo \"${USERNAME} ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/90-${USERNAME}-user"

df -h | grep -e "Filesystem" -e "/dev/mapper/loop"
