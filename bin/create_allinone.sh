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
BASEOS=${BASEOS:="rhel6.4"} # | fedora19 | centos6.4

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
        thor remote:yum:install $HOSTNAME http://dl.fedoraproject.org/pub/epel/6/x86_64/epel-release-6-8.noarch.rpm --username ${REMOTE_USER} ${VERBOSE}
        ;;

    *)
        
esac

thor origin:prepare $HOSTNAME --packages git ${PUPPET_RPM} --username ${REMOTE_USER} ${VERBOSE}




