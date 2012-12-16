#!/bin/bash

########################################################################
#
# Author : Tang Yi
# Email : tang_yi_1989@qq.com
# Date : 2012.11.12
#
# Openstack All in one
#
# 这个脚本的作用是离线安装CentOS的openstack, 目前仅计划安装和配置其中的3个
# 组件, nova , keystone , glance.
#
# 所要安装和配置的东西一共三种:
#
#   总线服务: Mysql 和 消息队列
#   openstack服务所依赖的包: rpm包和python的包
#   openstack的服务:nova, glance, keystone
#
# 根据服务器角色的不同,可以把服务器分成以下几种角色:
# glance(镜像服务), keystone(认证服务), nova-api(对外提供API), nova-compute,
# nova-network, vnc-proxy(提供VNC服务).
#
# 依赖包分成两总: general包(所有的服务都需要的包) 和 特定服务依赖的包
# TODO:细分包
#
# 注明:代码中的很多格式参考了 devstack( http://devstack.org/ )
#
#########################################################################


# Save trace setting
#XTRACE=$(set +o | grep xtrace)
#set +o xtrace

############################ INSTALL SETTINGS ###########################

TOP_DIR=$(cd $(dirname "$0") && pwd)
STACK_PACKAGES_DIR=$TOP_DIR/stack
DEST=${STACK_DEST:-/opt/stack}
TOOLS_DIR=$TOP_DIR/bin
ENABLED_SERVICES=${ENABLED_SERVICES:-glance,keystone,n-api,n-cpu,n-net,n-sch,n-novnc,horizon,mysql,rabbitmq}
INSTANCE_NAME_PREFIX=${INSTANCE_NAME_PREFIX:-instance-}
DATA_DIR=${DATA_DIR:-/nova/data}
LIBVIRT_TYPE=${LIBVIRT_TYPE:-kvm}

source $TOP_DIR/openrc

SERVICE_TENANT_NAME=${SERVICE_TENANT_NAME:-service}
SERVICE_TIMEOUT=${SERVICE_TIMEOUT:-60}

if [ -e $TOP_DIR/localrc ]; then
    source $TOP_DIR/localrc
fi

################################# FUNCTIONS #############################

source $TOP_DIR/functions
source $TOP_DIR/lib/mysql
source $TOP_DIR/lib/keystone
source $TOP_DIR/lib/glance
source $TOP_DIR/lib/nova

#################################################################
# 读取指定变量的值,如果localrc中没有密码,则提示用户输入,并且保存
# 到$TOP/localrc中.
#################################################################
function read_password {
    XTRACE=$(set +o | grep xtrace)
    set +o xtrace
    var=$1; msg=$2
    pw=${!var}

    localrc=$TOP_DIR/localrc

    # If the password is not defined yet, proceed to prompt user for a password.
    if [ ! $pw ]; then
        # If there is no localrc file, create one
        if [ ! -e $localrc ]; then
            touch $localrc
        fi

        # Presumably if we got this far it can only be that our localrc is missing
        # the required password.  Prompt user for a password and write to localrc.
        echo ''
        echo '################################################################################'
        echo $msg
        echo '################################################################################'
        echo "This value will be written to your localrc file so you don't have to enter it "
        echo "again.  Use only alphanumeric characters."
        echo "If you leave this blank, a random default value will be used."
        pw=" "
        while true; do
            echo "Enter a password now:"
            read -e $var
            pw=${!var}
            [[ "$pw" = "`echo $pw | tr -cd [:alnum:]`" ]] && break
            echo "Invalid chars in password.  Try again:"
        done
        if [ ! $pw ]; then
            pw=`openssl rand -hex 10`
        fi
        eval "$var=$pw"
        echo "$var=$pw" >> $localrc
    fi
    $XTRACE
}

################################ INIT #####################################

cp -r $TOP_DIR/files/service_setup/* /

############################## INSTALL STEPS ##############################

#Install general rpms
#TODO 此处没有对这些包的种类进行区分,
#     对于某些服务会有一些不必要的安装包
RPM_GENERALS=$TOP_DIR/rpms/generals
install_packages $RPM_GENERALS
general_service messagebus restart
general_service avahi-daemon restart

#Install general python packages
GENERAL_PY_PKGS=$TOP_DIR/py-pkgs/generals
install_py_pkgs_dir $GENERAL_PY_PKGS

#Install and setup mysql-server
if is_service_enabled mysql ; then
    MYSQL_RPMS_DIR=$TOP_DIR/rpms/services/mysql
    rpm -hiv --force --aid $MYSQL_RPMS_DIR/*.rpm #install mysql packages
fi

if is_service_enabled zeromq ; then
    ZEROMQ_PATH=$TOP_DIR/rpms/services/zeromq-2.1.9-1.el6.x86_64.rpm
    rpm -hiv $ZEROMQ_PATH
elif is_service_enabled rabbitmq ; then
    RABBIT_HOST=${RABBIT_HOST:-localhost}
    read_password RABBIT_PASSWORD "ENTER A PASSWORD TO USE FOR RABBIT."

    RABBITMQ_PATH=$TOP_DIR/rpms/services/rabbitmq
    rpm -hiv --force --aid $RABBITMQ_PATH/*.rpm
    service rabbitmq-server start
    rabbitmqctl change_password guest $RABBIT_PASSWORD
fi

#If this node is a compute node, install libvirt and kvm
#TODO setup something
VIRT_TOOLS_PATH=$TOP_DIR/rpms/virt
if is_service_enabled n-cpu ; then
    rpm -hiv --aid --force $VIRT_TOOLS_PATH/libvirt/*.rpm
    rpm -hiv --aid --force $VIRT_TOOLS_PATH/kvm/*.rpm
    if [ ! -e /usr/bin/qemu-system-x86_64 ] ; then
        ln -sf /usr/libexec/qemu-kvm /usr/bin/qemu-system-x86_64
        ln -sf /usr/libexec/qemu-kvm /usr/bin/qemu-kvm
    fi
    service libvirtd stop	#restart it
    service libvirtd start
fi

# Install and setup openstack services

if is_service_enabled nova ; then
    NOVA_PACKAGE=$STACK_PACKAGES_DIR/nova
    install_python_pacages $NOVA_PACKAGE $DEST
fi

if is_service_enabled glance ; then
    GLANCE_PACKAGE=$STACK_PACKAGES_DIR/glance
    install_python_pacages $GLANCE_PACKAGE $DEST
fi

if is_service_enabled keystone ; then
    KEYSTONE_PACKAGE=$STACK_PACKAGES_DIR/keystone
    install_python_pacages $KEYSTONE_PACKAGE $DEST
fi

if is_service_enabled horizon ; then
    DJANGO_PY_PKGS=$TOP_DIR/py-pkgs/django
    HORIZON_PACKAGE=$STACK_PACKAGES_DIR/horizon
    HORIZON_RPMS=$TOP_DIR/rpms/horizon

    rpm -hiv $HORIZON_RPMS/*.rpm
    install_py_pkgs_dir $DJANGO_PY_PKGS
    install_python_pacages $HORIZON_PACKAGE $DEST
fi

if is_service_enabled n-novnc ; then
   NOVNC_PACKAGE=$STACK_PACKAGES_DIR/novnc
   NOVNC_RPMS=$TOP_DIR/rpms/novnc
   
   rpm -hiv --aid --force $NOVNC_RPMS/*.rpm
   cp -r $NOVNC_PACKAGE $DEST
fi


#BUGFIX, it somewhat like a bug.
SITES_PACKAGES=/usr/lib/python2.6/site-packages
if [ -d $SITES_PACKAGES/PasteDeploy-1.5.0-py2.6.egg/paste ] ; then
    cp -rf $SITES_PACKAGES/PasteDeploy-1.5.0-py2.6.egg/paste/* $SITES_PACKAGES/paste
fi

######################### CONFIGURE STEPS ##########################

if is_service_enabled mysql ; then
    initalize_mysql
    configure_database_mysql
fi

if is_service_enabled keystone ; then
    read_password SERVICE_TOKEN "ENTER A SERVICE_TOKEN."
    read_password SERVICE_PASSWORD "ENTER A SERVICE_PASSWORD."
    read_password ADMIN_PASSWORD "ENTER ADMIN_PASSWORD(20 CHARS OR LESS)."
    configure_keystone
    init_keystone
    service_keystone start
    if ! timeout $SERVICE_TIMEOUT sh -c "while ! http_proxy= curl -s $KEYSTONE_AUTH_PROTOCOL://$SERVICE_HOST:$KEYSTONE_API_PORT/v2.0/ >/dev/null; do sleep 1; done"; then
      echo "keystone did not start"
      exit 1
    fi

    SERVICE_ENDPOINT=$KEYSTONE_AUTH_PROTOCOL://$KEYSTONE_AUTH_HOST:$KEYSTONE_AUTH_PORT/v2.0

    ADMIN_PASSWORD=$ADMIN_PASSWORD SERVICE_TENANT_NAME=$SERVICE_TENANT_NAME \
    SERVICE_PASSWORD=$SERVICE_PASSWORD \
    SERVICE_TOKEN=$SERVICE_TOKEN SERVICE_ENDPOINT=$SERVICE_ENDPOINT \
    SERVICE_HOST=$SERVICE_HOST DEVSTACK_DIR=$DEST/stack \
    ENABLED_SERVICES=$ENABLED_SERVICES \
        bash -x $TOP_DIR/files/keystone_data.sh

    # Set up auth creds now that keystone is bootstrapped
    export OS_AUTH_URL=$SERVICE_ENDPOINT
    export OS_TENANT_NAME=admin
    export OS_USERNAME=admin
    export OS_PASSWORD=$ADMIN_PASSWORD
fi

if is_service_enabled glance ; then
    configure_glance
    init_glance
fi

if is_service_enabled nova; then
    configure_nova
    create_nova_conf
    init_nova
    service_nova
fi

#if is_service_enabled horizon; then
#fi


############################ DO SOMETHING ELSE ##############################

# Launch the Glance services and upload a tty linux image for test
if is_service_enabled glance; then

    service_glance start
    sleep 5
    TOKEN=$(keystone token-get | grep ' id ' | get_field 2)
    upload_image $TOP_DIR/files/images/tty.tgz $TOKEN
fi
