# origin-setup

Tools to help setup an OpenShift Origin service on EC2 (and elsewhere)

These are a set of Thor scripts and several file templates which,
together can be used to create the basis for an OpenShift Origin
service in EC2 (and elsewhere)

The Thor scripts proper are stored in the [tasks](tasks) subdirectory.

Eventually these may be made into separate callable scripts, but for now they are invoked from
inside the origin-setup directory

# Requirements

The thor scripts require these RPMs on Fedora:

* rubygems
* rubygem-thor
* rubygem-parseconfig
* rubygem-aws-sdk
* rubygem-net-ssh
* rubygem-net-scp (worked around on RHEL)

# Download and Usage

The Thor scripts proper are stored in the [tasks](tasks) subdirectory.

Eventually these may be made into separate callable scripts, but for now they are invoked from
inside the origin-setup directory.  Clone the github repository to try it out.

<pre>
git clone https://github.com/markllama/origin-setup
cd origin-setup
thor list
... lots of tasks ...
</pre>

To list tasks in the _remote_ namespace:

<pre>
thor list remote
... fewer tasks ...
</pre>

To get help for a specific task:

> thor help remote:

The tasks are broken down into a number of _namespaces_ which group related tasks.

* build - tasks for building the Origin packages
* devenv - tasks for creating a development/testing environment
* ec2 - tasks for managing AWS EC2 resources
* origin - high level tasks for installing OpenShift Origin on remote hosts controlled over SSH
* puppet - tasks for configuring and managing puppet on remote hosts
* release - tasks for managing release and versioning of OpenShift Origin packages
* remote - low level tasks for performing operations on remote hosts over SSH
* route53 - tasks for managing AWS Route53 dynamic DNS services.

Additional groups of tasks will be added to manage new resources.

More complex tasks are composed of more primative ones. Each task prints its invokation line as
it is executed so that if it fails, it can be re-run and diagnosed.

# Task Groups (namespaces)

Thor groups sets of related tasks by _namespace_.  Each namespace is
composed of one or more strings delimited by a colon (:).  Namespaces
are hierarchical.  For example, to install the _git_ package using YUM on a
remote host, you would invoke the task named `remote:yum:install` like
this.

> thor remote:yum install myhost.example.com git

Each of the groups of tasks is described briefly below.  To see the
exact invocation syntax and help text, use `thor list <namespace>` to
see the list of available tasks and `thor help <namespace>` to view
the task description. For example: 

* List tasks in namespace

<pre>
thor list remote:yum
remote
------
thor remote:yum:exclude HOSTNAME REPO PATTERN  # exclude a package pattern fr...
thor remote:yum:install HOSTNAME RPMNAME       # install an RPM on the remote...
thor remote:yum:list HOSTNAME                  # list RPMs on the remote system
thor remote:yum:remove HOSTNAME RPMNAME        # remove an RPM on the remote ...
thor remote:yum:update HOSTNAME                # update RPMs on the remote sy...
</pre>

* Describe a task

<pre>
thor help remote:yum:install
Usage:
thor remote:yum:install HOSTNAME RPMNAME

Options:
[--verbose]                    
[--username=USERNAME]          
[--ssh-key-file=SSH_KEY_FILE]  
</pre>

## Build

* Status: *incomplete*

These tasks are used to build the packages for OpenShift Origin

## Devenv

* Status: *under development*

These tasks prepare a development/test environment consisting of a
self-contained all-in-one OpenShift Origin on a single remote host.

Requires a running host accessable by SSH with public key.  The remote
user must be the root user or have _sudo_ access without a password.

## EC2

* Status: *stable*

These tasks manipulate Amazon Web Services EC2 resources.  They
require AWS access key credentials.

Place AWS access key id and secret key in a file named `.awscred` in
your home directory.  You can also specify the default EC2 instance
type, SSH key pair name and remote user (root or ec2-user)

> $HOME/.awscred

<pre>
# AWS Access Informaton
AWSAccessKeyId=&lt;;your AWS access key id&gt;
AWSSecretKey=&lt;your AWS secret key&gt;
#
# EC2 SSH login information
AWSKeyPairName=&lt;your SSH key pair name&gt;
RemoteUser=ec2-user
#
# Default EC2 instance type
AWSEC2Type=t1.micro
</pre>

The AWS access key id and secret key are also required for the route53
tasks

### ec2:image

These tasks manage and report on EC2 images

### ec2:instance

These tasks create, delete and manipulate EC2 instances

### ec2:ip

These tasks manage and report on EC2 Elastic IP addresses

### ec2:securitygroup

These tasks manage and report on EC2 security groups

### ec2:snapshot

These tasks manage and report on EC2 disk snapshots

### ec2:volume

These tasks manage and report on EC2 disk volumes

## Origin

* Status: *under development*


## Puppet

* Status: *under developement*

These tasks manage puppet services on a remote host.

### puppet:agent

These tasks install, configure and manage a puppet agent on a remote host

### puppet:cert

These tasks manage certificates on a puppet master

### puppet:master

These tasks install and manage puppet master processes on a remote server.

### puppet:module

These tasks manage puppet modules on a remote host

## Release

* Status: *incomplete*

## Remote

* Status: *stable*

### remote:augeas

These tasks get or set configuration values on remote hosts using Augeas

### remote:file

These tasks copy files to and from a remote host, and move them from
place to place on the remote host.  They can also set permissions and
ownership of remote files and directories

### remote:firewall

These tasks manage the firewall rules on a remote host

### remote:git

These tasks manage git repositories on a remote host

### remote:repo

These tasks manage YUM repository configuration on a remote host

### remote:service

These tasks manage service settings on a remote host

### remote:yum

These tasks install and remove packages on a remote host using yum.

## Route53

* Status: *stable*

These tasks are used to manage DNS updates through the AWS Route53
service.

