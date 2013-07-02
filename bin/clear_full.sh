#!/bin/bash

# delete all instances
echo "DELETING INSTANCES"
thor ec2:instance list --verbose | grep -v terminated | cut -d' ' -f1 | \
  xargs -I{} thor ec2:instance delete --force --id {}

echo "RENAMING INSTANCES"
thor ec2:instance list --verbose | grep -v terminated | cut -d' ' -f1 | \
  xargs -I{} thor ec2:instance rename --newname terminate --id {} 

records() {
  local _zone
  _zone=$1
  thor route53:record:list $_zone A | grep -v task | grep $_zone | sed -e "s/\.$_zone\.//" | tr ' ' :
}

#echo "DELETING DNS RECORDS"
#for RECORD in $(records infra.lamourine.org) ; do
#    echo A RECORD $RECORD
#    OIFS=$IFS
#    IFS=:
#    set $RECORD
#    IFS=$OIFS
#    NAME=$1
#    TYPE=$2
#    VALUE=$4

#    thor route53:record:delete infra.lamourine.org $NAME $TYPE $VALUE
#done

# remove all IPs
#echo "DELETING IPs"
#thor ec2:ip list | cut -d' ' -f1 | grep -v task: | xargs -I{} thor ec2:ip delete {}

echo "DELETING VOLUMES"
thor ec2:volume list | cut -d' ' -f1 | xargs -I{} thor ec2:volume delete {}

echo "removing ssh keys"
for HOSTNAME in puppet broker ident ; do
    ssh-keygen -R ${HOSTNAME}.infra.lamourine.org
done

for HOSTNAME in $(grep ec2- ~/.ssh/known_hosts | cut -d, -f1) ; do
    ssh-keygen -R ${HOSTNAME}
done
