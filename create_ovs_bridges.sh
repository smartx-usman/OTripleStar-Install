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
# Name			: create_ovs_bridges.sh
# Description	: Script for installing and Configuring OpenvSwitch based SDN
#
# Created by    : Muhammad Usman
# Version       : 0.1
# Last Update	: November, 2017
#

#Before execution set these parameters carefully 
SITE=
BRCAP_DPID=
BRDEV_DPID=
BRSDX_DPID=

OPS_CONTROLLER=
DEV_CONTROLLER=
SDX_CONTROLLER=

Box_DP_IP=
GIST_DP_IP=
MYREN_DP_IP=

OVSVM_IP=192.168.122.101
OVSVM_PASSWORD=netmedia

# This script must be executed by root user
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

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
sudo ovs-vsctl add-port brdev eth2
sudo ovs-vsctl add-port brdev L3-BGP

# Add patch ports in bridge br-sdx inside vm
sudo ovs-vsctl add-port br-sdx eth4
sudo ovs-vsctl add-port br-sdx port-1

sleep 3
sudo ovs-vsctl show

if [ $SITE = "GIST1" ]; then
sudo ovs-vsctl add-port brdev PH
sudo ovs-vsctl set Interface PH type=patch
sudo ovs-vsctl set Interface PH options:peer=C_PH

sudo ovs-vsctl add-port brcap C_PH
sudo ovs-vsctl set Interface C_PH type=patch
sudo ovs-vsctl set Interface C_PH options:peer=PH

sudo ovs-vsctl add-port brcap ovs_vxlan_PH
sudo ovs-vsctl set Interface ovs_vxlan_PH type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_PH options:remote_ip=$Box_DP_IP


elif [ $SITE = "MYREN" ]; then
sudo ovs-vsctl add-port brdev PH
sudo ovs-vsctl set Interface PH type=patch
sudo ovs-vsctl set Interface PH options:peer=C_PH

sudo ovs-vsctl add-port brcap C_PH
sudo ovs-vsctl set Interface C_PH type=patch
sudo ovs-vsctl set Interface C_PH options:peer=PH

sudo ovs-vsctl add-port brcap ovs_vxlan_PH
sudo ovs-vsctl set Interface ovs_vxlan_PH type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_PH options:remote_ip=$Box_DP_IP


else
sudo ovs-vsctl add-port brdev GIST1
sudo ovs-vsctl set Interface GIST1 type=patch
sudo ovs-vsctl set Interface GIST1 options:peer=C_GIST1

sudo ovs-vsctl add-port brdev MYREN
sudo ovs-vsctl set Interface MYREN type=patch
sudo ovs-vsctl set Interface MYREN options:peer=C_MYREN

sudo ovs-vsctl add-port brcap C_GIST1
sudo ovs-vsctl set Interface C_GIST1 type=patch
sudo ovs-vsctl set Interface C_GIST1 options:peer=GIST1

sudo ovs-vsctl add-port brcap C_MYREN
sudo ovs-vsctl set Interface C_MYREN type=patch
sudo ovs-vsctl set Interface C_MYREN options:peer=MYREN

# Set Overlay Tunnel Ports
sudo ovs-vsctl add-port brcap ovs_vxlan_GIST1
sudo ovs-vsctl set Interface ovs_vxlan_GIST1 type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_GIST1 options:remote_ip=$GIST_DP_IP

sudo ovs-vsctl add-port brcap ovs_vxlan_MYREN
sudo ovs-vsctl set Interface ovs_vxlan_MYREN type=vxlan
sudo ovs-vsctl set Interface ovs_vxlan_MYREN options:remote_ip=$MYREN_DP_IP

sleep 5
fi

EOSSH

echo -e "Configuration Finised."


