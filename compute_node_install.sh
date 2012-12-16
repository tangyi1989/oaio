#!/bin/bash
TOP_DIR=$(cd $(dirname "$0") && pwd)
ENABLED_SERVICES=n-cpu,n-net

#读取计算节点的配置, 
source $TOP_DIR/compute_node_settings 

source $TOP_DIR/install.sh
service openstack-nova-compute start
service openstack-nova-network start
