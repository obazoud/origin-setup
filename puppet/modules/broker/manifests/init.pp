#
#
#
class broker::install {
  package { openshift-origin-broker:
    ensure => present,
  }

  package { openshift-origin-broker-util:
    ensure => present,
  }
}


class broker {
  include broker::install
}
  
