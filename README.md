# origin-setup

Tools to help setup an OpenShift Origin service on EC2 (and elsewhere)

These are a set of Thor scripts and several file templates which,
together can be used to create the basis for an OpenShift Origin
service in EC2 (and elsewhere)

The Thor scripts proper are stored in the [tasks](tasks) subdirectory.

Eventually these may be made into separate callable scripts, but for now they are invoked from
inside the origin-setup directory

# Download and Usage

The Thor scripts proper are stored in the [tasks](tasks) subdirectory.

Eventually these may be made into separate callable scripts, but for now they are invoked from
inside the origin-setup directory.  Clone the github repository to try it out.

> git clone https://github.com/markllama/origin-setup
> cd origin-setup
> thor list
> ... lots of tasks ...

To list tasks in the _remote_ namespace:

> thor list remote
> ... fewer tasks ...

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

- List tasks in namespace
> thor list remote:yum
> remote
> ------
> thor remote:yum:exclude HOSTNAME REPO PATTERN  # exclude a package pattern fr...
> thor remote:yum:install HOSTNAME RPMNAME       # install an RPM on the remote...
> thor remote:yum:list HOSTNAME                  # list RPMs on the remote system
> thor remote:yum:remove HOSTNAME RPMNAME        # remove an RPM on the remote ...
> thor remote:yum:update HOSTNAME                # update RPMs on the remote sy...

- Describe a task
> thor help remote:yum:install
> Usage:
>   thor remote:yum:install HOSTNAME RPMNAME
>
> Options:
>   [--verbose]                    
>   [--username=USERNAME]          
>   [--ssh-key-file=SSH_KEY_FILE]  

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

- $HOME/.awscred
> # AWS Access Informaton
> AWSAccessKeyId=<your AWS access key id>
> AWSSecretKey=<your AWS secret key>
> #
> # EC2 SSH login information
> AWSKeyPairName=<your SSH key pair name>
> RemoteUser=ec2-user
> #
> # Default EC2 instance type
> AWSEC2Type=t1.micro

The AWS access key id and secret key are also required for the route53
tasks

### ec2:image

### ec2:instance

### ec2:ip

### ec2:securitygroup

### ec2:snapshot

### ec2:volume

## Origin

* Status: *under development*


## Puppet

### puppet:agent

### puppet:cert

### puppet:master

### puppet:module

## Release

* Status: *incomplete*

## Remote

* Status: *stable*

### remote:augeas

### remote:file

### remote:firewall

### remote:git

### remote:repo

### remote:service

### remote:yum

## Route53

* Status: *stable*
These tasks are used to manage DNS updates through the AWS Route53
service.

