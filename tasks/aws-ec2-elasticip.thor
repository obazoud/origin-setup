#!/usr/bin/env ruby
# Present tasks to manage AWS EC2 images and instances
#
require 'rubygems'
require 'thor'
require 'aws'
require 'parseconfig'

module OpenShift

  class Elasticip < Thor

    namespace "ec2:ip"

    class_option :verbose, :type => :boolean, :default => false

    desc "list", "list the defined elastic IPs"
    def list
      puts "task: ec2:ip:list" unless options[:quiet]
      handle = login
      ips = handle.elastic_ips

      ips.each { |ip|
        puts "#{ip.ip_address} instance: #{ip.instance_id}"
      }
    end

    desc "create", "create a new elastic IP"
    def create
      puts "task: ec2:ip:create" unless options[:quiet]
      handle = login
      ips = handle.elastic_ips
      ip = ips.create
      puts ip
      ip
    end


    desc "delete IPADDR", "delete an elastic IP"
    def delete(ipaddr)
      puts "task: ec2:ip:delete #{ipaddr}" unless options[:quiet]
      handle = login
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
      handle = login

      # validate the IP addr and instance id?

      ips = handle.elastic_ips
      ips.select { |ip|
        ip.ip_address == ipaddr
      }.each { |ip|
        ip.associate :instance => instanceid
      }
    end

    desc "associate IPADDR INSTANCE", "associate and Elastic IP with an instance"
    def disassociate(ipaddr)
      puts "task: ec2:ip:disassociate #{ipaddr}" unless options[:quiet]
      handle = login

      # validate the IP addr and instance id?

      ips = handle.elastic_ips
      ips.select { |ip|
        ip.ip_address == ipaddr
      }.each { |ip|
        ip.disassociate
      }
    end

    no_tasks do
      
      # Create an EC2 connection
      def login(access_key_id=nil, secret_access_key=nil, credentials_file=nil, 
          region=nil)
        # explicit credentials take precedence over a file
        if not (access_key_id and secret_access_key) then
          credentials_file ||= AWS_CREDENTIALS_FILE
          config = ParseConfig.new File.expand_path(credentials_file)
          
          access_key_id = config.params['AWSAccessKeyId']
          secret_key = config.params['AWSSecretKey']

          # check them
        end

        connection = AWS::EC2.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_key
          )
        region ? connection.regions[region] : connection
      end
      
    end
  end

end
