#!/usr/bin/ruby
#
# Detect and then initialize the OpenShift database
#
require 'parseconfig'
require 'mongo'

#dbhost = "ec2-54-227-124-141.compute-1.amazonaws.com"
#dbport = "27017"

#dbadminuser = "root"
#dbadminpass = "dbadminsecret"

#dbname = "openshift"
#dbuser = "broker"
#dbpass = "dbsecret"

def db_exists(dbhost, dbport, user, pass, dbname)
  admin_uri = "mongodb://#{user}:#{pass}@#{dbhost}:#{dbport}/admin"

  conn = Mongo::Connection.from_uri(admin_uri)

  conn.database_names.member? dbname  
end

def db_create(dbhost, dbport, dbadminuser, dbadminpass, dbname, dbuser, dbpass)

  admin_uri = "mongodb://#{dbadminuser}:#{dbadminpass}@#{dbhost}:#{dbport}/admin"

  conn = Mongo::Connection.from_uri(admin_uri)

  db = conn.db(dbname)
  
  puts db

  db.add_user(dbuser, dbpass)

end


if self.to_s == 'main'


  #puts "Admin URL: #{admin_uri}"

  #if db_exists dbhost, dbport, dbadminuser, dbadminpass, dbname
  #  puts "found"
  #  exit
  #else
  #  puts "not found"
  #end

  #db_create dbhost, dbport, dbadminuser, dbadminpass, dbname, dbuser, dbpass
  
  #if db_exists dbhost, dbport, dbadminuser, dbadminpass, dbname
  #  puts "found"
  #else
  #  puts "not found"
  #end

  #conn.drop_database(dbname)

end
