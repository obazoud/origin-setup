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

class activemq-broker {
  package { activemq:
    ensure => present,
  }


  
  
}
