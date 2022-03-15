#!/bin/sh

sudo apt install qemu-user-static

mkdir -p chrootdir/tmp chrootdir/dev chrootdir/proc sfsmnt upper/usr/bin work upper/run/systemd

# Move QEMU to the chroot directory
cp /usr/bin/qemu-aarch64-static upper/usr/bin

# Mount up the chroot
sudo mount -t squashfs "bionic-server-cloudimg-$1.squashfs" sfsmnt
sudo mount -t overlay overlay -olowerdir=sfsmnt,upperdir=upper,workdir=work chrootdir

sudo mount -o bind /proc chrootdir/proc/
sudo mount --rbind /run/systemd chrootdir/run/systemd

# Everything below will be run inside the chroot
cat << EOF | sudo chroot chrootdir /bin/bash
sudo apt install libssl-dev libluajit-5.1-dev libcurl4-openssl-dev zlib1g-dev \
    libsdl2-dev pkg-config ccache python3-pip git libfftw3-dev
sudo pip3 install meson ninja

wget https://raw.githubusercontent.com/mgord9518/Powder_Toy.AppImage/main/build.sh
sh build.sh
EOF
