#!/bin/sh
#
# Create RHEL instances of OpenShift Origin
#  This requires things to work on RHEL6 which is somewhat behind Fedora
#
# For example, the baseline Ruby is 1.8.7 and Puppet is 2.7 (from the OpenShift
# dependencies repository or EPEL)
#

# create a rhel 6.4 instance
instanceid=$(thor ec2:instance create | cut -d: -f2) # get the instance id out

hostname=$(thor ec2:instance hostname --id $instanceid)

# "manually" add deps repo to provide puppet2
thor origin:depsrepo $hostname

# install puppet2 and git
thor remote:yum install $hostname puppet2 git

# pull down git repo for puppet modules
