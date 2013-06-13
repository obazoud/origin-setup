#!/usr/bin/ruby
#
require 'rubygems'
require 'thor'
require 'thor/actions'

require 'logger'
# Force synchronous stdout
STDOUT.sync, STDERR.sync = true

# Setup logger
@@log = Logger.new(STDOUT)
@@log.level = Logger::DEBUG

def log
  @@log
end

class Devenv < Thor

  class_option :verbose, :type => :boolean, :default => false

  class EC2 < Thor

    namespace "devenv:ec2"

    class_option :verbose, :type => :boolean, :default => false

    desc "image OSNAME OSVERSION", "report the existing devenv image for the OS and version"
    #  method_option :osname, :type => :string
    #  method_option :osversion, :type => :string
    method_option :owner, :default => :self
    method_option :branch, :type => :string
    method_option :base, :type => :boolean, :default => false
    def find_image(osname, osversion)
      puts "task: devenv:ec2:find_image"

      # enable logging/debugging
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

      config = OpenShift::AWS.config
      handle = AWS::EC2.new

      images = handle.images
      images = images.with_owner(options[:owner]) if options[:owner]
      images = images.tagged('osname').tagged_values(osname).
        tagged('osversion').tagged_values(osversion).
        tagged('devenv').tagged_values(options[:base] ? 'base' : 'latest')

      images = images.tagged('branch').tagged_values(options[:branch]) if options[:branch]

      images.each {|i|
        puts "#{i.id}"
      }

      images
    end

    desc "launch NAME", "create a new instance with the given name"
    method_option :image
    method_option :baseos
    method_option :keypair
    method_option :type, :default => "m1.large"
    method_option :securitygroup, :type => :array, :default => ['devenv']
    def launch(name)
      puts "task: devenv:ec2:launch #{name}" unless options.quiet?

      config = OpenShift::AWS.config

      # enable logging/debugging
      options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

      #----------------
      # Select an image
      #----------------
      #
      # if we have an image, create an instance, start it and learn the OS
      image_id = options[:image]
      if not image_id
        # use the current OS unless told explicitly
        osname, osversion = options[:baseos] || guess_os
        # TODO: validate baseos
        puts "- baseos: #{osname}" unless options[:quiet]

        image_id  = config[osname + osversion]['BaseOSImage']
      end
      # TODO: validate image_id
      puts "- image id: #{image_id}" unless options[:quiet]

      keypair = options[:keypair] || config['AWSKeyPairName']

      # select the instance type
      type = options[:type] || config['AWSEC2Type']

      instance = invoke("ec2:instance:create", [], 
        :name => name,
        :image => image_id,
        :key => config['AWSKeyPairName'],
        :type => type,
        :securitygroup => options[:securitygroup],
        :verbose => options[:verbose]
        )
    
      # monitor startup process: wait until running
      (1..20).each do |trynum|
        break if instance.status.to_s === 'running'
        puts "{instance.id} '#{instance.status}' waiting..." if options[:verbose]
        sleep 15
      end
      raise Exception.new "Instance failed to start" if not instance.status.to_s === 'running'
      puts "- instance #{instance.id} running" unless options[:quiet]

      # update facts - noop MAL 20130610

      # post launch
      # - puppet configure hostname
      # - puppet configure origin
      # - restart services ??
      #services = [ 'mongod', 'mcollective', 'activemq', 'cgconfig', 'cgred', 
      #  'openshift-cgroups', 'httpd', 'openshift-broker', 'openshift-console', 
      #  'openshift-node-web-proxy', 'named', 'sshd', 'oddjobd' ]

      # setup verifier (if options[:verifier])
      # - update remote tests hostname, branch, /data
      # -- update remote git repos

      # ssh_config_verifier?
      # - update api_file - console configuration    #   
      # - update ssh_config_verifier

      # update express server - libra.conf

      # prime remote home (from ~/.openshiftdev/home.d)

      puts "Public IP:       #{instance.public_ip_address}"
      puts "Public Hostname: #{instance.dns_name}"
      puts "Site URL:        https://#{instance.dns_name}"
      puts "Done"

    end

    desc "build NAME BUILD_NUM", "build a development host on EC2"
    def build(name, buildnum)
      # find the base image

      # launch an instance from the base instance

    end

  end

  desc "prepare HOSTNAME", "prepare a host for installing a devenv all-in-one"
  def prepare(hostname)
    puts "devenv:prepare #{hostname}"

    username = options[:username] || Remote.ssh_username
    key_file = options[:ssh_key_file] || Remote.ssh_key_file

    # check the os and version
    osname, osversion = invoke "remote:distribution", [hostname]
    arch = invoke "remote:arch", [hostname]

    # install augeas, used later
    Remote::Yum.install_rpms(hostname, username, key_file, ['augeas'], 
      options[:verbose])


    # disable updates-testing repo.  It has three parts.  Use Augeas for each
    ['updates-testing', 
      'updates-testing-debuginfo', 
      'updates-testing-source'].
      each { | reponame |
      Remote::Augeas.set(hostname, username, key_file, 
        "/files/etc/yum.repos.d/fedora-updates-testing.repo/#{reponame}/enabled",
        '0', 
        options[:verbose])      
    }

    # yum update
    invoke "remote:yum:update", [hostname]

    # install puppet repos (rhel/centos)
    if osname == 'rhel' or osname == 'centos'
      # install/update epel-release (rhel/centos)
      Remote::Yum.remove_rpms(hostname, username, key_file, ['epel-release'],
        options['verbose'])

      # should get the '6' from OS version
      epel_release = "6-8"
      epel_url =  "http://dl.fedoraproject.org/pub/epel/6/" +
        "#{arch}/epel-release-#{epel_release}.noarch.rpm"
      Remote::Yum.install_rpms(hostname, username, key_file, [epel_url],
        options[:verbose])

      # install the puppetlabs repo file - not in EPEL or RHEL
      invoke("remote:repo:create", 
        [hostname, 'puppetlabs', 'data/puppetlabs.repo'])
    end

  end


  no_tasks do
    # determine which distribution family we're running on
    def guess_os
      raise Exception.new("Unable to get base OS: no release file") unless File.exist?("/etc/redhat-release")
      data = File.read("/etc/redhat-release").strip
      parts = data.match(/^(.*)\srelease\s+((\d+)(\.(\d+))?)\s+/)
      return nil if parts == nil
      osname = "fedora" if parts[1] == "Fedora"
      osname = "rhel" if parts[1] == "Red Hat Enterprise Linux Server"
      osname = "centos" if data.downcase.match(/centos/) #
      raise Exception.new("Unable to get base OS from release file") if defined? osname

      osversion = parts[2]
      return osname, osversion
    end
   
  end

end
