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

## Creating Ignition Configs

Create a file called `install-config.yaml` similar to the one show below.

```apiVersion: v1
baseDomain: ocp4.pwc.umbrella.local
compute:
- name: worker
  replicas: 3
controlPlane:
  name: master
  replicas: 3
metadata:
  name: rhv
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
openshift-installer create ignition-configs --dir=/home/chris/openshift4/rhv
```

## Staging Content

On our web server, download the CoreOS image to the document root (assuming `/var/www/html`).

```bash
sudo curl -JLo /var/www/html/rhcos-410.8.20190418.1-metal-bios.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/latest/rhcos-410.8.20190418.1-metal-bios.raw.gz
```

## Generating Boot ISOs

We will use a bootable ISO to install CoreOS on our virtual machines. We need to pass several parameters to the kernel (see below). This can be cumbersome, so to speed things along we will generate boot ISOs for the bootstrap server, master nodes and worker nodes that will automatically boot and install CoreOS.

__Kernel Parameters__

* coreos.inst=yes
* coreos.inst.install\_dev=sda
* coreos.inst.image\_url=http://example.com/rhcos-410.8.20190418.1-metal-bios.raw.gz
* coreos.inst.ignition\_url=http://example.com/config.ign

### Obtaining Red Hat CoreOS ISO

Download the ISO file as shown (be sure to check the directory for the latest version).

```bash
(cd /tmp && curl -J -L -O https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.1/latest/rhcos-410.8.20190418.1-installer.iso)
```

### Modifying the ISO

First we need to mount this ISO and copy its contents so we can modify the boot menu. To do this, mount the iso to `/mnt/tmp`.

```bash
sudo mount -o loop -t iso9660 /tmp/rhcos-410.8.20190418.1-installer.iso /mnt/tmp
```

Next, copy the contents to `/tmp/rhcos`.

```bash
sudo rsync -av /mnt/tmp/* /tmp/rhcos
```

To change the way the ISO boots, we need to modify `/tmp/rhcos/isolinux/isolinux.cfg`. Add prompt=0 and change the timeout field from 600 to 50. Also, modify the kernel parameters as follows (this example will be for the bootstrap server and set `coreos.inst.ignition_url` to point to bootstrap.ign):

```
label linux
  menu label ^Install RHEL CoreOS
  kernel /images/vmlinuz
  append initrd=/images/initramfs.img nomodeset rd.neednet=1 coreos.inst=yes coreos.inst.install_dev=sda coreos.inst.image_url=http://lb.rhv.ocp4.pwc.umbrella.local:8888/rhcos-410.8.20190418.1-metal-bios.raw.gz coreos.inst.ignition_url=http://lb.ocp4.pwc.umbrella.local:8888/bootstrap.ign
```

No we can recreate the ISO as follows:

```bash
mkisofs -o ../rhcos-bootstrap.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table -J -R -V CoreOS .
```
