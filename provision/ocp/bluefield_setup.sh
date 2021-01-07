#!/bin/bash

# Set BF system time
# system time is not sychronized on BF card, set it manually for testing
# or start ntpd to synchronize system time automatically from remote server
date -s "11 DEC 2020 03:17:00"

# Disable firewalld
systemctl disable firewalld
systemctl stop firewalld

# Disable Selinux
setenforce 0

### Configure BF device in switchdev mode ###

# Note: unload the mellanox drivers on the host before running switchdev config

# Unload mlx drivers on host
# modprobe -rv mlx5_{ib,core}

# Set device in switchdev mode
/usr/bin/connectx_eswitch_mode_config.sh

# Reload mlx drivers on host
# modprobe -av mlx5_{ib,core}

# Provision SR-IOV VFs on the host
# echo 2 > /sys/class/net/<host-bf-int>/device/sriov_numvfs

# Rename VF representor interface names
# Ovn smart nic cni assumes the VF rep names in the format of pfxvfy
# where x is last bit of pf pci address, y is vf index number
# Change the interface names according to your own environment.

# ip link set eth3 down
# ip link set eth4 down
# ip link set eth3 name pf0vf0
# ip link set eth4 name pf0vf1


### Configure BF management port (ssh) ###

# Run below cmd on BF if eth0 is not yet managed by NM
# nmcli con add connection.interface-name eth0 type ethernet connection.id eth0

nmcli con mod eth0 ipv4.addresses 10.1.0.2/24
nmcli con mod eth0 ipv4.method manual
nmcli con up eth0
nmcli con show

# Assign IP address to tmfifo_net0 (directly connected with eth0 on BF) on host
# ip addr add 10.1.0.1/24 dev tmfifo_net0

# Login to BF via management port
# ssh root@10.1.0.2  passwd: bluefield

# Run below cmd if eth1 is not yet a bridge port
# nmcli con add type bridge-slave ifname eth1 master br0 connection.id br0-port1


### Configure openvswitch on BF ###

# Install openvswitch pkg
dnf install -y \
http://download.eng.bos.redhat.com/brewroot/vol/rhel-8/packages/openvswitch2.13/2.13.0/67.el8fdp/$(uname -m)/openvswitch2.13-2.13.0-67.el8fdp.$(uname -m).rpm \
http://download.eng.bos.redhat.com/brewroot/vol/rhel-8/packages/openvswitch2.13/2.13.0/67.el8fdp/$(uname -m)/openvswitch2.13-devel-2.13.0-67.el8fdp.$(uname -m).rpm \
http://download.eng.bos.redhat.com/brewroot/vol/rhel-8/packages/openvswitch2.13/2.13.0/67.el8fdp/$(uname -m)/python3-openvswitch2.13-2.13.0-67.el8fdp.$(uname -m).rpm \
http://download.eng.bos.redhat.com/brewroot/vol/rhel-8/packages/openvswitch-selinux-extra-policy/1.0/23.el8fdp/noarch/openvswitch-selinux-extra-policy-1.0-23.el8fdp.noarch.rpm


# Enable/start openvswitch service
systemctl enable openvswitch
systemctl start openvswitch

# Configure external bridge br-ex
# This is done by MCO in normal openshift deployment, need to be manually added on BF.
# All below commands can be replaced by equivalent nmcli commands.

# bridge name: br-ex
# bridge uplink port: eth1
# bridge hostlink port: enp3s0f0np0

ovs-vsctl add-br br-ex
ovs-vsctl add-port br-ex eth1
ovs-vsctl add-port br-ex enp3s0f0np0

# Set bridge uplink so that ovnkube-node can find the right uplink
ovs-vsctl set Bridge br-ex external-ids:bridge-uplink=eth1
# Enable ovs hardware offload
ovs-vsctl set Open_vSwitch . other_config:hw-offload=true

# Restart openvswitch service
systemctl restart openvswitch

# Allocate IP on br-ex
pkill dhclient
dhclient -v br-ex

### Run OVN components on BF ###

# Prepare ovn ca/cert/config files

mkdir -p /root/ovn-ca
mkdir -p /root/ovn-cert
mkdir -p /root/ovnkube-config
mkdir -p /var/run/secrets/kubernetes.io/serviceaccount

# Run the cmd on host that has access to API server
# get the ca-bundle.crt content and save it under /root/ovn-ca/ca-bundle.crt
oc get configmap ovn-ca -n openshift-ovn-kubernetes -o yaml

# get tls.{key,crt} contents and save them under /root/ovn-cert/tls.{key,tls} separately
oc get secret ovn-cert -n openshift-ovn-kubernetes -o yaml

# get ovnkube.conf content and save it under /root/ovnkube-config/ovnkube.conf
oc get configmap ovnkube-config -n openshift-ovn-kubernetes -o yaml

# get ca.crt from running ovn pods and save it under /var/run/secrets/kubernetes/io/serviceaccount/ca.crt
oc -n openshift-ovn-kubernetes exec <ovnkube-node-9l99q> -c ovnkube-node -- cat /var/run/secrets/kubernetes.io/serviceaccount/ca.crt

# get token from running ovn pods and save it under /var/run/secrets/kubernetes/io/serviceaccount/token
oc -n openshift-ovn-kubernetes exec <ovnkube-node-9l99q> -c ovnkube-node -- cat /var/run/secrets/kubernetes.io/serviceaccount/token

# add api-int.<domain> in /etc/hosts
sed -i -e '$a192.168.111.5	api-int.sriov.ovn.testing' /etc/hosts

# Run ovn-controller container
# bluefield_ovn_node.sh

# Run ovnkube-node container
# bluefield_ovn_controller.sh
