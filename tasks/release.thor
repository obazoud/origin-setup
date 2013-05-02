#!/usr/bin/env ruby
# Present tasks to manage AWS EC2 images and instances
#
require 'rubygems'
require 'thor'

class Release < Thor

  desc "tag", "tag the current software for release"
  def tag

  end

  desc "build", "build the software packages for release"
  def build

  end

end
