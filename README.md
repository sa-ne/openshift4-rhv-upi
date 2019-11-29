# Provisioning OpenShift 4.2 on RHV Using Baremetal UPI

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.2 on RHV.

_NOTE: Updated to include 4.2 bits on 11-10-2019_

## Background

The playbooks/scripts in this repository should help you automate the vast majority of an OpenShift 4.2 UPI deployment on RHV. Be sure to read the requirements section below. My initial installation of OCP 4.2 on RHV was a little cumbersome, so I opted to automate the majority of the installation to allow for iterative deployments.

The biggest challenge was the installation of the Red Hat Enterprise Linux CoreOS (RHCOS) nodes themselves and that is the focal point of the automation. The playbooks/scripts provided are essentially an automated walk through of the standard baremetal UPI installation instructions but tailored for RHV.

To automate the deployment of RHCOS, the standard boot ISO is modified so the installation automatically starts with specific kernel parameters. The parameters for each node type (bootstrap, masters and workers) are the same with the exception of  `coreos.inst.ignition_url`. To simplify the process, the boot ISO is made to reference a PHP script that offers up the correct ignition config based on the requesting hosts DNS name. This method allows the same boot ISO to be used for each node type.

Before provisioning the RHCOS nodes a lot of prep work needs to be completed. This includes creating the proper DNS entries for the environment, configuring a DHCP server, configuring a load balancer and configuring a web server to store ignition configs and other installation artifacts. Ansible playbooks are provided to automate much of this process.

## Specific Automations

* Deployment of RHCOS on RHV
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

Read through the [Installing on baremetal](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.2/html-single/installing/index#installing-bare-metal) installation documentation before proceeding.

## Clone this Repository

Find a good working directory and clone this repository using the following command:

```console
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
|installation_directory|The directory that you will be using with `openshift-install` command for generating ignition files|

For the individual node configuration, be sure to update the hosts in the `pg` hostgroup. Several parameters will need to be changed for _each_ host including `ip`, `storage_domain` and `network`. You can also specify `mac_address` for each of the VMs in its `network` section (if you don't, VMs will obtain their MAC address from cluster's MAC pool automatically). Match up your RHV environment with the inventory file.

Under the `webserver` and `loadbalancer` group include the FQDN of each host. Also make sure you configure the `httpd_port` variable for the web server host. In this example, the web server that will serve up installation artifacts and load balancer (HAProxy) are the same host.

## Creating an Ansible Vault

In the directory that contains your cloned copy of this git repo, create an Ansible vault called vault.yml as follows:

```console
$ ansible-vault create vault.yml
```

The vault requires the following variables. Adjust the values to suit your environment.

```yaml
---
rhv_hostname: "rhevm.pwc.umbrella.local"
rhv_username: "admin@internal"
rhv_password: "changeme"
ipa_hostname: "idm1.umbrella.local"
ipa_username: "admin"
ipa_password: "changeme"
```

## Download the OpenShift Installer

The OpenShift Installer releases are stored [here](https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/). Find the installer, right click on the "Download Now" button and select copy link. Then pull the installer using curl (be sure to quote the URL) as shown (linux client used as example):

```console
$ curl -o openshift-install-linux-4.2.0.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.2.0.tar.gz
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

Your pull secret can be obtained from the [OpenShift start page](https://cloud.redhat.com/openshift/install/metal/user-provisioned).

```console
$ ./openshift-install create ignition-configs --dir=/home/chris/upi/rhv-upi
```

## Staging Content

Next we need the RHCOS image. These images are stored [here](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/). On our web server, download the RHCOS image (BIOS, not UEFI) to the document root (assuming `/var/www/html`).

_NOTE: You may be wondering about SELinux contexts since httpd is not installed. Fear not, our playbooks will handle that during the installation phase._

```console
$ sudo mkdir -p /var/www/html
```

```console
$ sudo curl -o /var/www/html/rhcos-4.2.0-x86_64-metal-bios.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/rhcos-4.2.0-x86_64-metal-bios.raw.gz
```

Ignition files generated in the previous step will be copied to web server automatically as part of `httpd` role. If you intend to skip that role, copy bootstrap.ign, master.ign and worker.ign from your working directory to `/var/www/html` on your web server manually now.

## Generating Boot ISOs

We will use a bootable ISO to install RHCOS on our virtual machines. We need to pass several parameters to the kernel (see below). This can be cumbersome, so to speed things along we will generate a single boot ISO that can be used for bootstrap, master and worker nodes. During the installation, a playbook will install the PHP script on your web server. This script will serve up the appropriate ignition config based on the requesting servers DNS name.

__Kernel Parameters__

Note these parameters are for reference only. Specify the appropriate values for your environment in the `iso-generator.sh` and run the script to generate an ISO specific to your environment.

* coreos.inst=yes
* coreos.inst.install\_dev=sda
* coreos.inst.image\_url=http://example.com/rhcos-410.8.20190418.1-metal-bios.raw.gz
* coreos.inst.ignition\_url=http://example.com/ignition-downloader.php

### Obtaining RHCOS Install ISO

Next we need the RHCOS ISO installer (stored [here](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/)). Download the ISO file as shown. Be sure to check the directory for the latest version.

```console
$ curl -o /tmp/rhcos-4.2.0-x86_64-installer.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.2/latest/rhcos-4.2.0-x86_64-installer.iso
```

### Modifying the ISO

A script is provided to recreate an ISO that will automatically boot with the appropriate kernel parameters. Locate the script and modify the variables at the top to suite your environment.

Most parameters can be left alone. You WILL need to change at least the `KP_WEBSERVER` variable to point to the web server hosting your ignition configs and RHCOS image.

```shell-script
VERSION=4.2.0-x86_64
ISO_SOURCE=/tmp/rhcos-$VERSION-installer.iso
ISO_OUTPUT=/tmp/rhcos-$VERSION-installer-auto.iso

DIRECTORY_MOUNT=/tmp/rhcos-$VERSION-installer
DIRECTORY_WORKING=/tmp/rhcos-$VERSION-installer-auto

KP_WEBSERVER=lb.rhv-upi.ocp.pwc.umbrella.local:8888
KP_COREOS_IMAGE=rhcos-$VERSION-metal-bios.raw.gz
KP_BLOCK_DEVICE=sda
```

Running the script (make sure to do this as root) should produce similar output:

```console
(rhv) 0 chris@umbrella.local@toaster:~ $ sudo ./iso-generator.sh 
mount: /tmp/rhcos-4.2.0-x86_64-installer: WARNING: device write-protected, mounted read-only.
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
 13.43% done, estimate finish Tue Jun  4 20:28:18 2019
 26.88% done, estimate finish Tue Jun  4 20:28:18 2019
 40.28% done, estimate finish Tue Jun  4 20:28:18 2019
 53.72% done, estimate finish Tue Jun  4 20:28:18 2019
 67.12% done, estimate finish Tue Jun  4 20:28:18 2019
 80.56% done, estimate finish Tue Jun  4 20:28:18 2019
 93.96% done, estimate finish Tue Jun  4 20:28:18 2019
Total translation table size: 2048
Total rockridge attributes bytes: 2086
Total directory bytes: 8192
Path table size(bytes): 66
Max brk space used 1c000
37255 extents written (72 MB)
```

Copy the ISO to your ISO domain in RHV. After that you can cleanup the /tmp directory by doing `rm -rf /tmp/rhcos*`. Make sure to update the `iso_name` variable in your Ansible inventory file with the correct name (`rhcos-4.2.0-x86_64-installer-auto.iso` in this example).

At this point we have completed the staging process and can let Ansible take over.

## Deploying OpenShift 4.2 on RHV with Ansible

To kick off the installation, simply run the provision.yml playbook as follows:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass provision.yml
```

The order of operations for the `provision.yml` playbook is as follows:

* Create DNS Entries in IdM
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

### Skipping Portions of Automation

If you already have your own DNS, DHCP or Load Balancer you can skip those portions of the automation by passing the appropriate `--skip-tags` argument to the `ansible-playbook` command.

Each step of the automation is placed in its own role. Each is tagged ipa, dhcpd and haproxy. If you have your own DHCP configured, you can skip that portion as follows:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass --skip-tags dhcpd provision.yml
```

All three roles could be skipped using the following command:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass --skip-tags dhcpd,ipa,haproxy provision.yml
```

## Finishing the Deployment

Once the VMs boot RHCOS will be installed and nodes will automatically start configuring themselves. From this point we are essentially following the Baremetal UPI instructions starting with [Creating the Cluster](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.2/html-single/installing/index#installation-installing-bare-metal_installing-bare-metal).

Run the following command to ensure the bootstrap process completes (be sure to adjust the `--dir` flag with your working directory):

```console
$ ./openshift-install --dir=/home/chris/upi/rhv-upi wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.rhv-upi.ocp.pwc.umbrella.local:6443... 
INFO API v1.13.4+f2cc675 up                       
INFO Waiting up to 30m0s for bootstrapping to complete... 
INFO It is now safe to remove the bootstrap resources
```

Once this openshift-install command completes successfully, login to the load balancer and comment out the references to the bootstrap server in `/etc/haproxy/haproxy.cfg`. There should be two references, one in the backend configuration `backend_22623` and one in the backend configuration `backend_6443`. Alternativaly, you can just run this utility playbook to achieve the same:

```console
ansible-playbook -i inventory.yml bootstrap_cleanup.yml
```

Lastly, refer to the baremetal UPI documentation and complete [Logging into the cluster](https://docs.openshift.com/container-platform/4.2/installing/installing_bare_metal/installing-bare-metal.html#cli-logging-in-kubeadmin_installing-bare-metal) and all remaining steps.

# Retiring

Playbooks are also provided to remove VMs from RHV and DNS entries from IdM. To do this, run the retirement playbook as follows:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass retire.yml
```
