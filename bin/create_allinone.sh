#!/bin/sh
#
# Create RHEL instances of OpenShift Origin
#  This requires things to work on RHEL6 which is somewhat behind Fedora
#
# For example, the baseline Ruby is 1.8.7 and Puppet is 2.7 (from the OpenShift
# dependencies repository or EPEL)
#
NAME=$1
if [ -z "$NAME" ] ; then
  echo "ERROR - missing required argument: NAME"
  exit 1
fi

BASEOS=$2
BASEOS=${BASEOS:="fedora19"} # | rhel6.4 | centos6.4

AWSTYPE=$3
AWSTYPE=${AWSTYPE:="t1.micro"} # | m1.small|m1.medium|m1.large

AWS_CONFIG_FILE=${AWS_CONFIG_FILE:="./.awscred"}
REMOTE_USER=$(ruby -e "require 'parseconfig' ; puts ParseConfig.new('$AWS_CONFIG_FILE')['$BASEOS']['RemoteUser']")
REMOTE_USER=${REMOTE_USER:=fedora}

# make it right regardless
if [ -n "$VERBOSE" ] ; then
    VERBOSE="--verbose"
fi

# origin:baseinstance
thor origin:baseinstance $NAME --baseos ${BASEOS} --type ${AWSTYPE} ${VERBOSE}

HOSTNAME=$(thor ec2:instance hostname --name $NAME)
# origin:prepare

PUPPET_RPM=puppet

case $BASEOS in
    "rhel6.4")
        # "manually" add deps repo to provide puppet2
        thor origin:depsrepo $HOSTNAME --username ${REMOTE_USER} ${VERBOSE}
        PUPPET_RPM="puppet2"
        ;;
    
    "centos6.4")
        # enable epel for puppet
        #thor remote:yum:install $HOSTNAME http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm --username ${REMOTE_USER} ${VERBOSE}
        thor origin:depsrepo $HOSTNAME --username ${REMOTE_USER} ${VERBOSE}
        PUPPET_RPM="puppet2"
        ;;

    *)
        
esac

thor origin:prepare $HOSTNAME --packages git ${PUPPET_RPM} --username ${REMOTE_USER} ${VERBOSE}

if [ "$BASEOS" = 'rhel' -o "$BASEOS" = 'centos' ] ; then
  thor remote:file:mkdir ${HOSTNAME} /etc/puppet/modules --sudo --parents --username ${REMOTE_USER} ${VERBOSE}
fi

thor puppet:module:install ${HOSTNAME} puppetlabs-stdlib --username ${REMOTE_USER} ${VERBOSE}

PUPPET_GIT_URL=https://github.com/markllama/origin-puppet.git
PUPPET_REPODIR=$(basename $PUPPET_GIT_URL .git)

thor remote:git:clone ${HOSTNAME} ${PUPPET_GIT_URL} --username ${REMOTE_USER} ${VERBOSE}
thor remote:git:submodule:init ${HOSTNAME} $PUPPET_REPODIR --username ${REMOTE_USER} ${VERBOSE}
thor remote:git:submodule:update ${HOSTNAME} $PUPPET_REPODIR --username ${REMOTE_USER} ${VERBOSE}




