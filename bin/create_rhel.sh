#!/bin/sh
#
# Create RHEL instances of OpenShift Origin
#  This requires things to work on RHEL6 which is somewhat behind Fedora
#
# For example, the baseline Ruby is 1.8.7 and Puppet is 2.7 (from the OpenShift
# dependencies repository or EPEL)
#
INST_NAME=markllama-puppet-rhel6.4-1

# create a rhel 6.4 instane
thor origin:baseinstance ${INST_NAME} --baseos rhel6.4 --type m1.large $VERBOSE
thor ec2:instance tag --name ${INST_NAME} --tag owner --value markllama
thor ec2:instance tag --name ${INST_NAME} --tag purpose --value experiment
thor ec2:instance tag --name ${INST_NAME} --tag remote_user --value ec2-user

REMOTE_USER=ec2-user

hostname=$(thor ec2:instance hostname --name ${INST_NAME} ${VERBOSE})

# "manually" add deps repo to provide puppet2
thor origin:depsrepo $hostname --username ${REMOTE_USER} $VERBOSE
thor origin:prepare $hostname --username ${REMOTE_USER} --packages puppet2 git
#thor remote:yum:install $hostname puppet2 git --username ${REMOTE_USER} $VERBOSE
