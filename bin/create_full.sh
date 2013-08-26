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

#
# Take a node template and apply a hostname.
# 
create_node_file() {
  local _gitroot
  local _branch

  local _template
  local _hostname
  local _filename


  _gitroot=$1
  _branch=$2

  _template=$3
  _hostname=$4
  _filename=$5

  (cd $_gitroot ;
    sed -e "/^node '/s/'[^']*'/'$_hostname'/" $_template > $_filename ;
    git add $_filename ;
    git commit -m "'creating template for hostname $_hostname'" $_filename ;
    git push origin $(current_branch)
  )

}

current_branch() {
  local _gitroot
  local _chdir

  _gitroot=$1

  if [ -n "$1" ] 
  then
      _chdir="cd $_gitroot"
  fi

  ($_chdir ; git branch | grep \* | cut -d' ' -f2)
}

create_puppetmaster() {
    local _hostname
    local _sitrepo
    local _sitebranch

    _hostname=$1
    _siterepo=$2
    _sitebranch=$3

    echo "# creating puppetmaster"
    thor origin:baseinstance puppet --hostname ${_hostname} \
        --securitygroup default puppetmaster ${VERBOSE} --baseos ${BASEOS}

    thor ec2:instance tag --name puppet --tag purpose --value puppetinstall

    thor remote:available ${_hostname} ${VERBOSE}

    thor origin:puppetmaster ${_hostname} \
        --siterepo $_siterepo ${VERBOSE} --storedconfigs

    # Enable inbound syslog
    #thor remote:firewall:stop ${_hostname} ${VERBOSE}
    thor remote:firewall:port ${_hostname} 514 ${VERBOSE}
    #thor remote:firewall:start ${_hostname} ${VERBOSE}

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

    thor remote:file:put ${_hostname} data/openshift-secrets.pp --destpath site/manifests/secrets/openshift-secrets.pp ${VERBOSE}

}

create_puppetclient() {
    local _instancename
    local _securitygroup
    local _puppethost
    local _hostname
    local _ec2_type
    _instancename=$1
    _securitygroup=$2
    _puppethost=$3
    _hostname=$4
    _ec2_type=$5

    local _hostarg
    local _typearg

    if [ -n "$_hostname" ] ; then
        _hostarg="--hostname ${_hostname}"
    fi

    if [ -n "$_ec2_type" ] ; then
        _typearg="--type ${_ec2_type}"
    fi
    echo
    echo "# creating $_hostname"
    thor origin:baseinstance ${_instancename} ${_typearg} ${_hostarg} \
        --baseos ${BASEOS} --securitygroup default ${_securitygroup} ${VERBOSE} 
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


create_data1() {
    local _template
    local _nodefile

    # Create a node entry for a data store with this hostname
    create_puppetclient data1 datastore ${PUPPETHOST}

    DATAHOST=$(thor ec2:instance hostname --name data1)

    _template=datastore.pp
    _nodefile=data1.infra.lamourine.org.pp

    create_node_file $PUPPET_NODE_ROOT $(current_branch) $_template $DATAHOST $_nodefile
}

# update the contents of the new file

create_message1() {
    local _template
    local _nodefile

    create_puppetclient message1 messagebroker ${PUPPETHOST}

    MSGHOST=$(thor ec2:instance hostname --name message1)

    _template=messaging.pp
    _nodefile=message1.infra.lamourine.org.pp

    create_node_file $PUPPET_NODE_ROOT $(current_branch) $_template $MSGHOST $_nodefile

}

create_node1() {
    local _template
    local _nodefile

    create_puppetclient node1 node ${PUPPETHOST}

    NODEHOST=$(thor ec2:instance hostname --name node1)

    _template=node.pp
    _nodefile=node1.infra.lamourine.org.pp

    create_node_file $PUPPET_NODE_ROOT $(current_branch) $_template $NODEHOST $_nodefile

}


#====
#Main
#====


PUPPETHOST=puppet.infra.lamourine.org
PUPPET_NODE_ROOT=../origin-puppet/manifests/nodes
PUPPET_BRANCH=$(current_branch ${PUPPET_NODE_ROOT})

#create_puppetmaster ${PUPPETHOST} https://github.com/markllama/origin-puppet ${PUPPET_BRANCH}

#create_puppetclient ident freeipa ${PUPPETHOST} ident.infra.lamourine.org m1.small
#sleep 2
#thor remote:service:restart ident.infra.lamourine.org firewalld ${VERBOSE}
#sleep 2

# Build the support services before creating the broker so that they can be
# registered.

#create_data1

DATA1_HOSTNAME=$(thor ec2:hostname --name data1)

#create_message1

MESSAGE1_HOSTNAME=$(thor ec2:hostname --name message1)

# update broker and node puppet scripts with support service information
# set_service_hostnames $DATA1_HOSTNAME $MESSAGE1_HOSTNAME

#create_puppetclient broker broker ${PUPPETHOST} broker.infra.lamourine.org

#create_node1 $MESSAGE1_HOSTNAME


thor remote:git:pull puppet.infra.lamourine.org site --branch ${PUPPET_BRANCH}
