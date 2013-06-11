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

SIBLING_REPOS = {
  'origin-server' => ['../origin-server'],
  'rhc' => ['../rhc'],
  'origin-dev-tools' => ['../origin-dev-tools'],
  'puppet-openshift_origin' => ['../puppet-openshift_origin'],
}
OPENSHIFT_ARCHIVE_DIR_MAP = {'rhc' => 'rhc/'}
SIBLING_REPOS_GIT_URL = {
  'origin-server' => 'https://github.com/openshift/origin-server.git',
  'rhc' => 'https://github.com/openshift/rhc.git',
  'origin-dev-tools' => 'https://github.com/openshift/origin-dev-tools.git',
  'puppet-openshift_origin' => 'https://github.com/openshift/puppet-openshift_or
igin.git'
}

DEV_TOOLS_REPO = 'origin-dev-tools'
DEV_TOOLS_EXT_REPO = DEV_TOOLS_REPO
ADDTL_SIBLING_REPOS = SIBLING_REPOS_GIT_URL.keys - [DEV_TOOLS_REPO]



class Devenv < Thor

  class_option :verbose, :type => :boolean, :default => false
  class_option :debug, :type => :boolean, :default => false

  desc("task: build NAME BUILDNUM",
    "create a new devenv image from a base image")
  # name, build_num, image, conn, options
  method_option :image, :type => :string
  method_option(:update, :type => :string, 
    :desc => "update an existing devenv")
  method_option(:baseos, :type => :string)
  method_option(:branch, :type => :string)

  def build(name, build_num)
    puts "devenv:build #{name} #{build_num}"

    # enable logging/debugging
    options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

    config = OpenShift::AWS.config

    handle = AWS::EC2.new

    # Select the image to use as a base
    if options[:image]
      # The caller provided an image id
      image = handle.images[options[:image]]
      raise Exception.new("invalid image ID #{options[:image]}: not found") unless image
      puts "- image found - image id: #{image.id}"
    else
      # use the current OS unless told explicitly
      baseos = options[:baseos] || guess_os
      # TODO: validate baseos
      puts "- baseos: #{baseos}" unless options[:quiet]


      # determine the baseos ?

      # select an image to use as the base
      if options[:update]
        puts "looking for image matching #{options[:update]}"
        # find an image with a matching name
      else
        image_id  = config[baseos]['BaseOSImage']
        puts "- image selected - image id: #{image_id}"
        # use the base image from configuration
      end
    end
    
  end

  # additional methods for build
  no_tasks do

  end

  desc "install INSTANCE", "install a devenv on a running instance"
  def install(instance_id)
    
  end


  desc "launch NAME", "create a new instance with the given name"
  method_option :image
  method_option :baseos
  method_option :keypair
  method_option :type, :default => "m1.large"
  method_option :securitygroup, :type => :array, :default => ['devenv']
  def launch(name)
    puts "task: devenv:launch #{name}" unless options.quiet?

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
      baseos = options[:baseos] || guess_os
      # TODO: validate baseos
      puts "- baseos: #{baseos}" unless options[:quiet]

      image_id  = config[baseos]['BaseOSImage']
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
      puts "- #{instance.id} '#{instance.status}' waiting..." if options[:verbose]
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

  desc "image BASEOS OSVERSION", "report the existing devenv image for the OS and version"
  method_option :osname, :type => :string
  method_option :osversion, :type => :string
  method_option :branch, :type => :string
  def image
    puts "task: devenv:image"

    # enable logging/debugging
    options.verbose? ? log.level = Logger::DEBUG : log.level = Logger::ERROR

    config = OpenShift::AWS.config
    handle = AWS::EC2.new

    
  end

  no_tasks do
    # determine which distribution family we're running on
    def guess_os
      raise Exception.new("Unable to get base OS: no release file") unless File.exist?("/etc/redhat-release")
      data = File.read("/etc/redhat-release").strip
      parts = data.match(/^(.*)\srelease\s+((\d+)(\.(\d+))?)\s+/)
      return nil if parts == nil
      return "fedora" + parts[2] if parts[1] == "Fedora"
      return "rhel" + parts[2] if parts[1] == "Red Hat Enterprise Linux Server"
      return "centos" + parts[2] if data.match(/centos/)
      raise Exception.new("Unable to get base OS from release file")
    end
   
  end

end
