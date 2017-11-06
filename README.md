# README #
[SmartX Automation Framework: OTripleStarInstall] : A Linux-based Script (BASH) for automated installation of SmartX Box software O*** over OF@TEIN+ Testbed.

## Summary ##
### Overview ###
This tool is developed to do automated provisiong (installation and configuration) of SmartX Box type O*** of OF@TEIN Testbed infrastructure by using OpenStack and OpenvSwitch OpenFlow-SDN configuration.

### Release Version ###
This is the first version of the tools released on November 2017 and still under development. 

### Current Support and Caveats ###

The current release supports (OF@TEIN+ Testbed) current environment:

* Ubuntu Operating System 16.04.03 (Xenial)
* OpenStack Ocata Stable Release
* OpenStack VLAN-based Tenant Network
* OpenvSwitch OpenFlow-SDN VXLAN Overlay Network

## How it works ##

### Hardware (SmartX Box) Requirements ###

In order to install SmartX O*** software using this tool and integrate with current OF@TEIN+ Testbed , the required/recommended hardware specification are:

* Processor (CPU) 	: 4 cores or more
* Memory (RAM)		: 12 GB or more
* Storage (HDD)		: 80 GB or more			
* Network interface : 5 ports (Power + Management + Control + Data)
* Outband Management: IPMI (HP iLO or IBM IMM)

### Required Component and Connection Verification ###

Before the tools are executed, it required some components and verifications such as:

* OF@TEIN+ Box Specific Configuration : ask the testbed operators (TEIN-GIST@nm.gist.ac.kr) for the details
* OF@TEIN+ SmartX O*** OpenStack Centralized Management (Keystone and Horizon) : 103.22.221.74
* OF@TEIN+ OpenFlow-SDN Network Slicer (FlowVisor) : 103.22.221.52
* OF@TEIN+ SmartX Configuration and Access Center : 103.22.221.53
* OF@TEIN+ Testbed HUB nodes (MYREN or GIST) : 103.26.47.229 or 62.252.52.11


### Current Release Features ###

These are current features:

* Automated Upgrade Tools from previous SmartX Box type (Remote upgrade include: Clean Up + OS Upgrade + Install)
* Automated clean up tools for previous SmartX B** Installation (OpenStack devstack installation and OpenvSwitch)
* Automated Ubuntu Operating system upgrade to 16.04.3 LTS version
* Automated Fresh Install Tools of SmartX O***


## Preparation ##

### Dependencies ###
Git Tools

### SmartX Box Local Upgrade/Installation ###
Download the installation scripts into SmartX Box and Edit the "Specific Parameter" in the appropraite Scripts

install_controller.sh
* M_IP     = OpenStack management Box IP address
* PASSWORD = password for OpenStack keystone and Horizon services (better to use 'secrete' as password)

install_smartx_box.sh
* region   			     	 = OpenStack Region ID
* M_IP                       = SmartX Box Management interface IP
* C_INTERFACE                = SmartX Box Control interface name
* C_IP                       = SmartX Box Control interface IP
* C_NETMASK                  = SmartX Box Control interface subnet mask
* FLOATING_IP_NETWORK        = Floating IP network e.g. 192.168.1.0/24
* FLOATING_IP_START          = Floating IP starting IP address e.g. 192.168.1.86
* FLOATING_IP_END            = Floating IP ending IP address e.g.192.168.1.95
* FLOATING_IP_PUBLIC_GATEWAY = Floating IP gateway e.g.192.168.1.1
* controller_ip              = OpenStack management Box IP address
* controller_user            = OpenStack management node Box user
* controller_pwd             = OpenStack management node Box password
* PASSWORD                   = secrete 

create_ovs_vm.sh
* controller_ip              = OpenStack management Box IP address
* controller_pwd             = OpenStack management node Box password

create_ovs_bridges.sh
* SITE                       = OpenStack Region ID (e.g. GIST)
* BRCAP_DPID                 = Set Operator bridge data path ID (e.g. 3333333333333313)
* BRDEV_DPID                 = Set Developer bridge data path ID (e.g. 1111111111111113)
* BRSDX_DPID                 = Set SDX bridge data path ID (e.g. 5555555555555513)
* OPS_CONTROLLER             = Set Operator controller
* DEV_CONTROLLER             = Set Developer controller
* SDX_CONTROLLER             = Set SDX controller
* Box_DP_IP                  = SmartX Box Data path IP
* GIST_DP_IP                 = GIST SmartX Box Data path IP
* MYREN_DP_IP                = MYREN SmartX Box Data path IP
* OVSVM_IP                   = OVS-VM private ip e.g. 192.168.122.101
* OVSVM_PASSWORD             = OVS-VM password

### SmartX Box Remote Upgrade (still on Development) ###

Download the automated upgrade scripts into Remote Machine (Linux) and Edit the "Specific Parameter" in the script
<But it might still required customized configuration in the script before execution>

## How to Execute (Guidelines) ##

### Connection and Communication Verification ###

Ping to all OF@TEIN components above (103.22.221.74, 103.22.221.52, 103.22.221.53, 103.26.47.229, and 62.252.52.11).
Some of them maybe required specific TCP-level verification based on API/Service Ports. Please check details OpenStack and OpenvSwitch Ports.

### OpenStack Keystone and Horizon installation (OpenStack Management Box Installation ** Note this is only one time.) ###
* ./install_controller.sh

### Clean Up, OS Upgrade, OpenStack installation (SmartX Box Installation) ###
* ./install_smartxbox.sh

### Create OVS-VM (For creating developer and operator bridges) ###
* ./create_ovs_vm.sh

### Setup SDN part (Create and configure OpenvSwitch bridges and setup Tunnels) ###
* Note that you need to carefully run this script on multiple boxes to create appropriate ports and tunnels for proper topology setup.
* ./create_ovs_bridges


## Support and Contribution ##

* Authors : SmartX Collaboration (GIST NetCS)
* Contributors : Muhammad Usman
* Contact : TEIN-GIST@nm.gist.ac.kr
