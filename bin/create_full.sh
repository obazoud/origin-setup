#!/bin/bash

BASEOS=${BASEOS:="fedora19"}
PUPPETAGENT=${PUPPETAGENT:="puppetagent"}

INFRAZONE=infra.lamourine.org

PUPPETHOST=puppet.${INFRAZONE}
SERVICEHOSTS="broker data1 message1 node1"

#VERBOSE="--verbose"

syslog_puppet() {
    # BASHISM
    local _puppetclient
    local _puppetmaster
    local _puppetservice
    _puppetclient=$1
    _puppetmaster=$2
    _puppetservice=${3:-'puppet'}

    # push the rsyslog remote file to the client
    thor remote:file:put ${_puppetclient} data/rsyslog-puppet.conf-remote ${VERBOSE}

    # replace the syslog target on the remote file
    

    # copy the remote file to /etc/rsyslog.d/puppet.conf
    thor remote:file:copy ${_puppetclient} rsyslog-puppet.conf-remote /etc/rsyslog.d/puppet.conf --sudo ${VERBOSE}

    thor remote:service:restart ${_puppetclient} rsyslog ${VERBOSE}
    thor remote:service:restart ${_puppetclient} ${_puppetservice} ${VERBOSE}
}


create_puppetmaster() {
    local _hostname
    local _sitrepo
    local _sitebranch

    _hostname=$1
    _siterepo=$2

    echo "# creating puppetmaster"
    thor origin:baseinstance puppet --hostname ${_hostname} \
        --securitygroup default puppetmaster ${VERBOSE} --baseos ${BASEOS}

    thor ec2:instance tag --name puppet --tag purpose --value puppetinstall

    thor remote:available ${_hostname} ${VERBOSE}
    thor origin:puppetmaster ${_hostname} \
        --siterepo $_siterepo ${VERBOSE}

    # Enable inbound syslog
    thor remote:firewall:stop ${_hostname} ${VERBOSE}
    thor remote:firewall:port ${_hostname} 514 ${VERBOSE}
    thor remote:firewall:start ${_hostname} ${VERBOSE}

    # five \ because bourne takes one pair here, and one pair there augtool takes 1
    thor remote:augeas:set ${_hostname} \
        "'/files/etc/rsyslog.conf/\\\\\$ModLoad[last()+1]'" imtcp ${VERBOSE}
    thor remote:augeas:set ${_hostname} \
        "'/files/etc/rsyslog.conf/\\\\\$InputTCPServerRun'" 514 ${VERBOSE}
    thor remote:file:put ${_hostname} data/rsyslog-puppet.conf ${VERBOSE}
    thor remote:file:copy ${_hostname} rsyslog-puppet.conf \
        /etc/rsyslog.d/puppet.conf --sudo ${VERBOSE}
    thor remote:file:touch ${_hostname} /var/log/puppet.log --sudo ${VERBOSE}
    thor remote:service:restart ${_hostname} rsyslog ${VERBOSE}

    thor remote:git:checkout ${_hostname} site ${_sitebranch}

}

create_puppetclient() {
    local _instancename
    local _securitygroup
    local _puppethost
    local _hostname
    _instancename=$1
    _securitygroup=$2
    _puppethost=$3
    _hostname=$4

    local _hostarg

    if [ -n "$_hostname" ] ; then
        _hostarg="--hostname ${_hostname}"
    fi

    echo
    echo "# creating $_hostname"
    thor origin:baseinstance ${_instancename} ${_hostarg} --baseos ${BASEOS} \
        --securitygroup default ${_securitygroup} ${VERBOSE} 
    if [ -z "${_hostname}" ] ; then
        _hostname=$(thor ec2:instance hostname --name ${_instancename})
    fi

    thor ec2:instance tag --name ${_instancename} --tag purpose --value puppetinstall

    echo thor remote:available ${_hostname} ${VERBOSE}
    thor origin:puppetclient ${_hostname} ${_puppethost} ${VERBOSE}
    syslog_puppet ${_hostname} ${_puppethost} ${PUPPETAGENT}
}


#ssh-keygen -R puppet.infra.lamourine.org
#ssh-keygen -R broker.infra.lamourine.org
#ssh-keygen -R infra.infra.lamourine.org

#create_puppetclient ident freeipa ${PUPPETHOST} ident.infra.lamourine.org


create_data1() {
    # Create a node entry for a data store with this hostname
    create_puppetclient data1 datastore ${PUPPETHOST}

    DATAHOST=$(thor ec2:instance hostname --name data1)

    # copy the data1.infra.pp to <hostname>.pp
    #cp ${PUPPET_NODE_ROOT}/data1.infra.pp ${PUPPET_NODE_ROOT}/${DATAHOST}.pp
    #sed -i -e "/node/s/^.*$/node '${DATAHOST}' {/" ${PUPPET_NODE_ROOT}/${DATAHOST}.pp
    #(cd $PUPPET_NODE_ROOT ; git add ${DATAHOST}.pp ; git commit -m "adding datahost ${DATAHOST}")
    #(cd $PUPPET_NODE_ROOT ; git push origin ${PUPPET_BRANCH})
    #thor remote:git:checkout ${PUPPETHOST} site ${PUPPET_BRANCH}
    #thor remote:git:pull ${PUPPETHOST} site --branch ${PUPPET_BRANCH}
}
# update the contents of the new file

create_message1() {
    create_puppetclient message1 messagebroker ${PUPPETHOST}
    MSGHOST=$(thor ec2:instance hostname --name message1)


    #cp ${PUPPET_NODE_ROOT}/message1.infra.pp ${PUPPET_NODE_ROOT}/${MSGHOST}.pp
    #sed -i -e "/node/s/^.*$/node '${MSGHOST}' {/" ${PUPPET_NODE_ROOT}/${MSGHOST}.pp
    #(cd $PUPPET_NODE_ROOT ; git add ${MSGHOST}.pp ; git commit -m "adding datahost ${MSGHOST}")
    #(cd $PUPPET_NODE_ROOT ; git push origin ${PUPPET_BRANCH})
    #thor remote:git:pull ${PUPPETHOST} site --branch ${PUPPET_BRANCH}
}

create_node1() {

    create_puppetclient node1 node ${PUPPETHOST}

    #NODEHOST=$(thor ec2:instance hostname --name node1)
    #cp ${PUPPET_NODE_ROOT}/node1.infra.pp ${PUPPET_NODE_ROOT}/${NODEHOST}.pp
    #sed -i -e "/^node '/s/^.*$/node '${NODEHOST}' {/" ${PUPPET_NODE_ROOT}/${NODEHOST}.pp
    #(cd $PUPPET_NODE_ROOT ; git add ${NODEHOST}.pp ; git commit -m "adding nodehost ${NODEHOST}")
    
    #(cd $PUPPET_NODE_ROOT ; git push origin ${PUPPET_BRANCH})
    #thor remote:git:pull ${PUPPETHOST} site --branch ${PUPPET_BRANCH}
}


#====
#Main
#====


PUPPETHOST=puppet.infra.lamourine.org
PUPPET_NODE_ROOT=../origin-puppet/manifests/nodes
PUPPET_BRANCH=$(cd ${PUPPET_NODE_ROOT} ; git branch | cut -d' ' -f2)

create_puppetmaster ${PUPPETHOST} https://github.com/markllama/origin-puppet baseline

create_puppetclient broker broker ${PUPPETHOST} broker.infra.lamourine.org

create_data1
create_message1
create_node1
