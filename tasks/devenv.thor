#!/usr/bin/ruby
#
require 'rubygems'
require 'thor'
require 'thor/actions'

class Devenv < Thor

  class_option :verbose, :type => :boolean, :default => false
  class_option :debug, :type => :boolean, :default => false

  desc "launch NAME", "create a new instance with the given name"
  def launch(name)

    # enable logging/debugging

    # select the base OS

    # select an image

    # select the instance type

    invoke("ec2:instance:create", [], 
      :name => name,
      :image => image_id,
      :type => instance_type
      )
    
    # update facts

    # post launch

    # verify
 
    # update api ?

    # update ssh_config

    puts "Public IP:       #{instance.public_ip_address}"
    puts "Public Hostname: #{hostname}"
    puts "Site URL:        https://#{hostname}"
    puts "Done"

  end

end
