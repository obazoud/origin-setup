#
# An abstract definition of an OpenShift service using distinct external
# support services
#
# The top level classes describe the shared information for the service.
# Then each (puppet) node implements one of the host definitions for the
# (Openshift) broker, node and support services.
#
# This sample implements a complete service on four hosts (four puppet nodes):
# * OpenShift Broker
# * OpenShift Node
# * Messaging Service (ActiveMQ)
# * Data Server (MongoDB)
#
# It uses Route53 for publication (DNS) and the MongoDB for OpenShift broker
# authentication
#
# The support service installation and generic configurations are handled by
# 'standard' modules (where possible)

#
# OpenShift Origin service definitions
#
$openshift = {
  # OpenShift Service Parameters
  cloud_domain => 'app.example.org',
  broker_hosts => ['broker.infra.example.org'],
 
  datastore => {
    plugin => 'mongo',
    servers => []
    # more later
  },
 
  messaging => {
    plugin => 'mcollective',
    servers => []
    # more later
  },
 
  publication => {
    plugin => 'route53',
    # more later
  },
 
  authentication => {
  plugin => 'remote',
    # more later
  }
}
 

#
# keep the authentication information in a separate file
#
import 'secrets/*.pp'

# -----
# Puppet Node Definitions
# -----

import 'nodes/*.pp'
