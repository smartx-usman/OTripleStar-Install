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
# Description	: Script for installing and Configuring O***
#
# Created by    : Muhammad Usman
# Version       : 0.1
# Last Update	: November, 2017
#

#Run these steps manually
#Before execution set these parameters carefully 
SITE=GIST3
BRCAP_DPID=3333333333333313
BRDEV_DPID=1111111111111113
BRSDX_DPID=5555555555555513

DP_IF=eth2
DP_GW=61.252.52.1
DP_IF_IP=61.252.52.13
DP_IF_MASK=255.255.255.0

OPS_CONTROLLER=103.22.221.149
DEV_CONTROLLER=103.22.221.150
SDX_CONTROLLER=103.22.221.35

OVSVM_IP=103.22.221.28
OVSVM_PASSWORD=netmedia

OS_CONTROLLER=103.22.221.74
OS_CONTROLLER_PASS='fn!xo!ska!'

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Install required software
sudo apt-get install -y virt-manager qemu-system
ssh-copy-id netcs@$OS_CONTROLLER <<< $OS_CONTROLLER_PASS

# Copy required files
scp netcs@$OS_CONTROLLER:/home/netcs/openstack/lubuntu-16.04.2-desktop-amd64.iso /home/tein
scp netcs@$OS_CONTROLLER:/home/netcs/openstack/ovs-vm.qcow2 /tmp
scp netcs@$OS_CONTROLLER:/home/netcs/openstack/ovs-bridge-brvlan.xml /home/tein
scp netcs@$OS_CONTROLLER:/home/netcs/openstack/ovs-bridge-br-ex.xml /home/tein
mv /tmp/ovs-vm.qcow2 /var/lib/libvirt/images/ovs-vm1.qcow2

# Create virtual network
virsh net-define /home/tein/ovs-bridge-br-ex.xml
virsh net-define /home/tein/ovs-bridge-brvlan.xml
virsh net-start ovs-br-ex
virsh net-start ovs-brvlan
virsh net-autostart ovs-br-ex
virsh net-autostart ovs-brvlan

# Create Hypervisor VM
#sudo virt-install --connect qemu:///system -n ovs-vm1 -r 1024 -f ovs-vm1.qcow2 -s 12 -c /home/tein/lubuntu-16.04.2-desktop-amd64.iso --vnc --noautoconsole --os-type linux --accelerate --network=network:default
sudo virt-install --name ovs-vm --memory 1024 --disk /var/lib/libvirt/images/ovs-vm1.qcow2 --import

# Manually complete VM creation and create network interfaces via virt-manager

# Create OpenvSwitch bridges
ssh tein@$OVSVM_IP << EOSSH
#sudo -S <<< $OVSVM_PASSWORD su

# Delete existing OVS bridges
sudo ovs-vsctl del-br brcap
sudo ovs-vsctl del-br brdev
sudo ovs-vsctl del-br br-sdx

#Create Operator Bridge and Add Configurations
sudo ovs-vsctl add-br brcap
sudo ovs-vsctl set-fail-mode brcap secure
sudo ovs-vsctl set bridge brcap protocols=OpenFlow10
sudo ovs-vsctl set bridge brcap other-config:datapath-id=$BRCAP_DPID
sudo ovs-vsctl set-controller brcap tcp:$OPS_CONTROLLER:6633
sudo ovs-vsctl show
sleep 5

# Create Developer Bridge and Add Configurations
sudo ovs-vsctl add-br brdev
sudo ovs-vsctl set-fail-mode brdev secure
sudo ovs-vsctl set bridge brdev protocols=OpenFlow10
sudo ovs-vsctl set bridge brdev other-config:datapath-id=$BRDEV_DPID
sudo ovs-vsctl set-controller brdev tcp:$DEV_CONTROLLER:6633
sudo ovs-vsctl show
sleep 5

#Create Data-L3 Bridge and Add Configurations
sudo ovs-vsctl add-br br-sdx
sudo ovs-vsctl set-fail-mode br-sdx secure
sudo ovs-vsctl set bridge br-sdx protocols=OpenFlow10
sudo ovs-vsctl set bridge br-sdx other-config:datapath-id=$BRSDX_DPID
sudo ovs-vsctl set-controller br-sdx tcp:$SDX_CONTROLLER:6633
sudo ovs-vsctl show
sleep 5

# Add patch port in bridge brdev inside vm
sudo ovs-vsctl add-port brdev eth1
sudo ovs-vsctl add-port brdev L3-BGP

# Add patch ports in bridge br-sdx inside vm
sudo ovs-vsctl add-port br-sdx eth4
sudo ovs-vsctl add-port br-sdx port-1

sleep 3
sudo ovs-vsctl show

if [ $SITE = "GIST" ]; then
#sudo ovs-vsctl add-port brdev MYREN
#sudo ovs-vsctl set Interface MYREN type=patch
#sudo ovs-vsctl set Interface MYREN options:peer=C_MYREN

sudo ovs-vsctl add-port brdev PH
sudo ovs-vsctl set Interface PH type=patch
sudo ovs-vsctl set Interface PH options:peer=C_PH

#sudo ovs-vsctl add-port brcap C_MYREN
#sudo ovs-vsctl set Interface C_MYREN type=patch
#sudo ovs-vsctl set Interface C_MYREN options:peer=MYREN

sudo ovs-vsctl add-port brcap C_PH
sudo ovs-vsctl set Interface C_PH type=patch
sudo ovs-vsctl set Interface C_PH options:peer=PH

#sudo ovs-vsctl add-port brcap ovs_vxlan_MYREN
#sudo ovs-vsctl set Interface ovs_vxlan_MYREN type=vxlan
#sudo ovs-vsctl set Interface ovs_vxlan_MYREN options:remote_ip=103.26.47.229

sudo ovs-vsctl add-port brcap ovs_vxlan_PH
sudo ovs-vsctl set Interface ovs_vxlan_PH type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_PH options:remote_ip=202.90.150.28


elif [ $SITE = "MYREN" ]; then
sudo ovs-vsctl add-port brdev GIST3
sudo ovs-vsctl set Interface GIST3 type=patch
sudo ovs-vsctl set Interface GIST3 options:peer=C_GIST3

sudo ovs-vsctl add-port brdev PH
sudo ovs-vsctl set Interface PH type=patch
sudo ovs-vsctl set Interface PH options:peer=C_PH

sudo ovs-vsctl add-port brcap C_GIST3
sudo ovs-vsctl set Interface C_GIST3 type=patch
sudo ovs-vsctl set Interface C_GIST3 options:peer=GIST3

sudo ovs-vsctl add-port brcap C_PH
sudo ovs-vsctl set Interface C_PH type=patch
sudo ovs-vsctl set Interface C_PH options:peer=PH

sudo ovs-vsctl add-port brcap ovs_vxlan_GIST3
sudo ovs-vsctl set Interface ovs_vxlan_GIST3 type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_GIST3 options:remote_ip=61.252.52.13

sudo ovs-vsctl add-port brcap ovs_vxlan_PH
sudo ovs-vsctl set Interface ovs_vxlan_PH type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_PH options:remote_ip=202.90.150.28


else
sudo ovs-vsctl add-port brdev GIST
sudo ovs-vsctl set Interface GIST type=patch
sudo ovs-vsctl set Interface GIST options:peer=C_GIST

sudo ovs-vsctl add-port brdev MYREN
sudo ovs-vsctl set Interface MYREN type=patch
sudo ovs-vsctl set Interface MYREN options:peer=C_MYREN

sudo ovs-vsctl add-port brcap C_GIST
sudo ovs-vsctl set Interface C_GIST type=patch
sudo ovs-vsctl set Interface C_GIST options:peer=GIST

sudo ovs-vsctl add-port brcap C_MYREN
sudo ovs-vsctl set Interface C_MYREN type=patch
sudo ovs-vsctl set Interface C_MYREN options:peer=MYREN

# Set Overlay Tunnel Ports
sudo ovs-vsctl add-port brcap ovs_vxlan_GIST
sudo ovs-vsctl set Interface ovs_vxlan_GIST type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_GIST options:remote_ip=61.252.52.11
sudo ovs-vsctl add-port brcap ovs_vxlan_MYREN
sudo ovs-vsctl set Interface ovs_vxlan_MYREN type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_MYREN options:remote_ip=103.26.47.229

sleep 5
fi

EOSSH

echo -e "Configuration Finised."


