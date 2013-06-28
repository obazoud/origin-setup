#!/bin/bash

INFRAZONE=infra.lamourine.org

PUPPETHOST=puppet.${INFRAZONE}
SERVICEHOSTS="broker data1 message1 node1"

#VERBOSE="--verbose"

syslog_puppet() {
    # BASHISM
    local _puppetclient
    local _puppetmaster
    _puppetclient=$1
    _puppetmaster=$2

    # push the rsyslog remote file to the client
    thor remote:file:put ${_puppetclient} data/rsyslog-puppet.conf-remote ${VERBOSE}

    # replace the syslog target on the remote file
    

    # copy the remote file to /etc/rsyslog.d/puppet.conf
    thor remote:file:copy ${_puppetclient} rsyslog-puppet.conf-remote /etc/rsyslog.d/puppet.conf --sudo ${VERBOSE}

    thor remote:service:restart ${_puppetclient} rsyslog ${VERBOSE}
    thor remote:service:restart ${_puppetclient} puppet ${VERBOSE}
}


create_puppetmaster() {
    local _hostname
    local _sitrepo

    _hostname=$1
    _siterepo=$2

    echo "# creating puppetmaster"
    thor origin:baseinstance puppet --hostname ${_hostname} \
        --securitygroup default puppetmaster ${VERBOSE}
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
    thor origin:baseinstance ${_instancename} ${_hostarg} \
        --securitygroup default #{_securitygroup} ${VERBOSE}
    if [ -z "${_hostname}" ] ; then
        _hostname=$(thor ec2:instance hostname --name ${_instancename})
    fi
    echo thor remote:available ${_hostname} ${VERBOSE}
    thor origin:puppetclient ${_hostname} ${_puppethost} ${VERBOSE}
    syslog_puppet ${_hostname} ${_puppethost}
}

PUPPETHOST=puppet.infra.lamourine.org
create_puppetmaster ${PUPPETHOST} https://github.com/markllama/origin-puppet

create_puppetclient broker broker ${PUPPETHOST} broker.infra.lamourine.org
create_puppetclient ident freeipa ${PUPPETHOST} ident.infra.lamourine.org
create_puppetclient data1 datastore ${PUPPETHOST}
# Create a node entry for a data store with this hostname
create_puppetclient message1 messagebroker ${PUPPETHOST}

create_puppetclient node1 node ${PUPPETHOST}


