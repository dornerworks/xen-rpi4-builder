# Build Xen for Raspberry Pi 4

This script builds Xen, a 64-bit linux kernel from the Raspberry Pi tree, and packages a minimal 64-bit Ubuntu 18.04 rootfs for the Raspberry Pi 4.
A recent version of Ubuntu is required to run the build script. An internet connection is required. 8 GB RAM or more is recommended, and 10GB+ free disk space.

Usage:

    $ ./rpixen.sh

When the script is finished, flash to SD card with (for example):

    $ umount /dev/sdX1
    $ umount /dev/sdX2
    $ sudo dd if=rpixen.img of=/dev/sdX bs=8M
    $ sync

Xen will print messages to the UART.

This script is a little bit like [https://github.com/mirage/xen-arm-builder](https://github.com/mirage/xen-arm-builder) and [https://github.com/RPi-Distro/pi-gen](https://github.com/RPi-Distro/pi-gen) but for Xen+Ubuntu instead of Raspbian.
More info about Ubuntu Base is available here [https://wiki.ubuntu.com/Base](https://wiki.ubuntu.com/Base).

## Limitations

* System RAM limited to 1024M
* HDMI not working
* Raspberry Pi kernel not suitable for domU
* aux spi1 and aux spi2 are disabled

## 32-bit Linux

A 32-bit linux kernel may be built by doing:

    $ ./rpixen.sh armhf

Xen will be built for aarch64 regardless.

# Adding Guest domains to Xen on Raspberry Pi

 * Follow instructions in link below
    * https://wiki.xenproject.org/wiki/Xen_on_ARM_and_Yocto
 * bitbake xen-guest-image-minimal
 *  Copy in the built guest filesystem in a file:
    * .../work/raspberrypi4_64-poky-linux/xen-guest-image-minimal/*/deploy-xen-guest-image-minimal-image-complete/xen-guest-image-minimal-raspberrypi4-64.ext3
    * to Domain-0: /home/root/xen-guest-image-minimal-raspberrypi4-64.ext3
 * Copy in the guest kernel file: Image
    * .../work/raspberrypi4_64-poky-linux/linux-raspberrypi/*/deploy-linux-raspberrypi/Image
    * to Domain-0: /home/root/Image
 * Create a new file: guest.cfg
    - kernel = "/home/root/Image"
    - cmdline = "console=hvc0 earlyprintk=xen sync_console root=/dev/xvda"
    - memory = "256"
    - name = "rpi4-xen-guest"
    - vcpus = 1
    - serial="pty"
    - disk = [ 'phy:/dev/loop0,xvda,w' ]
    - vif=[ 'mac=00:11:22:66:88:22,bridge=xenbr0,type=netfront', ]
 * [**OPTIONAL**] Create a bridge and move the eth0 physical device onto it:
    - killall -SIGUSR2 udhcpc                               _# release your existing DHCP lease_
    - brctl addbr xenbr0                                    _# create a new bridge called “xenbr0”_
    - brctl addif xenbr0 eth0                               _# put eth0 onto xenbr0_
    - killall udhcpc                                        _# terminate the DHCP client daemon_
    - udhcpc -R -b -p /var/run/udhcpc.xenbr0.pid -i xenbr0  _# restart the DHCP client daemon on the new bridge_
 * Loopback mount the ext3 guest filesystem file to make it available as a device
    * losetup /dev/loop0 /home/root/xen-guest-image-minimal-raspberrypi4-64.ext3
 * Create Guest
    * xl create -c guest.cfg
 * Console Controls
    * Press `Ctrl + ]` to detach from current guest
    * Type `sudo xl console your-DomU-name` to attach to a specifc guest
    * Type `sudo xl list` to know the domain name or number
    * Type `sudo xl shutdown N` where N is the domain name or number