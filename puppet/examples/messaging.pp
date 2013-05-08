#
# Configure messaging on a host
#

class {"activemq::config":
  brokername => "msg1.lamourine.org",
  # Messaging admin
  admin_username => "admin",
  admin_password => "adminsecret",
  # message queue and access user
  msg_queue => "openshift",
  msg_username => "openshift",
  msg_password => "msgsecret",
  # jetty access user
  ctrl_username => "admin",
  ctrl_password => "ctrlsecret",
}

class {"activemq": }
