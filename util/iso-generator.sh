#!/bin/bash

# Run this script as root

if [ `whoami` != "root" ] ; then
   echo "Must be run as root!"
   exit 1
fi

VERSION=4.4.3-x86_64
ISO_SOURCE=/tmp/rhcos-$VERSION-installer.x86_64.iso
ISO_OUTPUT=/tmp/rhcos-$VERSION-installer.x86_64-auto.iso

DIRECTORY_MOUNT=/tmp/rhcos-$VERSION-installer
DIRECTORY_WORKING=/tmp/rhcos-$VERSION-installer-auto

KP_WEBSERVER=lb.rhv-upi.ocp.pwc.umbrella.local:8080
KP_COREOS_IMAGE=rhcos-$VERSION-metal.x86_64.raw.gz
KP_BLOCK_DEVICE=sda

if [ -d $DIRECTORY_MOUNT ] || [ -d $DIRECTORY_WORKING ] ; then
	echo "$DIRECTORY_MOUNT or $DIRECTORY_WORKING already exist!"
	exit
fi

# Setup

mkdir -p $DIRECTORY_MOUNT $DIRECTORY_WORKING
mount -o loop -t iso9660 $ISO_SOURCE $DIRECTORY_MOUNT

if [ ! -f $DIRECTORY_MOUNT/isolinux/isolinux.cfg ] ; then
	echo "Unexpected contents in $DIRECTORY_MOUNT!"
	exit
fi

rsync -av $DIRECTORY_MOUNT/* $DIRECTORY_WORKING/

# Edit isolinux.cfg

INST_INSTALL_DEV="coreos.inst.install_dev=$KP_BLOCK_DEVICE"
INST_IMAGE_URL="coreos.inst.image_url=http:\/\/$KP_WEBSERVER\/$KP_COREOS_IMAGE"
INST_IGNITION_URL="coreos.inst.ignition_url=http:\/\/$KP_WEBSERVER\/ignition-downloader.php"

sed -i 's/default vesamenu.c32/default linux/' $DIRECTORY_WORKING/isolinux/isolinux.cfg
sed -i 's/timeout 600/timeout 0/' $DIRECTORY_WORKING/isolinux/isolinux.cfg
sed -i "/coreos.inst=yes/s|$| $INST_INSTALL_DEV $INST_IMAGE_URL $INST_IGNITION_URL|" $DIRECTORY_WORKING/isolinux/isolinux.cfg

# Generate new ISO

mkisofs -o $ISO_OUTPUT -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -input-charset utf-8 -JRV CoreOS $DIRECTORY_WORKING/

umount $DIRECTORY_MOUNT

# Cleanup...
# rm -rf $DIRECTORY_MOUNT $DIRECTORY_WORKING
