#
# OpenShift Origin sensitive information
#

$openshift::secrets = {
  datastore => 'dbsecret',
  message_bus => 'msgsecret',
  message_end => 'mcsecret',
  publishing => 'dnssecret',
}

# Initialize the mongo database
$mongodb::secrets = {
  admin => 'dbadminsecret'
}

$freeipa::secrets = {
  admin => 'ipasecret',
  ldap => 'dssecret'
}
