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
  $hostname,
  $console_admin_username = 'admin',
  $console_admin_password,
  $broker_admin_username = 'admin',
  $broker_admin_password,
  $msg_queue = 'openshift',
  $msg_username = 'openshift',
  $msg_password,
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
    content => template("jetty.xml.erb"),
    owner => 'root',
    group => 'root',
    mode => 0644,
    require => Class["activemq::install"],
    notify => Class["activemq::service"],
  }

  file { "/etc/activemq/jetty-realm.properties":
    ensure => present,
    content => template("jetty-realm.properties.erb"),
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
      require => Class["ssh::config"],
    }
}

class activemq {
  include activemq::install, activemq::config, activemq::service
}
