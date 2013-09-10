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
AWSTYPE=${AWSTYPE="t1.micro"} # | m1.small|m1.medium|m1.large

# origin:baseinstance
thor origin:baseinstance $NAME --baseos ${BASEOS} --type ${AWSTYPE} ${VERBOSE}
HOSTNAME=$(thor ec2:instance hostname --name $NAME)
# origin:prepare
#thor origin:prepare $HOSTNAME 



#hostname=$(thor ec2:instance hostname --id $instanceid)

# "manually" add deps repo to provide puppet2
#thor origin:depsrepo $hostname

# install puppet2 and git
#thor remote:yum install $hostname puppet2 git

# pull down git repo for puppet modules
