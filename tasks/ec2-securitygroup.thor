#!/usr/bin/env ruby
#
# Set up an OpenShift Origin service on AWS EC2
#
require 'rubygems'
require 'parseconfig'
require 'aws'
require 'thor'

module Openshift

  class Securitygroup < Thor

    namespace "ec2:securitygroup"

    class_option :verbose, :type => :boolean, :default => false

    AWS_CREDENTIALS_FILE = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"

    desc "list", "list the available snapshots"
    def list
      handle = AWS::EC2.new
      
      securitygroups = handle.security_groups
      securitygroups.each { |securitygroup|
        puts "#{securitygroup.id}: #{securitygroup.name}, #{securitygroup.description}"
        if options[:verbose]
          securitygroup.ingress_ip_permissions.each { |perm|
            puts "  in rule: #{perm.ip_ranges} #{perm.port_range} #{perm.protocol}"
          }

          securitygroup.egress_ip_permissions.each { |perm|
            puts " out rule: #{perm.ip_ranges} #{perm.port_range} #{perm.protocol}"
          }
        end
      }
    end

    desc "create NAME", "create a new securitygroup"
    method_option :description, :type => :string # required?
    def create(name)
      handle = AWS::EC2.new
      sgroups = handle.security_groups
      sgroup = sgroups.create(name, :description => options[:description])
      puts sgroup.id
      sgroup
    end

    desc "delete", "delete the securitygroup"
    method_option :id, :type => :string
    method_option :name, :type => :string
    def delete(group_id)
      puts "task: ec2:securitygroup:delete #{group_id}" unless options[:quiet]

      sgroup = Securitygroup.get(options[:id], options[:name])
      sgroup.delete
    end


    desc "info", "retrieve and report on a securitygroup"
    method_option :id, :type => :string
    method_option :name, :type => :string
    def info
      puts "task: ec2:securitygroup:info" unless options[:quiet]

      sgroup = Securitygroup.get(options[:id], options[:name])

      puts "#{sgroup.id}: #{sgroup.name}, #{sgroup.description}"
        if options[:verbose]
          sgroup.ingress_ip_permissions.each { |perm|
            puts "  in rule: #{perm.ip_ranges} #{perm.port_range} #{perm.protocol}"
          }

          sgroup.egress_ip_permissions.each { |perm|
            puts " out rule: #{perm.ip_ranges} #{perm.port_range} #{perm.protocol}"
          }
        end
      sgroup
    end

    no_tasks do
      
      # retrieve a single securitygroup by name or id
      def self.get(id=nil, name=nil)
        handle = AWS::EC2.new      
        securitygroups = handle.security_groups
        # ask?
        if id
          sgroup = securitygroups[id]
        elsif name
          sgroup_list = securitygroups.select {|sg|
            sg.name.match name
          }
          if sgroup_list.count != 1
            raise ArgumentError.new(
              "no matching security group '#{name}'")
          end
          sgroup = sgroup_list[0]
        else
          raise ArgumentError.new "either id or name is required"
        end
        sgroup
      end

    end

    class Rule < Thor
      namespace "ec2:securitygroup:rule"

      desc("add PROTOCOL PORTS [SOURCES]",
        "add a permission rule to a security group")
      method_option :id, :type => :string
      method_option :name, :type => :string
      method_option :egress, :type => :boolean, :default => false
      def add(protocol, ports, *sources)
        puts "task: ec2:securitygroup:rule:add #{protocol} #{ports} #{sources.join(' ')}"

        # get the sgroup with the given ID
        sgroup = Securitygroup.get(options[:id], options[:name])

        # check that the protocol is valid
        proto_sym = protocol.downcase.to_sym
        if not [:tcp, :udp, :icmp].member? proto_sym
          raise ArgumentError.new "invalid protocol: #{protocol}"
        end

        # validate the ports
        port_list = ports.split('..')
        # check for split out of range
        portrange = port_list[0].to_i if port_list.count == 1
        portrange = Range.new(*port_list.map{|s|s.to_i}) if port_list.count == 2
        
        # validate the sources

        # add the rule to the sgroup
        sgroup.authorize_ingress proto_sym, portrange, *sources

      end

    end
  end
end