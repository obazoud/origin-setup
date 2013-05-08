# Configure MCollective client


class {'mcollective::client':

  #topicprefix => '/topic/',
  main_collective => 'openshift',
  collectives => 'openshift',

  # libdir => '/usr/libexec/mcollective',
  # logger_type => 'file'
  # logfile => '/var/log/mcollective-client'
  # loglevel => 'warn'

  mc_security_provider => 'psk',
  mc_security_psk => 'mcsecret',

  stomp_server => 'msg1.example.com',
  stomp_port => '61613',
  stomp_user => 'openshift',
  stomp_passwd => 'msgsecret',
}
