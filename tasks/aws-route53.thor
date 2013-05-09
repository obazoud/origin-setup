#!/usr/bin/env ruby
#
#
require 'rubygems'
require 'thor'
require 'aws'
require 'parseconfig'

module OpenShift
  class Route53 < Thor
    namespace "route53"
    
    class_option :verbose, :type => :boolean, :default => false

    AWS_CREDENTIALS_FILE = ENV["AWS_CREDENTIALS_FILE"] || "~/.awscred"

    desc "zones", "list hosted zones"
    def zones

      puts "task: route53:zone" unless options[:quiet]
      handle = Route53.login

      response = handle.list_hosted_zones
      zones = response[:hosted_zones]
      zones.each { |zone|
        puts "id: #{zone[:id].split('/')[2]} name: #{zone[:name]} records: #{zone[:resource_record_set_count]}"
      }
    end

    desc "records", "return records for a zone"
    method_option :id, :type => :string
    method_option :zone, :type => :string
    def records
      puts "task: route53:records"

      handle = Route53.login

      if options[:zone]
        zoneid = Route53.zone_id(handle, options[:zone])
      else
        zoneid = options[:id]
      end

      response = handle.list_resource_record_sets(
        :hosted_zone_id => "/hostedzone/#{zoneid}")

      response.data[:resource_record_sets].each { |rrset|
        name = rrset[:name]
        type = rrset[:type]
        values = rrset[:resource_records]
        puts "#{rrset[:name]} #{rrset[:type]}"
        values.each { |rvalue|
          puts "  #{rvalue[:value]}"
        }
      }

    end

    desc "zoneid ZONE", "return the zone id of a name"
    def zoneid(zonename)
      puts "task route53:zoneid #{zonename}" unless options[:quiet]

      handle = Route53.login

      id = Route53.zone_id(handle, zonename)
      puts "id = " + id
    end

    class Record < Thor
      namespace "route53:record"

      desc("list ZONE [TYPE]",
        "create a new resource record")
      def list(zonename, type=nil)
        puts "task: route53:record:list #{zonename}"

        handle = Route53.login

        zoneid = Route53.zone_id(handle, zonename)
        puts "looking for zone id #{zoneid}"

        opts = {:hosted_zone_id => "/hostedzone/#{zoneid}"}

        response = handle.list_resource_record_sets(opts)

        response.data[:resource_record_sets].each { |rrset|
          name = rrset[:name]
          rrtype = rrset[:type]
          if type === nil or rrtype === type.upcase
            values = rrset[:resource_records]
            puts "#{rrset[:name]} #{rrtype}"
            values.each { |rvalue|
              puts "  #{rvalue[:value]}"
            }
          end
        }
        
      end
      
      desc("create ZONE NAME TYPE VALUE",
        "create a new resource record")
      def create(zone, type, name, value)

      end

      desc("delete ZONE NAME [TYPE [VALUE]]",
        "delete a resource record")
      def delete(zone, name, type=nil, value=nil)

      end


    end

    no_tasks do
      # Create a Route53 connection
      def self.login(access_key_id=nil, secret_access_key=nil,
          credentials_file=nil, region=nil)
        # explicit credentials take precedence over a file
        if not (access_key_id and secret_access_key) then
          credentials_file ||= AWS_CREDENTIALS_FILE
          config = ParseConfig.new File.expand_path(credentials_file)
          access_key_id = config.params['AWSAccessKeyId']
          secret_key = config.params['AWSSecretKey']

          # check them
        end

        connection = AWS::Route53.new(
          :access_key_id => access_key_id,
          :secret_access_key => secret_key
          ).client
      end

      def self.zone_id(handle, zonename)
        # allow non-canonical zone names
        zonename += "." if not zonename.end_with? "."
        response = handle.list_hosted_zones
        zones = response[:hosted_zones]
        zones.select! { |zone|
          zone[:name] == zonename
        }
        zones[0][:id].split('/')[2]
      end 
    end
  end
end
