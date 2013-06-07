#!/usr/bin/env ruby
# Present tasks to manage AWS EC2 images and instances
#
require 'rubygems'
require 'thor'
require 'aws'

module EC2

  class Elasticip < Thor

    namespace "ec2:ip"

    class_option :verbose, :type => :boolean, :default => false

    desc "list", "list the defined elastic IPs"
    def list
      puts "task: ec2:ip:list" unless options[:quiet]
      handle = AWS::EC2.new
      ips = handle.elastic_ips

      ips.each { |ip|
        puts "#{ip.ip_address} instance: #{ip.instance_id}"
      }
    end

    desc "create", "create a new elastic IP"
    def create
      puts "task: ec2:ip:create" unless options[:quiet]
      handle = AWS::EC2.new
      ips = handle.elastic_ips
      ip = ips.create
      puts ip
      ip
    end


    desc "delete IPADDR", "delete an elastic IP"
    def delete(ipaddr)
      puts "task: ec2:ip:delete #{ipaddr}" unless options[:quiet]
      handle = AWS::EC2.new
      ips = handle.elastic_ips
      ips.select { |ip|
        ip.ip_address == ipaddr
      }.each { |ip|
        ip.delete
      }
    end

    desc "associate IPADDR INSTANCE", "associate and Elastic IP with an instance"
    def associate(ipaddr, instanceid)
      puts "task: ec2:ip:associate #{ipaddr} #{instanceid}" unless options[:quiet]
      handle = AWS::EC2.new

      # validate the IP addr and instance id?

      ips = handle.elastic_ips
      ips.select { |ip|
        ip.ip_address == ipaddr
      }.each { |ip|
        ip.associate :instance => instanceid
      }
    end

    desc "disassociate IPADDR INSTANCE", "associate and Elastic IP with an instance"
    def disassociate(ipaddr)
      puts "task: ec2:ip:disassociate #{ipaddr}" unless options[:quiet]
      handle = AWS::EC2.new

      # validate the IP addr and instance id?

      ips = handle.elastic_ips
      ips.select { |ip|
        ip.ip_address == ipaddr
      }.each { |ip|
        ip.disassociate
      }
    end

    desc "info IPADDR", "get information for an IP address"
    def info(ipaddr)
      puts "task: ec2:ip:info #{ipaddr}" unless options[:quiet]
      handle = AWS::EC2.new

      # validate the IP addr and instance id?

      ips = handle.elastic_ips
      begin
        ip = ips[ipaddr]
        puts "- IP address: #{ip.ip_address} instance: #{ip.instance_id}"
      rescue AWS::EC2::Errors::InvalidAddress::NotFound
        puts "- IP address: #{ipaddr} not found"
        ip = nil
      end
      ip
    end
  end

end
