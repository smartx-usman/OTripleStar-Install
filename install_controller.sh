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
# Description	: Script for installing and Configuring OpenStack on Management Server 
#
# Created by    : Muhammad Usman
# Version       : 0.1
# Last Update	: November, 2017
#

# Modify these parameters before execution of this script
M_IP=
PASSWORD=

if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

update_package(){

apt-get -y install ntp software-properties-common rabbitmq-server memcached

#Add Repository and update
add-apt-repository cloud-archive:ocata
apt-get update && apt-get -y upgrade

#openstack client
apt-get -y install python-openstackclient
}

install_env_software() {
# Install & Configure NTP
sudo apt-get install -y ntp
systemctl restart ntp

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

install_keystone() {
# Install & Configure Keystone
# Configure Mysql DB
cat << EOF | mysql -uroot -p$PASSWORD
CREATE DATABASE keystone;
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$PASSWORD';
GRANT ALL PRIVILEGES ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$PASSWORD';
quit
EOF

TOKEN=`openssl rand -hex 10`

#2.Run the following command to install the packages
sudo apt-get -y install keystone

#3.Edit the /etc/keystone/keystone.conf file and complete the following actions
#◦In the [database] section, configure database access:
#sed -i "s/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection = mysql+pymysql:\/\/keystone:$PASSWORD@$M_IP\/keystone/g" /etc/keystone/keystone.conf
sed -i "s/#connection = <None>/connection = mysql+pymysql:\/\/keystone:$PASSWORD@$M_IP\/keystone/g" /etc/keystone/keystone.conf

#◦In the [token] section, configure the Fernet token provider:
sed -i "s/#provider = fernet/provider = fernet/g" /etc/keystone/keystone.conf

sed -i "s/#verbose = true/verbose = true/g" /etc/keystone/keystone.conf

#4.Populate the Identity service database
su -s /bin/sh -c "keystone-manage db_sync" keystone

#5.Initialize Fernet keys:
keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone
keystone-manage credential_setup --keystone-user keystone --keystone-group keystone

#5.Bootstrap the Identity service:
keystone-manage bootstrap --bootstrap-password $PASSWORD \
  --bootstrap-admin-url http://$M_IP:35357/v3/ \
  --bootstrap-internal-url http://$M_IP:35357/v3/ \
  --bootstrap-public-url http://$M_IP:5000/v3/ \
  --bootstrap-region-id RegionOne

#1.Restart the Apache service and remove the default SQLite database:
service apache2 restart
rm -f /var/lib/keystone/keystone.db

#2.Configure the administrative account
export OS_USERNAME=admin
export OS_PASSWORD=$PASSWORD
export OS_PROJECT_NAME=admin
export OS_USER_DOMAIN_NAME=Default
export OS_PROJECT_DOMAIN_NAME=Default
export OS_AUTH_URL=http://$M_IP:35357/v3
export OS_IDENTITY_API_VERSION=3

#3.This guide uses a service project that contains a unique user for each service that you add to your environment. Create the service project:
openstack project create --domain default --description "Service Project" service

#4.Regular (non-admin) tasks should use an unprivileged project and user. As an example, this guide creates the demo project and user.
openstack project create --domain default --description "Demo Project" demo
openstack user create --domain default --password $PASSWORD demo
openstack role create user
openstack role add --project demo --user demo user

#Unset the temporary OS_TOKEN and OS_URL environment variables:
unset OS_URL

#1.Edit the admin-openrc file and add the following content:
touch admin-openrc.sh
echo "export OS_PROJECT_DOMAIN_NAME=default" >> admin-openrc.sh
echo "export OS_USER_DOMAIN_NAME=default" >> admin-openrc.sh
echo "export OS_PROJECT_NAME=admin" >> admin-openrc.sh
echo "export OS_USERNAME=admin" >> admin-openrc.sh
echo "export OS_PASSWORD=$PASSWORD" >> admin-openrc.sh
echo "export OS_AUTH_URL=http://$M_IP:35357/v3" >> admin-openrc.sh
echo "export OS_IDENTITY_API_VERSION=3" >> admin-openrc.sh
echo "export OS_IMAGE_API_VERSION=2" >> admin-openrc.sh

#2.Edit the demo-openrc file and add the following content:
touch demo-openrc.sh
echo "export OS_PROJECT_DOMAIN_NAME=default" >> demo-openrc.sh
echo "export OS_USER_DOMAIN_NAME=default" >> demo-openrc.sh
echo "export OS_PROJECT_NAME=demo" >> demo-openrc.sh
echo "export OS_USERNAME=demo" >> demo-openrc.sh
echo "export OS_PASSWORD=$PASSWORD" >> demo-openrc.sh
echo "export OS_AUTH_URL=http://$M_IP:5000/v3" >> demo-openrc.sh
echo "export OS_IDENTITY_API_VERSION=3" >> demo-openrc.sh
echo "export OS_IMAGE_API_VERSION=2" >> demo-openrc.sh

# Download the source image:
wget http://download.cirros-cloud.net/0.3.5/cirros-0.3.5-x86_64-disk.img
}

install_horizon(){
#1.Install the packages:
sudo apt-get install -y openstack-dashboard

#2.Edit the /etc/openstack-dashboard/local_settings.py file and complete the following actions:
sed -i 's/OPENSTACK_HOST = "127.0.0.1"/OPENSTACK_HOST = "'$M_IP'"/g' /etc/openstack-dashboard/local_settings.py
sed -i "s/ALLOWED_HOSTS = '\*'/ALLOWED_HOSTS = \['\*', \]/g" /etc/openstack-dashboard/local_settings.py
sed -i "s/# memcached set CACHES to something like/# memcached set CACHES to something like\n\
SESSION_ENGINE = 'django.contrib.sessions.backends.cache'/g" /etc/openstack-dashboard/local_settings.py
sed -i "s/'LOCATION': '127.0.0.1:11211'/'LOCATION': '$M_IP:11211'/g" /etc/openstack-dashboard/local_settings.py
sed -i "s/http:\/\/%s:5000\/v2.0/http:\/\/%s:5000\/v3/g" /etc/openstack-dashboard/local_settings.py

sed -i 's/#OPENSTACK_API_VERSIONS = {/OPENSTACK_API_VERSIONS = {/g' /etc/openstack-dashboard/local_settings.py
sed -i 's/#    "data-processing": 1.1,/"identity": 3,/g' /etc/openstack-dashboard/local_settings.py
sed -i 's/#    "identity": 3,/"image": 2,/g' /etc/openstack-dashboard/local_settings.py
sed -i 's/#    "volume": 2,/"volume": 2,/g' /etc/openstack-dashboard/local_settings.py
sed -i 's/#    "compute": 2,/}/g' /etc/openstack-dashboard/local_settings.py

sed -i "s/#OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'default'/OPENSTACK_KEYSTONE_DEFAULT_DOMAIN = 'default'/g" /etc/openstack-dashboard/local_settings.py
sed -i 's/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "_member_"/OPENSTACK_KEYSTONE_DEFAULT_ROLE = "user"/g' /etc/openstack-dashboard/local_settings.py

sed -i "s/'enable_distributed_router': False,/'enable_distributed_router': True,/g" /etc/openstack-dashboard/local_settings.py

# multidomain support
sed -i "s/#OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = False/OPENSTACK_KEYSTONE_MULTIDOMAIN_SUPPORT = True/g" /etc/openstack-dashboard/local_settings.py

#permission Error Issue
sudo chown www-data /var/lib/openstack-dashboard/secret_key

#•Reload the web server configuration:
service apache2 reload
}

}

update_package
install_env_software
install_keystone
install_horizon