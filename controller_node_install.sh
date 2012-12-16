
TOP_DIR=$(cd $(dirname "$0") && pwd)
ENABLED_SERVICES=glance,keystone,n-api,n-sch,n-novnc,horizon,mysql,rabbitmq

source $TOP_DIR/install.sh

service openstack-keystone start
service openstack-nova-scheduler start
service openstack-nova-consoleauth start
service openstack-nova-novncproxy start
service openstack-nova-api start
