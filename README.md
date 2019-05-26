# Provisioning OpenShift 4.1 on RHV Using Baremetal UPI

*Note: This document is wholly incomplete and a WIP.*

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.1 on RHV.

## Specific Automations

* Deployment of Red Hat CoreOS on RHV
* Creation of all SRV and A records in IdM
* Generation of HAProxy Load Balancer Configs
* Generation of dhcpd.conf for Static IP Assignment Based on MAC Addresses in RHV

## Noted UPI Installation Issues

* Bootstrap SSL Certificate is only valid for 24 hours
* etcd/master naming convention conforms to 0 based index (i.e. master0, master1, master2...not master1, master2, master3)

# Installing

Read through the [baremetal](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html) UPI installation documentation before proceeding.

## Installing Web Server on Load Balancer

## Creating Ignition Configs

Create a file called `install-config.yaml` similar to the one show below. This example shows 3 masters and 4 worker nodes.

```apiVersion: v1
baseDomain: rhv-upi.ocp.pwc.umbrella.local
compute:
- name: worker
  replicas: 3
controlPlane:
  name: master
  replicas: 4
metadata:
  name: rhv-upi
networking:
  clusterNetworks:
  - cidr: 10.128.0.0/14
    hostPrefix: 23
  networkType: OpenShiftSDN
  serviceNetwork:
  - 172.30.0.0/16
platform:
  none: {}
pullSecret: '{ ... }'
sshKey: 'ssh-rsa ... user@host'
```

You will need to modify baseDomain, pullSecret and sshKey with the appropriate values. Next, copy `install-config.yaml` into your working directory (`/home/chris/openshift4/rhv` in this example) and run the OpenShift installer as follows to generate your Ignition configs.

```bash
openshift-installer create ignition-configs --dir=/home/chris/openshift4/rhv-upi
```

## Staging Content

On our web server, download the CoreOS image to the document root (assuming `/var/www/html`). Be sure to check the directory for the latest version.

```bash
sudo curl -kLo /var/www/html/rhcos-410.8.20190520.0-metal-bios.raw.gz https://releases-art-jenkins.cloud.paas.upshift.redhat.com/storage/releases/ootpa/410.8.20190520.0/rhcos-410.8.20190520.0-metal-bios.raw.gz
```

## Generating Boot ISOs

We will use a bootable ISO to install CoreOS on our virtual machines. We need to pass several parameters to the kernel (see below). This can be cumbersome, so to speed things along we will generate a single boot ISO that can be used for bootstrap, master and worker nodes. Make sure to install the PHP script on your web server. This script will serve up the appropriate ignition config based on the requesting servers DNS name.

__Kernel Parameters__

Note these parameters are for example only. Specify the appropriate values for your environment in the `iso-generator.sh` and run the script to generate an ISO specific to your environment.

* coreos.inst=yes
* coreos.inst.install\_dev=sda
* coreos.inst.image\_url=http://example.com/rhcos-410.8.20190418.1-metal-bios.raw.gz
* coreos.inst.ignition\_url=http://example.com/ignition-downloader.php

### Obtaining Red Hat CoreOS ISO

Download the ISO file as shown. Be sure to check the directory for the latest version.

```bash
curl -kJLo /tmp/rhcos-410.8.20190520.0-installer.iso https://releases-art-jenkins.cloud.paas.upshift.redhat.com/storage/releases/ootpa/410.8.20190520.0/rhcos-410.8.20190520.0-installer.iso
```

### Modifying the ISO

A script is provided to recreate an ISO that will automatically boot with the appropriate kernel parameters. Locate the script and modify the variables at the top to suite your environment.

Most parameters can be left alone. You WILL need to change at least the `KP_WEBSERVER` variable to point to the web server hosting your ignition configs and CoreOS image.

```
VERSION=410.8.20190520.0
ISO_SOURCE=/tmp/rhcos-$VERSION-installer.iso
ISO_OUTPUT=/tmp/rhcos-$VERSION-installer-auto.iso

DIRECTORY_MOUNT=/tmp/rhcos-$VERSION-installer
DIRECTORY_WORKING=/tmp/rhcos-$VERSION-installer-auto

KP_WEBSERVER=lb.rhv-upi.ocp.pwc.umbrella.local:8888
KP_COREOS_IMAGE=rhcos-$VERSION-metal-bios.raw.gz
KP_BLOCK_DEVICE=sda
```

Running the script (make sure to do this as root) should produce similar output:

```
$ sudo ./iso-generator.sh 
mount: /tmp/rhcos-410.8.20190520.0-installer: WARNING: device write-protected, mounted read-only.
sending incremental file list
README.md
EFI/
EFI/fedora/
EFI/fedora/grub.cfg
images/
images/efiboot.img
images/initramfs.img
images/vmlinuz
isolinux/
isolinux/boot.cat
isolinux/boot.msg
isolinux/isolinux.bin
isolinux/isolinux.cfg
isolinux/ldlinux.c32
isolinux/libcom32.c32
isolinux/libutil.c32
isolinux/vesamenu.c32

sent 75,912,546 bytes  received 295 bytes  151,825,682.00 bytes/sec
total size is 75,893,080  speedup is 1.00
Size of boot image is 4 sectors -> No emulation
 13.43% done, estimate finish Sun May 26 15:19:20 2019
 26.88% done, estimate finish Sun May 26 15:19:20 2019
 40.28% done, estimate finish Sun May 26 15:19:20 2019
 53.72% done, estimate finish Sun May 26 15:19:20 2019
 67.12% done, estimate finish Sun May 26 15:19:20 2019
 80.56% done, estimate finish Sun May 26 15:19:20 2019
 93.96% done, estimate finish Sun May 26 15:19:20 2019
Total translation table size: 2048
Total rockridge attributes bytes: 2086
Total directory bytes: 8192
Path table size(bytes): 66
Max brk space used 1c000
37255 extents written (72 MB)
```

Copy the ISO to your ISO domain in RHV. After that you can cleanup the /tmp directory by doing `rm -rf /tmp/rhcos*`.

## Creating Load Balancer w/ HAProxy
TODO

## Creating Environment in RHV
TODO

## Booting up Nodes
TODO

## Running Installer
TODO