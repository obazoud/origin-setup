# A module to create a dynamic DNS service using BIND named
#
class named {
  package { ['bind', 'bind-utils', 'rsyslog']:
    ensure => present,
  }

  exec { 'restart rsyslog':
    command => "/usr/bin/systemctl restart rsyslog.service",
    require => Package['rsyslog'],
  }

  # Split Named logging out to its own file
  file { "/etc/rsyslog.d/named.conf":
    owner => 'root',
    group => 'root',
    mode => 0644,
    content => template('named/rsyslog-named.conf.erb'),
    require => Exec['restart rsyslog'],
    #notify => Service['rsyslog']
  }

  # Touch the log file to prime it
  file { "/var/log/named.log":
    ensure => present,
    owner => 'root',
    group => 'root',
    mode => 0600,
    require => File['/etc/rsyslog.d/named.conf']
  }

  # Create the access key to manage the named service
  exec { 'create rndc.key':
    # urandom is not cryptographically strong, but won't hang
    command => '/usr/sbin/rndc-confgen -a -r /dev/urandom',
    unless  => '/usr/bin/[ -f /etc/rndc.key ]',
    require => Package['bind'],
  }

  file { '/etc/rndc.key':
    owner   => 'root',
    group   => 'named',
    mode    => '0640',
    require => Exec['create rndc.key'],
  }

  # define a how to create dynamic zone config files
  define dynamic_zone($zone,
                            $secret,
                            $serial,
                            $admin,
                            $nameservers   = [['localhost','127.0.0.1']],
                            $ttl           = "30",
   ) {
    file { "${zone}.conf":
      path => "/var/named/${zone}.conf",
      owner => 'named',
      group => 'named',
      mode => 0640,
      require => File['named.conf'],
      content => template('named/dynamic.conf.erb'),
      notify => Service['named'],
    }

    file { "${zone}.db":
      path => "/var/named/dynamic/${zone}.db",
      owner => 'named',
      group => 'named',
      mode => 0640,
      require => File["${zone}.conf"],
      content => template('named/dynamic.db.erb'),
    }

  }
    # add a line to /etc/named.conf
}

class {named:}
