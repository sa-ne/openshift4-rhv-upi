# Provisioning OpenShift 4.4 on RHV Using Baremetal UPI

This repository contains a set of playbooks to help facilitate the deployment of OpenShift 4.4 on RHV.

## Background

The playbooks/scripts in this repository should help you automate the vast majority of an OpenShift 4.4 UPI deployment on RHV. Be sure to read the requirements section below. My initial installation of OCP on RHV was a little cumbersome, so I opted to automate the majority of the installation to allow for iterative deployments.

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

* RHV Environment (tested on 4.3.9)
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

Read through the [Installing on baremetal](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html-single/installing_on_bare_metal/index) installation documentation before proceeding.

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
|ipa\_validate\_certs|Enable or disable validation of the certificates for your IdM server (default: `yes`)|
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
$ curl -o openshift-install-linux-4.4.3.tar.gz https://mirror.openshift.com/pub/openshift-v4/clients/ocp/latest/openshift-install-linux-4.4.3.tar.gz
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
fips: false
pullSecret: '{ ... }'
sshKey: 'ssh-rsa ... user@host'
```

You will need to modify baseDomain, pullSecret and sshKey (be sure to use your _public_ key) with the appropriate values. Next, copy `install-config.yaml` into your working directory (`/home/chris/upi/rhv-upi` in this example) and run the OpenShift installer as follows to generate your Ignition configs.

Your pull secret can be obtained from the [OpenShift start page](https://cloud.redhat.com/openshift/install/metal/user-provisioned).

```console
$ ./openshift-install create ignition-configs --dir=/home/chris/upi/rhv-upi
```

## Staging Content

Next we need the RHCOS image. These images are stored [here](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.4/latest/). On our web server, download the RHCOS image (BIOS, not UEFI) to the document root (assuming `/var/www/html`).

_NOTE: You may be wondering about SELinux contexts since httpd is not installed. Fear not, our playbooks will handle that during the installation phase._

```console
$ sudo mkdir -p /var/www/html
```

```console
$ sudo curl -o /var/www/html/rhcos-4.4.3-x86_64-metal.x86_64.raw.gz https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/latest/latest/rhcos-4.4.3-x86_64-metal.x86_64.raw.gz
```

Ignition files generated in the previous step will be copied to web server automatically as part of `httpd` role. If you intend to skip that role, copy bootstrap.ign, master.ign and worker.ign from your working directory to `/var/www/html` on your web server manually now.

## Generating Boot ISOs

We will use a bootable ISO to install RHCOS on our virtual machines. We need to pass several parameters to the kernel (see below). This can be cumbersome, so to speed things along we will generate a single boot ISO that can be used for bootstrap, master and worker nodes. During the installation, a playbook will install the PHP script on your web server. This script will serve up the appropriate ignition config based on the requesting servers DNS name.

__Kernel Parameters__

Note these parameters are for reference only. Specify the appropriate values for your environment in `util/iso-generator.sh` and run the script to generate an ISO specific to your environment.

* coreos.inst=yes
* coreos.inst.install\_dev=sda
* coreos.inst.image\_url=http://example.com/rhcos-4.4.3-x86_64-metal.raw.gz
* coreos.inst.ignition\_url=http://example.com/ignition-downloader.php

### Obtaining RHCOS Install ISO

Next we need the RHCOS ISO installer (stored [here](https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.4/latest/)). Download the ISO file as shown. Be sure to check the directory for the latest version.

```console
$ curl -o /tmp/rhcos-4.4.3-x86_64-installer.x86_64.iso https://mirror.openshift.com/pub/openshift-v4/dependencies/rhcos/4.4/latest/rhcos-4.4.3-x86_64-installer.x86_64.iso
```

### Modifying the ISO

A script is provided to recreate an ISO that will automatically boot with the appropriate kernel parameters. Locate the script and modify the variables at the top to suite your environment.

Most parameters can be left alone. You WILL need to change at least the `KP_WEBSERVER` variable to point to the web server hosting your ignition configs and RHCOS image.

```shell-script
VERSION=4.4.3-x86_64
ISO_SOURCE=/tmp/rhcos-$VERSION-installer.x86_64.iso
ISO_OUTPUT=/tmp/rhcos-$VERSION-installer.x86_64-auto.iso

DIRECTORY_MOUNT=/tmp/rhcos-$VERSION-installer
DIRECTORY_WORKING=/tmp/rhcos-$VERSION-installer-auto

KP_WEBSERVER=lb.rhv-upi.ocp.pwc.umbrella.local:8888
KP_COREOS_IMAGE=rhcos-$VERSION-metal.x86_64.raw.gz
KP_BLOCK_DEVICE=sda
```

Running the script (make sure to do this as root) should produce similar output:

```console
<<<<<<< HEAD
(rhv) 0 chris@umbrella.local@toaster:~ $ sudo ./util/iso-generator.sh
mount: /tmp/rhcos-4.3.0-x86_64-installer: WARNING: device write-protected, mounted read-only.
=======
(rhv) 0 chris@umbrella.local@toaster:~ $ sudo ./iso-generator.sh
mount: /tmp/rhcos-4.4.3-x86_64-installer: WARNING: device write-protected, mounted read-only.
>>>>>>> a8694ee2d2d1a85a14ca24fdc4ea7fd1716632e6
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

Copy the ISO to your ISO domain in RHV. After that you can cleanup the /tmp directory by doing `rm -rf /tmp/rhcos*`. Make sure to update the `iso_name` variable in your Ansible inventory file with the correct name (`rhcos-4.4.3-x86_64-installer.x86_64-auto.iso` in this example).

At this point we have completed the staging process and can let Ansible take over.

## Deploying OpenShift 4.4 on RHV with Ansible

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

Once the VMs boot RHCOS will be installed and nodes will automatically start configuring themselves. From this point we are essentially following the Baremetal UPI instructions starting with [Creating the Cluster](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html-single/installing_on_bare_metal/index#installation-installing-bare-metal_installing-bare-metal).

Run the following command to ensure the bootstrap process completes (be sure to adjust the `--dir` flag with your working directory):

```console
$ ./openshift-install --dir=/home/chris/upi/rhv-upi wait-for bootstrap-complete
INFO Waiting up to 30m0s for the Kubernetes API at https://api.rhv-upi.ocp.pwc.umbrella.local:6443...
INFO API v1.17.1+b9b84e0 up                       
INFO Waiting up to 30m0s for bootstrapping to complete...
INFO It is now safe to remove the bootstrap resources
```

Once this openshift-install command completes successfully, login to the load balancer and comment out the references to the bootstrap server in `/etc/haproxy/haproxy.cfg`. There should be two references, one in the backend configuration `backend_22623` and one in the backend configuration `backend_6443`. Alternativaly, you can just run this utility playbook to achieve the same:

```console
ansible-playbook -i inventory.yml bootstrap_cleanup.yml
```

Lastly, refer to the baremetal UPI documentation and complete [Logging into the cluster](https://access.redhat.com/documentation/en-us/openshift_container_platform/4.4/html-single/installing_on_bare_metal/index#cli-logging-in-kubeadmin_installing-bare-metal) and all remaining steps.

# Installing QEMU Guest Agent

RHCOS includes the `open-vm-tools` package by default but does not include `qemu-guest-agent`. To work around this, we can run the `qemu-ga` daemon via a container using a DaemonSet or by copying the `qemu-ga` binary and requisite configuration to RHCOS using a MachineConfig.

## Option 1 - Installing QEMU Guest Agent using a DaemonSet

*Note: The DaemonSet option is not completely working. Guest memory is not reported to RHV. This is a work in progress.*

The Dockerfile used to build the container is included in the `qemu-guest-agent` directory in this git repository. You will need to download the latest `qemu-guest-agent` RPM from access.redhat.com and place it alongside the Dockerfile to successfully build the container. The container was built using buildah as follows:

```console
buildah bud -t qemu-guest-agent --format docker
```

However, building the container is for documentation purposes only. The DaemonSet is already configured to pull the `qemu-guest-agent` container from quay.io.

To start the deployment we need to create the namespace, to do that run the following command:

```console
oc create -f qemu-guest-agent/0-namespace.yaml
```

Next we need to create the service account:

```console
oc create -f qemu-guest-agent/1-service-account.yaml
```

The pods will require the privileged SCC, so add the appropriate RBAC as follows:

```console
oc create -f qemu-guest-agent/2-rbac.yaml
```

Finally deploy the DaemonSet by running:

```console
oc create -f 3-daemonset.yaml
```

## Option 2 - Installing QEMU Guest Agent using MachineConfigs

The following files were extracted from the `qemu-guest-agent` rpm, base64 encoded and added to the ignition portion of the Machine Config.

* /etc/qemu-ga/fsfreeze-hook
* /etc/sysconfig/qemu-ga
* /etc/udev/rules.d/99-qemu-guest-agent.rules
* /usr/bin/qemu-ga

Since the `/usr` filesystem on RHCOS is mounted read-only, the `qemu-ga` binary was placed in `/opt/qemu-guest-agent/bin/qemu-ga`. Left alone the `qemu-guest-agent` service will fail to start because the `qemu-ga` binary does not have the appropriate SELinux contexts. To work around this, an additional service named `qemu-guest-agent-selinux` is added to force the appropriate contexts before the `qemu-guest-agent` services starts. Both services are added via the `systemd` portion of the ignition config.

To add the `qemu-guest-agent` service to your worker nodes, simply run the following command:

```console
oc create -f 50-worker-qemu-guest-agent.yaml
```

When applied, the Machine Config Operator will perform a rolling reboot of all worker nodes in your cluster.

Similarly, the `qemu-guest-agent` service can be applied to your master nodes using the following command:

```console
oc create -f 50-master-qemu-guest-agent.yaml
```

# Installing OpenShift Container Storage (OCS)

This guide will show you how to deploy OpenShift Container Storage (OCS) using a bare metal methodology and local storage.

## Requirements

For typical deployments, OCS will require three dedicated worker nodes with the following VM specs:

* 48GB RAM
* 12 vCPU
* 1 OSD Disk (300Gi)
* 1 MON Disk (10Gi)

The OSD disks can really be any size but 300Gi is used in this example. Also, an example inventory file (`ocs/inventory-example-ocs.yaml`) that shows how to add multiple disks to a worker node is included in the root of this repository.

## Labeling Nodes

Before we begin an installation, we need to label our OCS nodes with the label `cluster.ocs.openshift.io/openshift-storage`. Label each node with the following command:

```console
$ oc label node workerX.rhv-upi.ocp.pwc.umbrella.local cluster.ocs.openshift.io/openshift-storage=''
```

## Deploying OCS and Local Storage Operator

OCS will use the default storage class (typically `gp2` in AWS and VMware deployments) to create the PVCs used for the OSD and MON disks. Since our RHV deployment does not have an existing storage class we will use the Local Storage Operator to create two storage class with PVs backed by block devices on our OCS nodes.

### Deploying OCS Operator

To deploy the OCS operator, run the following command:

```console
$ oc create -f ocs/ocs-operator.yaml
```

### Deploying the Local Storage Operator

To deploy the Local Storage operator, run the following command (note that this will install the Local Storage Operator and supporting operators in the same namespace as the OCS operator):

```console
$ oc create -f ocs/localstorage-operator.yaml
```

### Verifying

To verify the operators were successfully installed, run the following:

```console
$ oc get csv -n openshift-storage
NAME                                         DISPLAY                       VERSION               REPLACES              PHASE
awss3operator.1.0.1                          AWS S3 Operator               1.0.1                 awss3operator.1.0.0   Succeeded
local-storage-operator.4.2.15-202001171551   Local Storage                 4.2.15-202001171551                         Succeeded
ocs-operator.v4.2.1                          OpenShift Container Storage   4.2.1                                       Succeeded
```

You should see phase `Succeeded` for all operators.

## Creating Storage Classes for OSD and MON Disks

Next we will create two storage classes using the Local Storage Operator. One for the OSD disks and another for the MON disks. Two storage classes are used as the OSDs require `volumeMode: block` and the MONs require `volumeMode: filesystem`.

Login to your worker nodes over SSH and verify the locations of your block devices (this can be done w/ the `lsblk` command). In this example, the OSD disks on each node are located at `/dev/sdb` and the MON disks are located at `/dev/sdc`.

Modify the `ocs/storageclass-mon.yaml` and `ocs/storageclass-osd.yaml` files to suit your environment. Pay special attention to the `nodeSelectors` and `devicePaths` field.

Once you have the right values, create the storage classes as follows:

```console
$ oc create -f ocs/storageclass-mon.yaml
```

```console
$ oc create -f ocs/storageclass-osd.yaml
```

To verify, check for the appropriate storage classes and persistent volumes as follows (output may vary slightly):

```console
$ oc get sc
NAME                          PROVISIONER                             AGE
localstorage-ocs-mon-sc       kubernetes.io/no-provisioner            49m
localstorage-ocs-osd-sc       kubernetes.io/no-provisioner            49m
```

```console
$ oc get pv
NAME                CAPACITY   ACCESS MODES   RECLAIM POLICY   ...   STORAGECLASS              REASON   AGE
local-pv-1e5a8670   300Gi      RWO            Delete           ...   localstorage-ocs-osd-sc            6h53m
local-pv-60e5cc95   300Gi      RWO            Delete           ...   localstorage-ocs-osd-sc            6h53m
local-pv-bc51d61e   300Gi      RWO            Delete           ...   localstorage-ocs-osd-sc            6h53m
local-pv-6b8a2749   10Gi       RWO            Delete           ...   localstorage-ocs-mon-sc            6h53m
local-pv-709ff523   10Gi       RWO            Delete           ...   localstorage-ocs-mon-sc            6h53m
local-pv-a8913854   10Gi       RWO            Delete           ...   localstorage-ocs-mon-sc            6h53m
```

## Provisioning OCS Cluster

Modify the file `ocs/storagecluster.yaml` and adjust the storage requests accordingly. These requests must match the underlying PV sizes in the corresponding storage class.

To create the cluster, run the following command:

```console
$ oc create -f ocs/storagecluster.yaml
```

The installation process should take approximately 5 minutes. Run `oc get pods -n openshift-storage -w` to observe the process.

To verify the installation is complete, run the following:

```console
$ oc get storagecluster storagecluster -ojson -n openshift-storage | jq .status
{
  "cephBlockPoolsCreated": true,
  "cephFilesystemsCreated": true,
  "cephObjectStoreUsersCreated": true,
  "cephObjectStoresCreated": true,
  ...
}
```

All fields should be marked true.

## Adding Storage for OpenShift Registry

OCS provides RBD and CephFS backed storage classes for use within the cluster. We can leverage the CephFS storage class to create a PVC for the OpenShift registry.

Modify the file `ocs/registry-cephfs-pvc.yaml` file and adjust the size of the claim. Then run the following to create the PVC:

```console
$ oc create -f ocs/registry-cephfs-pvc.yaml
```

To reconfigure the registry to use our new PVC, run the following:

```console
$ oc patch configs.imageregistry.operator.openshift.io/cluster --type merge -p '{"spec":{"managementState":"Managed","storage":{"pvc":{"claim":"registry"}}}}'
```


# Retiring

Playbooks are also provided to remove VMs from RHV and DNS entries from IdM. To do this, run the retirement playbook as follows:

```console
$ ansible-playbook -i inventory.yml --ask-vault-pass retire.yml
```
