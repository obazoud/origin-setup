# == Create a DNS dynamic zone for a BIND server
#
# === Parameters
#    zone
#    key_string
#    nameserver (?)
#
#    create config file
#    create initial zone file
#    add entry to master config file
#

class named::dynamic_zone {

  # dynamic configuration file
  file { 'dynamic configuration':
    path => "/var/named/${zone}.conf",
    content => template('named/dynamic_zone.conf.erb'),
    owner => 'named',
    group => 'named',
    mode => '0660',
  }
  
  # initial zone file
  file { 'dynamic zone':
    path => "/var/named/dynamic/${zone}.db",
    content => template('named/dynamic_zone.db.erb'),
    owner => 'named',
    group => 'named',
    mode => '0660',
    require => File['/var/named/dynamic'],
  }

  
}

class {"named::dynamic_zone":}
