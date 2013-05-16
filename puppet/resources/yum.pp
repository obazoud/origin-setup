# Define yum repositories
#

$mirror_base_url = $::operatingsystem ? {
  'Fedora' => "https://mirror.openshift.com/pub/openshift-origin/fedora-${::operatingsystemrelease}/${::architecture}/",
  'Centos' => "https://mirror.openshift.com/pub/openshift-origin/rhel-6/${::architecture}/",
  default  => "https://mirror.openshift.com/pub/openshift-origin/rhel-6/${::architecture}/",
}


yumrepo { 'openshift-origin-deps':
  name     => 'openshift-origin-deps',
  baseurl  => $mirror_base_url,
  enabled  => 1,
  gpgcheck => 0,
}


case $install_repo {
  'nightlies' : {
    case $::operatingsystem {
      'Fedora' : {
        $install_repo_path = "https://mirror.openshift.com/pub/openshift-origin/nightly/fedora-${::operatingsystemrelease}/latest/${::architecture}/"
      }
      default  : {
        $install_repo_path = "https://mirror.openshift.com/pub/openshift-origin/nightly/rhel-6/latest/${::architecture}/"
      }
    }
  }
  default     : {
    $install_repo_path = $install_repo
  }
}

yumrepo { 'openshift-origin-packages':
  name     => 'openshift-origin',
  baseurl => "https://mirror.openshift.com/pub/openshift-origin/nightly/fedora-${::operatingsystemrelease}/latest/${::architecture}/",
  enabled  => 1,
  gpgcheck => 0,
}
