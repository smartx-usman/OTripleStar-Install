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
# Name			: OpenStack Ocata Install (Multi-region Deployment)
# Description	: Script for installing and Configuring OpenStack on Compute/Network Server (All in One)
#
# Created by    : Muhammad Usman
# Version       : 0.1
# Last Update	: November, 2017
#

#Before execution set all these parameters carefully. Set parameters are just examples. 
M_IP=
C_INTERFACE=eth1
C_IP=
C_NETMASK=
FLOATING_IP_NETWORK=
FLOATING_IP_START=
FLOATING_IP_END=
FLOATING_IP_PUBLIC_GATEWAY=

controller_ip=
controller_user=
controller_pwd=

PASSWORD=secrete
region=

# This script must be executed by root user
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi


# Function to remove old OpenStack installation (Juno Devstack)
remove_openstack(){
su stack

cd /opt/devstack
./unstack.sh
./clean.sh

# Run again because with One time it left some components installed
./unstack.sh
./clean.sh

cd ..
#rm -rf devstack
sudo rm -rf /opt/stack
sudo rm -rf /usr/local/bin/
sudo rm -rf /usr/local/lib/python2.7/dist-packages/*

exit

# Remove OpenvSwitch bridges
ovs-vsctl del-br brvlan
ovs-vsctl del-br br-tun
ovs-vsctl del-br br-int
ovs-vsctl del-br br-ex

apt-get -y autoremove
echo "Successfully Removed Existing Installation of OpenStack. \n"
echo "System is going to Restart in 10sec. \n"
sleep 10
sudo init 6
}


# Function to Upgrade OS to Ubuntu 16.04 from Ubuntu 14.04
update_os(){
# upgrade to Ubuntu 16.04
apt-get -y update && apt-get -y upgrade
apt-get -y dist-upgrade
do-release-upgrade

# Update kernel version to support IO Visor
apt-get -y install --install-recommends linux-generic-hwe-16.04 xserver-xorg-hwe-16.04
apt -y install linux-headers-generic-hwe-16.04
apt -y autoremove

echo "Successfully Upgrade OS to Ubuntu 16.04.3. \n"
echo "System is going to Restart in 10sec. \n"
sleep 10
init 6
}


# Function to add OpenStack repository
update_package(){
#Add Repository and update
add-apt-repository cloud-archive:ocata
apt-get update && apt-get -y upgrade

#Install required common software
apt-get -y install software-properties-common

#openstack client
apt-get -y install python-openstackclient
}


# Function to Install common software for all OpenStack services
install_env_software() {
# Install & Configure NTP Server
sudo apt-get install -y ntp
systemctl restart ntp

apt-get -y remove --purge mysql*
apt-get -y autoremove

# Install & Configure MYSQL
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password password $PASSWORD"
sudo debconf-set-selections <<< "mariadb-server mysql-server/root_password_again password $PASSWORD"
sudo apt-get -y install mariadb-server python-pymysql

sudo touch /etc/mysql/mariadb.conf.d/99-openstack.cnf

echo "[mysqld]" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "bind-address = $M_IP" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "default-storage-engine = innodb" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "innodb_file_per_table" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "max_connections  = 4096" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "collation-server = utf8_general_ci" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf
echo "character-set-server = utf8" >> /etc/mysql/mariadb.conf.d/99-openstack.cnf

service mysql restart

echo -e "$PASSWORD\nn\ny\ny\ny\ny" | mysql_secure_installation

# Intall & Configure RabbitMQ
sudo apt-get install -y rabbitmq-server
rabbitmqctl add_user openstack $PASSWORD
rabbitmqctl set_permissions openstack ".*" ".*" ".*"

# Install & configure Memcached
sudo apt-get install -y memcached python-memcache
sed -i "s/127.0.0.1/$M_IP/g" /etc/memcached.conf
service memcached restart
}


# Function to Install and Configure OpenStack Heat Service
install_heat(){
#Prerequisites

#1.To create the database, complete these steps:
cat << EOF | mysql -uroot -p$PASSWORD
CREATE DATABASE heat;
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON heat.* TO 'heat'@'%' IDENTIFIED BY '$PASSWORD';
quit
EOF

ssh $controller_user@$controller_ip << EOF
#2.Source the admin credentials to gain access to admin-only CLI commands:

. /home/netcs/admin-openrc

#3.To create the service credentials, complete these steps:

#Create the heat user:
openstack user create --domain default --password $PASSWORD heat

#Add the admin role to the heat user:
openstack role add --project service --user heat admin

#Create the heat and heat-cfn service entities:
openstack service create --name heat --description "Orchestration" orchestration

openstack service create --name heat-cfn --description "Orchestration"  cloudformation

#4.Create the Orchestration service API endpoints:
openstack endpoint create --region $region orchestration public http://$M_IP:8004/v1/%\(tenant_id\)s

openstack endpoint create --region $region orchestration internal http://$M_IP:8004/v1/%\(tenant_id\)s

 openstack endpoint create --region $region orchestration admin http://$M_IP:8004/v1/%\(tenant_id\)s

openstack endpoint create --region $region cloudformation public http://$M_IP:8000/v1

openstack endpoint create --region $region cloudformation internal http://$M_IP:8000/v1

openstack endpoint create --region $region cloudformation admin http://$M_IP:8000/v1

#5.Orchestration requires additional information in the Identity service to manage stacks. To add this information, complete these steps:

#Create the heat domain that contains projects and users for stacks:
openstack domain create --description "Stack projects and users" heat

#Create the heat_domain_admin user to manage projects and users in the heat domain:
openstack user create --domain heat --password $PASSWORD heat_domain_admin

#Add the admin role to the heat_domain_admin user in the heat domain to enable administrative stack management privileges by the heat_domain_admin user:
openstack role add --domain heat --user-domain heat --user heat_domain_admin admin

#Create the heat_stack_owner role:
openstack role create heat_stack_owner

#Add the heat_stack_owner role to the demo project and user to enable stack management by the demo user:
openstack role add --project demo --user demo heat_stack_owner

#◦Create the heat_stack_user role:
openstack role create heat_stack_user
EOF

#Install and configure components

#1.Install the packages:
sudo apt-get install -y heat-api heat-api-cfn heat-engine

#2.Edit the /etc/heat/heat.conf file and complete the following actions:
sed -i "s/#connection = <None>/connection = mysql+pymysql:\/\/heat:$PASSWORD@$M_IP\/heat/g" /etc/heat/heat.conf

sed -i "s/#transport_url = <None>/transport_url = rabbit:\/\/openstack:$PASSWORD@$M_IP/g" /etc/heat/heat.conf

sed -i "s/#auth_uri = <None>/auth_uri = http:\/\/$management_node_ip:5000\n\
auth_url = http:\/\/$management_node_ip:35357\n\
memcached_servers = $management_node_ip:11211\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
project_name = service\n\
username = heat\n\
password = $PASSWORD/g" /etc/heat/heat.conf


sed -i "s/#auth_type = <None>/\[trustee\]\n\
auth_type = password\n\
auth_url = http:\/\/$management_node_ip:35357\n\
username = heat\n\
password = $PASSWORD\n\
user_domain_name = default\n\
\n\
[clients_keystone]\n\
auth_uri = http:\/\/$management_node_ip:35357\n\
\n\
[ec2authtoken]\n\
auth_uri = http:\/\/$management_node_ip:5000/g" /etc/heat/heat.conf

sed -i "s/#debug = false/heat_metadata_server_url = http:\/\/$M_IP:8000\n\
heat_waitcondition_server_url = http:\/\/$M_IP:8000\/v1\/waitcondition\n\
stack_domain_admin = heat_domain_admin\n\
stack_domain_admin_password = $PASSWORD\n\
stack_user_domain_name = heat/g" /etc/heat/heat.conf

#3.Populate the Orchestration database:
su -s /bin/sh -c "heat-manage db_sync" heat

#restart the Orchestration services:
service heat-api restart
service heat-api-cfn restart
service heat-engine restart
}


# Function to Install and Configure Glance Service
install_glance(){
#1.To create the database, complete these steps:
cat << EOF | mysql -uroot -p$PASSWORD
CREATE DATABASE glance;
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON glance.* TO 'glance'@'%' IDENTIFIED BY '$PASSWORD';
quit
EOF

ssh $controller_user@$controller_ip << EOF
# Source the admin credentials to gain access to admin-only CLI commands
. /home/netcs/openstack/admin-openrc

# To create the service credentials, complete these steps
# Create the glance user:
#openstack user create --domain default --password $PASSWORD glance

# Add the admin role to the glance user and service project
#openstack role add --project service --user glance admin

#Create the glance service entity
#openstack service create --name glance --description "OpenStack Image" image

#4 Create the Image service API endpoints
openstack endpoint create --region $region image public http://$M_IP:9292

openstack endpoint create --region $region image internal http://$M_IP:9292

openstack endpoint create --region $region image admin http://$M_IP:9292
EOF

# Install and configure components
# Install the packages
sudo apt-get install -y glance

# Edit the /etc/glance/glance-api.conf file and complete the following actions:
# In the [database] section, configure database access:
sed -i "s/#connection = <None>/connection = mysql+pymysql:\/\/glance:$PASSWORD@$M_IP\/glance/g" /etc/glance/glance-api.conf

# In the [keystone_authtoken] and [paste_deploy] sections, configure Identity service access:
sed -i "s/#auth_uri = <None>/auth_uri = http:\/\/$controller_ip:5000\n\
auth_url = http:\/\/$controller_ip:35357\n\
memcached_servers = $controller_ip:11211\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
project_name = service\n\
username = glance\n\
password = $PASSWORD\n/g" /etc/glance/glance-api.conf

sed -i "s/#flavor = keystone/flavor = keystone/g" /etc/glance/glance-api.conf

# In the [glance_store] section, configure the local file system store and location of image files:
sed -i "s/#stores = file,http/stores = file,http/g" /etc/glance/glance-api.conf
sed -i "s/#default_store = file/default_store = file/g" /etc/glance/glance-api.conf
sed -i "s/#filesystem_store_datadir = \/var\/lib\/glance\/images/filesystem_store_datadir = \/var\/lib\/glance\/images\//g" /etc/glance/glance-api.conf


# Edit the /etc/glance/glance-registry.conf file and complete the following actions:
# In the [database] section, configure database access:
sed -i "s/#connection = <None>/connection = mysql+pymysql:\/\/glance:$PASSWORD@$M_IP\/glance/g" /etc/glance/glance-registry.conf

# In the [keystone_authtoken] and [paste_deploy] sections, configure Identity service access:
sed -i "s/#auth_uri = <None>/auth_uri = http:\/\/$controller_ip:5000\n\
auth_url = http:\/\/$controller_ip:35357\n\
memcached_servers = $controller_ip:11211\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
project_name = service\n\
username = glance\n\
password = $PASSWORD\n/g" /etc/glance/glance-registry.conf

sed -i "s/#flavor = keystone/flavor = keystone/g" /etc/glance/glance-registry.conf

# Populate the Image service database:
su -s /bin/sh -c "glance-manage db_sync" glance

# Restart the Image services:
service glance-registry restart
service glance-api restart

# Download the source image:
#wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img

# Upload the image to the Image service using the QCOW2 disk format, bare container format, and public visibility so all projects can access it:
# 403 Forbidden: You are not authorized to complete this action. (HTTP 403) when creating image
# because of wrong configuration. missed to add flavor = keystone in glance-api and glance-registry files

ssh $controller_user@$controller_ip << EOF
# Source the admin credentials to gain access to admin-only CLI commands
. /home/netcs/openstack/admin-openrc
cd /home/netcs/openstack
openstack --os-region-name $region image create "cirros" --file cirros-0.3.5-x86_64-disk.img --disk-format qcow2 --container-format bare --public --unprotected
openstack --os-region-name $region image create "Xenial-Ubuntu 16.04" --file xenial-server-cloudimg-amd64-disk1.img --disk-format qcow2 --container-format bare --public --unprotected
openstack --os-region-name $region image create "Trusty-Ubuntu 14.04" --file ubuntu-14.04-server-cloudimg-amd64.img --disk-format qcow2 --container-format bare --public --unprotected
EOF
}


# Function to Install and Configure Nova Services
install_nova(){
# To create the database, complete these steps
cat << EOF | mysql -uroot -p$PASSWORD
CREATE DATABASE nova_api;
CREATE DATABASE nova;
CREATE DATABASE nova_cell0;
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_api.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON nova_cell0.* TO 'nova'@'%' IDENTIFIED BY '$PASSWORD';
quit
EOF

# Source the admin credentials to gain access to admin-only CLI commands
ssh $controller_user@$controller_ip << EOF
. /home/netcs/openstack/admin-openrc
# To create the service credentials, complete these steps
# Create the nova user:
#openstack user create --domain default --password $PASSWORD nova

# Add the admin role to the nova user
#openstack role add --project service --user nova admin

# Create the nova service entity
#openstack service create --name nova --description "OpenStack Compute" compute

# Create the Compute service API endpoints
openstack endpoint create --region $region compute public http://$M_IP:8774/v2.1
openstack endpoint create --region $region compute internal http://$M_IP:8774/v2.1
openstack endpoint create --region $region compute admin http://$M_IP:8774/v2.1

# Create a Placement service user using your chosen PLACEMENT_PASS
#openstack user create --domain default --password $PASSWORD placement

# Add the Placement user to the service project with the admin role
#openstack role add --project service --user placement admin

# Create the Placement API entry in the service catalog:
#openstack service create --name placement --description "Placement API" placement

# Create the Placement API service endpoints:
openstack endpoint create --region $region placement public http://$M_IP:8778
openstack endpoint create --region $region placement internal http://$M_IP:8778
openstack endpoint create --region $region placement admin http://$M_IP:8778
EOF

# Install and configure components

# Install the packages
sudo apt-get install -y nova-api nova-conductor nova-consoleauth \
  nova-novncproxy nova-scheduler nova-placement-api nova-compute 
  
#2 Edit the /etc/nova/nova.conf file
# In the [api_database] and [database] sections, configure database access:

sed -i "s/connection=sqlite:\/\/\/\/var\/lib\/nova\/nova.sqlite/connection = mysql+pymysql:\/\/nova:$PASSWORD@$M_IP\/nova_api/g" /etc/nova/nova.conf

sed -i "s/#connection=<None>/connection = mysql+pymysql:\/\/nova:$PASSWORD@$M_IP\/nova/g" /etc/nova/nova.conf


# In the [DEFAULT] section, configure RabbitMQ message queue access:
sed -i "s/#transport_url=<None>/transport_url = rabbit:\/\/openstack:$PASSWORD@$M_IP/g" /etc/nova/nova.conf


# In the [api] and [keystone_authtoken] sections, configure Identity service access:
#sed -i "s/#auth_strategy=keystone/auth_strategy=keystone/g" /etc/nova/nova.conf


#2 Edit the /etc/nova/nova.conf file and complete the following actions:
sed -i "s/enabled_apis=osapi_compute,metadata/enabled_apis=osapi_compute,metadata\n\
my_ip = $M_IP\n\
use_neutron = True \n\
firewall_driver = nova.virt.firewall.NoopFirewallDriver\n\
rpc_backend = rabbit\n\
auth_strategy = keystone/g" /etc/nova/nova.conf


sed -i "s/#auth_uri=<None>/auth_uri = http:\/\/$controller_ip:5000\n\
auth_url = http:\/\/$controller_ip:35357\n\
memcached_servers = $controller_ip:11211\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
project_name = service\n\
username = nova\n\
password = $PASSWORD/g" /etc/nova/nova.conf


# In the [DEFAULT] section, configure the my_ip option to use the management interface IP:
#sed -i "s/#my_ip=10.89.104.70/my_ip= $M_IP/g" /etc/nova/nova.conf

# In the [DEFAULT] section, enable support for the Networking service:
#sed -i "s/#use_neutron=true/use_neutron=true/g" /etc/nova/nova.conf
#sed -i "s/#firewall_driver=<None>/firewall_driver = nova.virt.firewall.NoopFirewallDriver/g" /etc/nova/nova.conf

# In the [vnc] section, configure the VNC proxy to use the management interface IP address:
sed -i "s/#vncserver_listen=127.0.0.1/vncserver_listen = $M_IP/g" /etc/nova/nova.conf
sed -i "s/#vncserver_proxyclient_address=127.0.0.1/vncserver_proxyclient_address = $M_IP/g" /etc/nova/nova.conf
sed -i "s/#novncproxy_base_url=http:\/\/127.0.0.1:6080\/vnc_auto.html/novncproxy_base_url=http:\/\/$M_IP:6080\/vnc_auto.html/g" /etc/nova/nova.conf
sed -i "s/#enabled=true/enabled = true/g" /etc/nova/nova.conf

# In the [glance] section, configure the location of the Image service API:
sed -i "s/#api_servers=<None>/api_servers = http:\/\/$M_IP:9292/g" /etc/nova/nova.conf

# In the [oslo_concurrency] section, configure the lock path:
sed -i "s/lock_path=\/var\/lock\/nova/lock_path= \/var\/lib\/nova\/tmp/g" /etc/nova/nova.conf

sed -i "s/log_dir=\/var\/log\/nova/#log_dir=<None>/g" /etc/nova/nova.conf

# In the [placement] section, configure the Placement API:
sed -i "s/os_region_name = openstack/os_region_name = $region\n\
project_domain_name = Default\n\
project_name = service\n\
auth_type = password\n\
user_domain_name = Default\n\
auth_url = http:\/\/$controller_ip:35357\/v3\n\
username = placement\n\
password = $PASSWORD/g" /etc/nova/nova.conf

sed -i "s/#discover_hosts_in_cells_interval=-1/discover_hosts_in_cells_interval=300/g" /etc/nova/nova.conf

#3 Populate the nova-api database:
su -s /bin/sh -c "nova-manage api_db sync" nova

#4 Register the cell0 database:
su -s /bin/sh -c "nova-manage cell_v2 map_cell0" nova

#5 Create the cell1 cell:
su -s /bin/sh -c "nova-manage cell_v2 create_cell --name=cell1 --verbose" nova

#6 Populate the nova database:
su -s /bin/sh -c "nova-manage db sync" nova
  
#Finalize installation

#1.Determine whether your compute node supports hardware acceleration for virtual machines:
NUM=`egrep -c '(vmx|svm)' /proc/cpuinfo`
if [ $NUM = 0 ]
then
 echo "Virtualization Support ..."
 sed -i "s/virt_type=kvm/virt_type=qemu/g" /etc/nova/nova-compute.conf
fi  
  
# Change Permission 
chown -R nova:nova /var/lib/nova
sleep 10
 
# To install Nova LXD instead of KVM (uncomment)
# apt-get -y install nova-compute-lxd 
# Restart the nova services:
service nova-api restart
service nova-consoleauth restart
service nova-scheduler restart
service nova-conductor restart
service nova-novncproxy restart  

# Discover compute hosts
su -s /bin/sh -c "nova-manage cell_v2 discover_hosts --verbose" nova
sleep 5

service nova-compute restart

# Create Flavors
ssh $controller_user@$controller_ip << EOF
. /home/netcs/openstack/admin-openrc
openstack --os-region-name $region flavor create --public m1.tiny --id auto --ram 512 --disk 1 --vcpus 1
openstack --os-region-name $region flavor create --public m1.small --id auto --ram 1024 --disk 10 --vcpus 1
openstack --os-region-name $region flavor create --public m1.medium --id auto --ram 2048 --disk 20 --vcpus 2
openstack --os-region-name $region flavor create --public m1.large --id auto --ram 4096 --disk 40 --vcpus 2
openstack --os-region-name $region flavor create --public m1.xlarge --id auto --ram 8192 --disk 80 --vcpus 4
EOF

# error creating instance "no valid host was found"
# This error occur because of wrong neutron configuration. check all configuration files to solve this problem. Also creating wrong neutron network causes this problem. Sometime droping nova database and recreating also solves the problem.
}


# Function to Install and Configure Neutron Services
install_neutron(){
#1 To create the database, complete these steps:
cat << EOF | mysql -uroot -p$PASSWORD
CREATE DATABASE neutron;
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON neutron.* TO 'neutron'@'%' IDENTIFIED BY '$PASSWORD';
quit
EOF

ssh $controller_user@$controller_ip << EOF
#2 Source the admin credentials to gain access to admin-only CLI commands:
. /home/netcs/openstack/admin-openrc

#3 To create the service credentials, complete these steps:
# Create the neutron user:
#openstack user create --domain default --password $PASSWORD neutron

# Add the admin role to the neutron user:
#openstack role add --project service --user neutron admin

# Create the neutron service entity:
#openstack service create --name neutron \
  --description "OpenStack Networking" network


#4 Create the Networking service API endpoints:
openstack endpoint create --region $region \
  network public http://$M_IP:9696

openstack endpoint create --region $region \
  network internal http://$M_IP:9696

openstack endpoint create --region $region \
  network admin http://$M_IP:9696
EOF

# Install the components
sudo apt-get install -y openvswitch-switch
sudo apt-get install -y neutron-server neutron-plugin-ml2 \
  neutron-openvswitch-agent neutron-l3-agent neutron-dhcp-agent \
  neutron-metadata-agent neutron-plugin-openvswitch-agent 

## Edit the /etc/neutron/neutron.conf file and complete the following actions:
sed -i "s/connection = sqlite:\/\/\/\/var\/lib\/neutron\/neutron.sqlite/connection = mysql+pymysql:\/\/neutron:$PASSWORD@$M_IP\/neutron/g" /etc/neutron/neutron.conf

#sed -i "s/#auth_strategy = \*/auth_strategy = keystone/g"

sed -i "s/#service_plugins =/service_plugins = router\n\
allow_overlapping_ips = true\n\
rpc_backend = rabbit\n\
auth_strategy = keystone\n\
notify_nova_on_port_status_changes = true\n\
notify_nova_on_port_data_changes = true/g" /etc/neutron/neutron.conf

# In the [DEFAULT] section, configure RabbitMQ message queue access:
sed -i "s/#transport_url = <None>/transport_url = rabbit:\/\/openstack:$PASSWORD@$M_IP/g" /etc/neutron/neutron.conf

sed -i "s/#auth_uri = <None>/auth_uri = http:\/\/$controller_ip:5000\n\
auth_url = http:\/\/$controller_ip:35357\n\
memcached_servers = $controller_ip:11211\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
project_name = service\n\
username = neutron\n\
password = $PASSWORD/g" /etc/neutron/neutron.conf

sed -i "s/#auth_url = <None>/auth_url = http:\/\/$controller_ip:35357\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
region_name = $region\n\
project_name = service\n\
username = nova\n\
password = $PASSWORD/g" /etc/neutron/neutron.conf


# Edit the /etc/neutron/plugins/ml2/ml2_conf.ini file and complete the following actions:
sed -i "s/#type_drivers = local,flat,vlan,gre,vxlan,geneve/type_drivers = flat,vlan,vxlan\n\
tenant_network_types = vxlan\n\
mechanism_drivers = openvswitch/g" /etc/neutron/plugins/ml2/ml2_conf.ini

sed -i "s/#vxlan_group = <None>/#vxlan_group = <None>\n\
vni_ranges = 1:1000/g" /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i "s/#network_vlan_ranges =/network_vlan_ranges = provider:100:199/g" /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i "s/#flat_networks = \*/flat_networks = external/g" /etc/neutron/plugins/ml2/ml2_conf.ini
sed -i "s/#firewall_driver = <None>/firewall_driver = iptables_hybrid\n\
enable_ipset = true/g" /etc/neutron/plugins/ml2/ml2_conf.ini


# In the openvswitch_agent.ini file, configure the Open vSwitch agent:
sed -i "s/#local_ip = <None>/local_ip = $M_IP/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
sed -i "s/#tunnel_types =/tunnel_types = vxlan/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
sed -i "s/#firewall_driver = <None>/firewall_driver = iptables_hybrid/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
sed -i "s/#arp_responder = false/arp_responder = True/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
sed -i "s/#enable_security_group = true/enable_security_group = true/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini
sed -i "s/#bridge_mappings =/bridge_mappings = provider:brvlan,external:br-ex/g" /etc/neutron/plugins/ml2/openvswitch_agent.ini


# In the l3_agent.ini file, configure the L3 agent:
sed -i "s/#interface_driver = <None>/interface_driver = openvswitch\n\
external_network_bridge = \n\
dhcp_driver = neutron.agent.linux.dhcp.Dnsmasq\n\
enable_isolated_metadata = true/g" /etc/neutron/l3_agent.ini


# In the dhcp_agent.ini file, configure the DHCP agent:
#sed -i "s/#enable_isolated_metadata = false/enable_isolated_metadata = true/g" /etc/neutron/dhcp_agent.ini
sed -i "s/#interface_driver = <None>/interface_driver = neutron.agent.linux.interface.OVSInterfaceDriver/g" /etc/neutron/dhcp_agent.ini
sed -i "s/#ovs_use_veth = false/ovs_use_veth = false/g" /etc/neutron/dhcp_agent.ini


# In the metadata_agent.ini file, configure the metadata agent:
sed -i "s/#nova_metadata_ip = 127.0.0.1/nova_metadata_ip = $M_IP/g" /etc/neutron/metadata_agent.ini
sed -i "s/#metadata_proxy_shared_secret =/metadata_proxy_shared_secret = $PASSWORD/g" /etc/neutron/metadata_agent.ini


# Edit the /etc/nova/nova.conf file and complete the following actions:
# In the [neutron] section, configure access parameters:

sed -i "s/#url=http:\/\/127.0.0.1:9696/url = http:\/\/$M_IP:9696\n\
auth_url = http:\/\/$controller_ip:35357\n\
auth_type = password\n\
project_domain_name = default\n\
user_domain_name = default\n\
region_name = $region\n\
project_name = service\n\
username = neutron\n\
password = $PASSWORD\n\
service_metadata_proxy = true\n\
metadata_proxy_shared_secret = $PASSWORD/g" /etc/nova/nova.conf

# Create the OpenvSwitch Bridges
ovs-vsctl add-br brvlan
ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex $C_INTERFACE

#Configure Interface for Internet Connectivity
echo -e "\nauto br-ex \n   iface br-ex inet static \n   address $C_IP \n   netmask $C_NETMASK\n" >> /etc/network/interfaces

#Enable IP forwarding
sed -i "s/#net.ipv4.conf.default.rp_filter=1/net.ipv4.conf.default.rp_filter=0/g" /etc/sysctl.conf
sed -i "s/#net.ipv4.conf.all.rp_filter=1/net.ipv4.conf.all.rp_filter=0/g" /etc/sysctl.conf
sed -i "s/#net.ipv4.ip_forward=1/net.ipv4.ip_forward=1/g" /etc/sysctl.conf
sed -i "s/#net.ipv6.conf.all.forwarding=1/net.ipv6.conf.all.forwarding=1/g" /etc/sysctl.conf
sudo sysctl -p /etc/sysctl.conf


# Finalize installation
su -s /bin/sh -c "neutron-db-manage --config-file /etc/neutron/neutron.conf \
  --config-file /etc/neutron/plugins/ml2/ml2_conf.ini upgrade head" neutron

#Restart the Compute service:
service nova-api restart
service neutron-server restart
service openvswitch-switch restart
service neutron-openvswitch-agent restart
service neutron-l3-agent restart
service neutron-dhcp-agent restart
service neutron-metadata-agent restart

sleep 10

# Create public network for connectivity to internet
ssh $controller_user@$controller_ip << EOF
#2 Source the admin credentials to gain access to admin-only CLI commands:
. /home/netcs/openstack/admin-openrc
openstack --os-region-name $region network create public --share --external --provider-physical-network external --provider-network-type flat
openstack --os-region-name $region subnet create --network public --subnet-range $FLOATING_IP_NETWORK public_subnet --allocation-pool start=$FLOATING_IP_START,end=$FLOATING_IP_END --dns-nameserver 8.8.8.8 --gateway $FLOATING_IP_PUBLIC_GATEWAY
EOF
}


OS_VERSION=`lsb_release -a`
echo -e "Detected OS version: \n$OS_VERSION"

if echo $OS_VERSION | grep -iq "14.04"; then
	OS_VERSION=14
else
	OS_VERSION=16
fi

#read -p "Is it fresh install/Updated version of Ubuntu 16.04.3 yes/no? " yn
case $OS_VERSION in
	16 )update_package
		install_env_software
		install_glance
		install_nova
		install_neutron
	;;
	14 ) read -p "Previous OpenStack devstack instllation Exists (yes/no)? " yn
		case $yn in
			[Yy]* ) remove_openstack
			;;
			[Nn]* ) update_os
			;;
			* ) echo "Please answer yes or no."
			;;
		esac
	;;
	* ) echo "Please answer yes or no.";;
esac
echo "|******************************************************************| "
echo "|                   Installation Completed.                        | "
echo "|******************************************************************| "

