#!/usr/bin/env ruby
#
require 'rubygems'
require 'thor'
require 'aws'

module EC2
  # Manage Amazon Web Services EC2 instances and images

  class Image < Thor
    namespace "ec2:image"

    class_option :verbose, :type => :boolean, :default => false

    desc "list", "list the available images for new instances"
    method_option(:name, :type => :string, :default => "*")
    method_option(:location, :type => :string, :default => "*")
    method_option(:owner, :default => :self)
    method_option(:arch, :type => :string, :default => "*")
    def list
      handle = AWS::EC2.new
      images = handle.images.filter('state', 'available')
      images = images.with_owner(options[:owner]) if options[:owner]
      images = images.filter('architecture', options[:arch]) if options[:arch]
      images = images.filter('name', options[:name]) if options[:name]

      images.each do |i|
        if options[:verbose] then
          puts "#{i.id}, #{i.name}: #{i.architecture}, #{i.platform}" +
            "#{i.block_device_mappings.to_a}, #{i.state}" +
            "\n   #{i.owner_id} '#{i.owner_alias}'"
        else
          puts "#{i.id} #{i.owner_id} #{i.architecture} #{i.name} #{i.platform}"
        end
      end
    end
    
    desc "info", "retrieve information about a specified image"
    method_option(:id, :type => :string)
    method_option(:name, :type => :string)
    method_option(:tag_key, :type => :string)
    method_option(:tag_value, :type => :string)
    def info

      if not options[:id] || options[:name] then
        puts "No values provided for either --name or --id"
        return
      end

      handle = AWS::EC2.new
      image = handle.images[options[:id]]

      if not image
        puts "no matching image"
        return
      end

      if options[:verbose] then
        puts "Image: #{image.id} (#{image.name})"
        puts "  Description: #{image.description}"
        puts "  State: #{image.state}"
        puts "  Type: #{image.type}"
        puts "  Owner: #{image.owner_id} (#{image.owner_alias})"
        puts "  Location: #{image.location}"
        puts "  Platform: #{image.platform}"
        image.block_device_mappings.each {| devname, devhash |
          puts "  Device: #{devname}"
          devhash.each { | param, value |
            puts "    #{param}: #{value}"
          }
        }
        puts "  Tags: #{image.tags.to_a}"
      else
        puts "#{image.id} #{image.name} #{image.state}"
      end

    end

    desc "tag", "set or retrieve information about a specified image"
    method_option(:id, :type => :string)
    method_option(:name, :type => :string)
    method_option(:tag, :type => :string, :required => true)
    method_option(:value, :type => :string)
    def tag

      if not options[:id] || options[:name] then
        puts "No values provided for either --name or --id"
        return
      end

      handle = AWS::EC2.new
      image = find_image(login, options)

      if not image
        puts "no matching image"
        return
      end

      # set a value if it is given
      if options[:value] then
        image.add_tag(options[:tag], { :value => options[:value] })
      else
        value = options[:tag]
        puts "#{options[:tag]}: #{value}"
        return value
      end
    end

    desc "create INSTANCE NAME", "Create a new image from an existing configured instance"
    method_option :description, :type => :string, :default => ""
    method_option :wait, :type => :boolean, :default => false
    def create(instance, name)

      handle = AWS::EC2.new

      # if the instance is a string, get the instance from AWS
      if instance.class == String and instance.match(/^i-/)
        instance_id = instance
      else
        instance_id = instance.id
      end

      puts "task: ec2:image create #{instance_id} #{name}"

      newimage = handle.images.create(
        :instance_id => instance_id,
        :name => name,
        :description => options[:description]
        )

      puts "  new image_id: #{newimage.id}" if options[:verbose]
      if options[:wait]
        maxtries = 10
        poll_interval = 30
        (1..maxtries).each do |trynum|
          break if newimage.state == :available
          puts "  #{trynum}) #{newimage.state}: sleeping #{poll_interval} seconds" if options[:verbose]
          sleep poll_interval
        end
        if not newimage.state == :available
          raise Exception.new("image #{image.id} is not ready after " +
            "#{maxtries * poll_interval} seconds: #{newimage.state}.")
        end
      end # wait
      puts "image_id: #{newimage.id} #{newimage.name} #{newimage.state}"
      newimage
    end

    desc "delete", "Delete an existing instance"
    method_option :id, :type => :string, :default => nil
    method_option :name, :type => :string
    def delete
      handle = AWS::EC2.new
      
      # find one image that matches either the image or name
      if options[:id] then
        puts "going to delete image #{options[:id]}"
        image = handle.images[options[:id]]
      else
        puts "trying to find a match of #{options[:name]}"
        matches = handle.images.with_owner(:self).
          filter('tag-key', 'Name').filter('tag-value', options[:name])
        if matches.count === 0 then
          raise ArgumentError.new("no matching image: #{options[:name]}")
        elsif matches.count > 1 then
          raise ArgumentError.new("#{options[:name]} matches #{matches.count} images")
        else
          image = matches.to_a[0]
        end
      end
      puts "deleting image #{image.id} #{image.name}"
      image.delete
    end

    desc "find TAGNAME", "find the id of images with a given tag"
    method_option(:tagvalue)
    def find(tagname)
      handle = AWS::EC2.new

      if options[:tagvalue]
        images = handle.images.with_owner(:self).
          filter('tag-key', tagname).filter('tag-value', options[:tagvalue])
      else
        images = handle.images.with_owner(:self).filter('tag-key', tagname)
      end

      puts "there are #{images.count} images with tag #{tagname}"

      images.each do |image|
        puts "#{image.id} #{image.name} #{tagname}='#{image.tags[tagname]}'"
      end
    end
    

    private

    no_tasks do
      # Find a single instance given an ID or name
      def find_image(connection, options)
      
        if options[:id] then
          image = connection.images[options[:id]]
          raise ArgumentError.new("id #{options[:id]}: no matches") if not image
          return image
        end

        images = connection.images.with_owner(:self).
          filter("name", options[:name])
        
        if images.count === 0 then
          raise ArgumentError.new(
            "name #{options[:name]}: no matches")
        elsif
          images.count > 1 then
          raise ArgumentError.new(
            "name #{options[:name]} matches #{images.count} images")
        end

        # get the first element of an iterator
        images.to_a[0]
      end
    end
  end
end

if self.to_s === "main" then
  EC2::Image.start()
end
