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
