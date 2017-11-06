#!/bin/bash
#
# Copyright 2017 SmartX Collaboration (GIST NetCS). All rights reserved.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#  http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#  See the License for the specific language governing permissions and
#
# Name			: O*** Install
# Description	: Script for installing and Configuring OVS-VM
#
# Created by    : Muhammad Usman
# Version       : 0.1
# Last Update	: November, 2017
#

#Before execution set these parameters carefully 

controller_ip=103.22.221.74
controller_pwd='fn!xo!ska!'

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install required software
sudo apt-get install -y virt-manager qemu-system
ssh-copy-id netcs@$controller_ip <<< $controller_pwd

# Copy required files
scp netcs@$controller_ip:/home/netcs/openstack/ovs-vm.qcow2 /tmp
scp netcs@$controller_ip:/home/netcs/openstack/ovs-bridge-brvlan.xml /home/tein
scp netcs@$controller_ip:/home/netcs/openstack/ovs-bridge-br-ex.xml /home/tein
mv /tmp/ovs-vm.qcow2 /var/lib/libvirt/images/ovs-vm1.qcow2

# Create virtual network
virsh net-define /home/tein/ovs-bridge-br-ex.xml
virsh net-define /home/tein/ovs-bridge-brvlan.xml
virsh net-start ovs-br-ex
virsh net-start ovs-brvlan
virsh net-autostart ovs-br-ex
virsh net-autostart ovs-brvlan

# Create Hypervisor VM
sudo virt-install --name ovs-vm --memory 1024 --disk /var/lib/libvirt/images/ovs-vm1.qcow2 --import

# Manually complete VM creation and create network interfaces via virt-manager
# Steps to create Interfaces
# 1. Connect via virt-manager
# 2. Add network interface with default NAT using virtio driver
# 3. Add network interface with ovs-brvlan using virtio driver
# 4. Add network interface with data path interface (e.g. eth1/eno2) using virtio driver
# 5. Add network interface with ovs-br-ex using virtio driver
# 6. Add network interface with data path interface (e.g. eth3/eno4) using virtio driver
# 7. Force off the vm and start again
# 8. Verify the interface eth0 by pinging 192.168.122.101 from SmartX Box.