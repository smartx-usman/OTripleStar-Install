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
# Version       : 0.2
# Last Update	: November, 2017
#

#Before execution set these parameters carefully 

controller_ip=
controller_pwd=

ovs_vm_mgmt_ip=
ovs_vm_mgmt_netmask=
ovs_vm_mgmt_gateway=
ovs_vm_mgmt_dns=8.8.8.8

data_1_interface=
data_1_ip=
data_1_netmask=

#data_2_interface=
#data_2_ip=
#data_2_netmask=


if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install required software
echo "*      Installing required software                                *"
sudo apt-get install -y virt-manager qemu-system
ssh-copy-id netcs@$controller_ip <<< $controller_pwd

echo "*      Required software installation completed.                   *"

# Copy required files
echo "*      Be patience because 5GB data will be downloaded             *"
scp netcs@$controller_ip:/home/netcs/openstack/ovs-vm.qcow2 /var/lib/libvirt/images/ovs-vm1.qcow2
scp netcs@$controller_ip:/home/netcs/openstack/ovs-bridge-brvlan.xml /home/tein
scp netcs@$controller_ip:/home/netcs/openstack/ovs-bridge-br-ex.xml /home/tein
echo "*       Data download completed.                                   *"

# Create virtual networks
echo "*      Creating virtual networks                                   *"
virsh net-define /home/tein/ovs-bridge-br-ex.xml
virsh net-define /home/tein/ovs-bridge-brvlan.xml
virsh net-start ovs-br-ex
virsh net-start ovs-brvlan
virsh net-autostart ovs-br-ex
virsh net-autostart ovs-brvlan
sleep 5
echo "*      Virtual networks created.                                  *"

# Create Hypervisor VM
echo "*      Creating virtual machine for SDN switches deployment       *"
sudo virt-install \
	--name ovs-vm1 \
	--memory 1024 \
	--disk /var/lib/libvirt/images/ovs-vm1.qcow2 \
	--network default,model=virtio \
	--import
	
sleep 10
echo "*       virtual machine creation completed.                      *"

# Create virtual interfaces
echo "*      Creating virtual machine network interfaces               *"
sudo virsh destroy ovs-vm1
sleep 10

#sudo virsh attach-interface --domain ovs-vm --type network --source default  --model virtio --config
#sleep 3
sudo virsh attach-interface --domain ovs-vm1 --type network --source ovs-br-ex  --model virtio --config
sleep 3
sudo virsh attach-interface --domain ovs-vm1 --type network --source ovs-brvlan  --model virtio --config
sleep 3
sudo virsh attach-interface --domain ovs-vm1 --type direct --source $data_1_interface --model virtio --config
sleep 3
echo "*       virtual machine virtual interfaces creation completed.   *"

# Start Hypervisor VM
echo "*      Starting Hypervisor virtual machine                       *"
sudo virsh start ovs-vm1
sleep 20

echo "*       Enter Password: netmedia     *"
#Configure Interface for Internet Connectivity
ssh tein@192.168.122.101 << EOSSH
sudo su
sudo echo -e "\nauto eth1 \n   iface eth1 inet static \n   address $ovs_vm_mgmt_ip \n   netmask $ovs_vm_mgmt_netmask \n   gateway $ovs_vm_mgmt_gateway\n   dns-nameservers $ovs_vm_mgmt_dns\n" >> /etc/network/interfaces
sudo echo -e "\nauto eth2 \n   iface eth2 inet manual \n   up ifconfig eth2 up\n" >> /etc/network/interfaces
sudo echo -e "\nauto eth3 \n   iface eth3 inet static \n   address $data_1_ip \n   netmask $data_1_netmask\n" >> /etc/network/interfaces
init 6
EOSSH
sleep 10

echo "*      Verify virtual machine networking                       *"
ping -c 2 192.168.122.101
ping -c 2 $ovs_vm_mgmt_ip

echo "|******************************************************************| "
echo "|                   Installation Completed.                        | "
echo "|******************************************************************| "





# Manually complete VM creation and create network interfaces via virt-manager
# 1. Connect via virt-manager
# 2. Add network interface with default NAT using virtio driver
# 3. Add network interface with ovs-brvlan using virtio driver
# 4. Add network interface with data path interface (e.g. eth1/eno2) using virtio driver
# 5. Add network interface with ovs-br-ex using virtio driver
# 6. Add network interface with data path interface (e.g. eth3/eno4) using virtio driver
# 7. Force off the vm and start again
# 8. Verify the interface eth0 by pinging 192.168.122.101 from SmartX Box
# 9. Edit /etc/network/interface to configure all the interfaces which were created earlier