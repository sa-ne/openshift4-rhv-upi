# Provisioning OpenShift 4.1 on RHV Using Baremetal UPI

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.1 on RHV.

## Background

The playbooks/scripts in this repository should help you automate the vast majority of an OpenShift 4.1 UPI deployment on RHV. Be sure to read the requirements section below. My initial installation of OCP 4.1 on RHV was a little cumbersome, so I opted to automate the majority of the installation to allow for iterative deployments.

The biggest challenge was the installation of the CoreOS nodes themselves and that is the focal point of the automation. The playbooks/scripts provided are essentially an automated walk through of the standard baremetal UPI installation instructions but tailored for RHV.

To automate the deployment of CoreOS, the standard boot ISO is modified so the installation automatically starts with specific kernel parameters. The parameters for each node type (bootstrap, masters and workers) are the same with the exception of  `coreos.inst.ignition_url`. To simplify the process, the boot ISO is made to reference a PHP script that offers up the correct ignition config based on the requesting hosts DNS name. This method allows the same boot ISO to be used for each node type.

Before provisioning the CoreOS nodes a lot of prep work needs to be completed. This includes creating the proper DNS entries for the environment, configuring a DHCP server, configuring a load balancer and configuring a web server to store ignition configs and other installation artifacts. Ansible playbooks are provided to automate much of this process.

## Specific Automations

* Deployment of Red Hat CoreOS on RHV
* Creation of all SRV, A and PTR records in IdM
* Deployment of httpd Server for Installation Artifacts and Logic
* Deployment of HAProxy and Applicable Configuration
* Deployment of dhcpd and Applicable Static IP Assignment
* Ordered Starting (i.e. installation) of VMs

## Requirements

To leverage the automation in this guide you need to bring the following:

* RHV Environment (tested on 4.3)
* IdM Server with DNS Enabled
 * Must have Proper Forward/Reverse Zones Configured
* RHEL 7 Server which will act as a Web Server, Load Balancer and DHCP Server
 * Only Repository Requirement is `rhel-7-server-rpms`

### Naming Convention

All hostnames must follow the following format:

* bootstrap.\<base domain\>
* master0.\<base domain\>
* masterX.\<base domain\>
* worker0.\<base domain\>
* workerX.\<base domain\>

## Noted UPI Installation Issues

* Bootstrap SSL Certificate is only valid for 24 hours
* etcd/master naming convention conforms to 0 based index (i.e. master0, master1, master2...not master1, master2, master3)

# Installing

Read through the [baremetal](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html) UPI installation documentation before proceeding.

## Clone this Repository

Find a good working directory and clone this repository using the following command:

```shell
$ git clone https://github.com/sa-ne/openshift4-rhv-upi.git
```

## Create DNS Zones in IdM

Login to your IdM server and make sure a reverse zone is configured for your subnet. My lab has a subnet of `172.16.10.0` so the corresponding reverse zone is called `10.16.172.in-addr.arpa.`. Make sure a forward zone is configured as well. It should be whatever is defined in the `base_domain` variable in your Ansible inventory file (`rhv-upi.ocp.pwc.umbrella.local` in this example).

## Creating Inventory File for Ansible

An example inventory file is included for Ansible (`inventory-example.yml`). Use this file as a baseline. Make sure to configure the appropriate number of master/worker nodes for your deployment.

The following global variables will need to be modified (the default values are what I use in my lab, consider them examples):

|Variable|Description|
|:---|:---|
|iso_name|The name of the custom ISO file in the RHV ISO domain|
|base\_domain|The base DNS domain. Not to be confused with the base domain in the UPI instructions. Our base\_domain variable in this case is `<cluster_name>`.`<base_domain>`|
|dhcp\_server\_dns\_servers|DNS server assigned by DHCP server|
|dhcp\_server\_gateway|Gateway assigned by DHCP server|
|dhcp\_server\_subnet\_mask|Subnet mask assigned by DHCP server|
|dhcp\_server\_subnet|IP Subnet used to configure dhcpd.conf|
|load\_balancer\_ip|This IP address of your load balancer (the server that HAProxy will be installed on)|

Under the `webserver` and `loadbalancer` group include the FQDN of each host. Also make sure you configure the `httpd_port` variable for the web server host. In this example, the web server that will serve up installation artifacts and load balancer (HAProxy) are the same host.

## Creating an Ansible Vault

In the directory that contains your cloned copy of this git repo, create an Ansible vault called vault.yml as follows:

```shell
$ ansible-vault create vault.yml
```

The vault requires the following variables. Adjust the values to suit your environment.

```yaml
---
rhv_hostname: "rhevm.pwc.umbrella.local"
rhv_username: "admin@internal"
rhv_password: "changeme"
rhv_cluster: "r710s"
ipa_hostname: "idm1.umbrella.local"
ipa_username: "admin"
ipa_password: "changeme"
```

## Download the OpenShift Installer

The OpenShift Installer releases are stored [here](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.1.0-rc.5.tar.gz). Download the installer to your working directory as follows:

```shell
$ curl -O https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.1.0-rc.5.tar.gz
```

Extract the archive and continue.

## Creating Ignition Configs

After you download the installer we need to create our ignition configs using the `openshift-install` command. Create a file called `install-config.yaml` similar to the one show below. This example shows 3 masters and 4 worker nodes.

```yaml
apiVersion: v1
baseDomain: ocp.pwc.umbrella.local
compute:
- name: worker
  replicas: 4
controlPlane:
  name: master
  replicas: 3
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

You will need to modify baseDomain, pullSecret and sshKey (be sure to use your _public_ key) with the appropriate values. Next, copy `install-config.yaml` into your working directory (`/home/chris/upi/rhv-upi` in this example) and run the OpenShift installer as follows to generate your Ignition configs.

```shell
$ ./openshift-installer create ignition-configs --dir=/home/chris/upi/rhv-upi
```

## Staging Content

On our web server, download the CoreOS image to the document root (assuming `/var/www/html`). Be sure to check the directory for the latest version.

_NOTE: You may be wondering about SELinux contexts since httpd is not installed. Fear not, our playbooks will handle that during the installation phase._

```shell
$ sudo mkdir -p /var/www/html
```

```shell
$ sudo curl -kLo /var/www/html/rhcos-410.8.20190520.0-metal-bios.raw.gz https://releases-art-jenkins.cloud.paas.upshift.redhat.com/storage/releases/ootpa/410.8.20190520.0/rhcos-410.8.20190520.0-metal-bios.raw.gz
```

Next copy bootstrap.ign, master.ign and worker.ign from your working directory to `/var/www/html` on your web server.

## Generating Boot ISOs

We will use a bootable ISO to install CoreOS on our virtual machines. We need to pass several parameters to the kernel (see below). This can be cumbersome, so to speed things along we will generate a single boot ISO that can be used for bootstrap, master and worker nodes. During the installation, a playbook will install the PHP script on your web server. This script will serve up the appropriate ignition config based on the requesting servers DNS name.

__Kernel Parameters__

Note these parameters are for reference only. Specify the appropriate values for your environment in the `iso-generator.sh` and run the script to generate an ISO specific to your environment.

* coreos.inst=yes
* coreos.inst.install\_dev=sda
* coreos.inst.image\_url=http://example.com/rhcos-410.8.20190418.1-metal-bios.raw.gz
* coreos.inst.ignition\_url=http://example.com/ignition-downloader.php

### Obtaining Red Hat CoreOS ISO

Download the ISO file as shown. Be sure to check the directory for the latest version.

```shell
$ curl -kJLo /tmp/rhcos-410.8.20190520.0-installer.iso https://releases-art-jenkins.cloud.paas.upshift.redhat.com/storage/releases/ootpa/410.8.20190520.0/rhcos-410.8.20190520.0-installer.iso
```

### Modifying the ISO

A script is provided to recreate an ISO that will automatically boot with the appropriate kernel parameters. Locate the script and modify the variables at the top to suite your environment.

Most parameters can be left alone. You WILL need to change at least the `KP_WEBSERVER` variable to point to the web server hosting your ignition configs and CoreOS image.

```bash
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

```shell
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

Copy the ISO to your ISO domain in RHV. After that you can cleanup the /tmp directory by doing `rm -rf /tmp/rhcos*`. Make sure to update the `iso_name` variable in your Ansible inventory file with the correct name (`rhcos-410.8.20190520.0-installer-auto.iso` in this example).

At this point we have completed the staging process and can let Ansible take over.

## Deploying OpenShift 4.1 on RHV with Ansible

To kick off the installation, simply run the provision.yml playbook as follows:

```shell
$ ansible-playbook -i inventory.yml --ask-vault-pass provision.yml
```

The order of operations for the `provision.yml` playbook is as follows:

* Create DNS Entries in RHV
* Create VMs in RHV
	- Create VMs
	- Create Disks
	- Create NICs
* Configure Load Balancer Host
	- Install and Configure dhcpd
	- Install and Configure HAProxy
	- Install and Configure httpd
* Boot VMs
	- Start bootstrap VM and wait for SSH
	- Start master VMs and wait for SSH
	- Start worker VMs and wait for SSH
	
Once the playbook completes (should several minutes) continue with the instructions.

## Finishing the Deployment

Once the VMs boot CoreOS will be installed and nodes will automatically start configuring themselves. From this point we are essentially following the Baremetal UPI instructions starting with [Creating the Cluster](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#installation-installing-bare-metal_installing-bare-metal).

Run the following command to ensure the bootstrap process completes (be sure to adjust the `--dir` flag with your working directory):

```shell
$ ./openshift-install --dir=/home/chris/upi/rhv-upi wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.rhv-upi.ocp.pwc.umbrella.local:6443... 
INFO API v1.13.4+f2cc675 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
INFO It is now safe to remove the bootstrap resources
```

Once this openshift-install command completes successfully, login to the load balancer and comment out the references to the bootstrap server in `/etc/haproxy/haproxy.cfg`. There should be two references, one in the backend configuration `backend_22623` and one in the backend configuration `backend_6443`.

Lastly, refer to the baremetal UPI documentation and complete [Logging into the cluster](https://docs.openshift.com/container-platform/4.1/installing/installing_bare_metal/installing-bare-metal.html#cli-logging-in-kubeadmin_installing-bare-metal) and all remaining steps.

# Retiring

Playbooks are also provided to remove VMs from RHV and DNS entries from IdM. To do this, run the retirement playbook as follows:

```shell
$ ansible-playbook -i inventory.yml --ask-vault-pass retire.yml
```