#
# Define the contents of an ActiveMQ broker host and a configuration
# for OpenShift messaging
#
# Variables
#   message server hostname (brokername)
#   message server IP address
#   ActiveMQ console admin username (admin)
#   ActiveMQ console admin password
#   ActiveMQ messaging admin account username (admin)
#   ActiveMQ messaging admin account password
#   OpenShift messaging account name (mcollective)
#   OpenShift messaging account password
#   OpenShift messaging topic/queue name (mcollective)

# Files:
#    ActiveMQ service
#        /etc/activemq/activemq.xml
#        /etc/activemq/activemq-stomp.xml
#    ActiveMQ monitoring console
#        /etc/activemq/jetty.xml
#        /etc/activemq/jetty-realm.properties
#
#
# Services:
#   activemq
#   start/stop/restart/status
#   enabled
#
# Network Ports:
#   61613/TCP messaging (open to broker/node hosts)
#   8161/TCP monitoring (localhost only)
#
# Encryption
#   Keys (TBD)
#
# Variables
#
# 

# This should be the Java ActiveMQ package from the openshift extras repo
class activemq::install {
  package { activemq:
    ensure => present,
  }
}

class activemq::params {

}

class activemq::config (
  $brokername,
  # Messaging admin
  $admin_username,
  $admin_password,
  # message queue and access user
  $msg_queue,
  $msg_username,
  $msg_password,
  # jetty access user
  $ctrl_username,
  $ctrl_password,
  ) {

  file { "/etc/activemq/activemq.xml":
    ensure => present,
    content => template("activemq/activemq-stomp.xml.erb"),
    owner => 'root',
    group => 'root',
    mode => 0644,
    require => Class["activemq::install"],
    notify => Class["activemq::service"],
    
  }

  file { "/etc/activemq/jetty.xml":
    ensure => present,
    content => template("activemq/jetty.xml.erb"),
    owner => 'root',
    group => 'root',
    mode => 0644,
    require => Class["activemq::install"],
    notify => Class["activemq::service"],
  }

  file { "/etc/activemq/jetty-realm.properties":
    ensure => present,
    content => template("activemq/jetty-realm.properties.erb"),
    owner => 'root',
    group => 'root',
    mode => 0644,
    require => Class["activemq::install"],
    notify => Class["activemq::service"],
  }
}

class activemq::service {
    service { "activemq":
      ensure => running,
      hasstatus => true,
      hasrestart => true,
      enable => true,
      require => Class["activemq::config"],
    }
}

class activemq {
  include activemq::install, activemq::config, activemq::service
}

