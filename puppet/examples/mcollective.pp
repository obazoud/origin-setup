# Configure MCollective client

class {'mcollective':

  version => 'present',

  server => 'false',

  client => 'true',
  client_config => template('mcollective/client.cfg.erb'),
  # place this in the apached home?
  client_config_file => '/etc/mcollective/client.cfg',
  
  stomp_server => 'msg1.example.com',
}
