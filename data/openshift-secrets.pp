#
# OpenShift Origin sensitive information
#

$secrets = {
  openshift => {
    datastore => 'dbsecret',
    message_bus => 'msgsecret',
    message_end => 'mcsecret',
    publishing => 'dnssecret',
  },
  mongodb => {
    admin => 'dbadminsecret'
  },

  freeipa => {
    admin => 'ipasecret',
    ldap => 'dssecret'
  }
}
