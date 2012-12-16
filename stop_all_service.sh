#!/bin/bash

service openstack-glance-registry stop
service openstack-glance-api stop
service openstack-keystone stop
service openstack-nova-compute stop
service openstack-nova-network stop
service openstack-nova-scheduler stop
service openstack-nova-api stop

