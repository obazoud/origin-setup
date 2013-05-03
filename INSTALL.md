These tasks are written using the [Thor rubygem](https://rubygems.org/gems/thor)

The tasks defined here require a number of additional gems

* rubygem-thor
* rubygem-aws-sdk
* rubygem-parseconfig
* rubygem-net-ssh (in Origin mirror)
* rubygem-net-scp (optional)

# Adding the OpenShift Extras YUM repository

On Fedora 18+ all of the gems are readily available as RPM packages.  For RHEL6 or CentOS6 you will need to get 
the ``net/ssh`` gem either from the OpenShift extras repo at mirrors.openshift.com or as a gem from *rubygems.org*.

On RHEL6 and CentOS6 you'll need to get the Ruby 1.9.3 packages so that all of the tools will run.  These packages
are also in the [OpenShift Extras](https://mirror.openshift.com/origin-server/rhel-6) repository for your architecture
(i386 or x86_64).  Add the _origin-extras_ repo file to your system:

* ```/etc/yum.repos.d/origin-extras.repo```

    [origin-extras]
    name=OpenShift Origin Extra Packages
    baseurl=https://mirror.openshift.com/origin-server/<distro>-<version>/$basearch
    enable=1
    gpgcheck=0

Replace _<distro>_ with either <underscore>fedora</underscore> or <underscore>rhel</underscore> (for both RHEL6 and CentOS6).
Replace the _<version>_ with the distrubution with the major number (18,19 for Fedora, 6 for RHEL and CentOS).

# Package Installation

## Fedora

Installing the requirements on Fedora is pretty easy.

    sudo yum install rubygem-thor rubygem-parseconfig rubygem-aws-sdk rubygem-net-ssh rubygem-net-scp

Examine the list of packages and dependencies to install and say _yes_ if you don't see anything you don't want.

## RHEL or CentOS

A number of the components only run on Ruby 1.9.3.  Since RHEL6 and CentOS6 have ruby 1.8.7 this is a problem.
The scl-utils package (and the related ruby193 packages built to run in it) solves the problem. All of the ruby packages
which run under SCL are prefaced with _ruby193-_.  The dependencies are set up properly, so installing the right packages
is a matter of installing the ruby193 versions of the packages listed for Fedora and letting YUM do the work.

    sudo yum install ruby193-rubygem-thor ruby193-rubygem-parseconfig ruby193-rubygem-aws-sdk \
    ruby193-rubygem-net-ssh

Again, examine the package list and say _yes_ if you approve.

Once the packages are installed you will want to run in the ruby 1.9.3 environment.

    scl ruby193 enable bash
    ruby --version
    ruby 1.9.3p327 (2012-11-10 revision 37606) [x86_64-linux]

# Configuration

These tasks aim to make managing the components of a development and test environment easier. There are a number of variables normally required to access and manage EC2 instances and hosts via SSH that are used repeatedly. These values can be placed in a configuration file so that they do not need to be re-entered for each command.  Options are provided to allow the values to be overridden as needed.

The default location for the configuration is in ```$HOME/.awscred```

## AWS REST interface

Access to the Amazon Web Services (AWS) system uses the ```aws-sdk``` rubygem which communicates using the published
REST interface.  Access to the REST interface requires the user to create an _access key_ and make a note of the
<b>Access Key ID</b> and <b>Secret Access Key</b>.  To create an access key, browse to your AWS web console, find the
[Security Credentials](https://portal.aws.amazon.com/gp/aws/securityCredentials) page and the _Access Keys_ tab. 
Create an access key pair there.

When you have the access key id and the secret key, create a file in your home directory named ```.awscred``` and add
a line for each:

    AWSAccessKeyId=REPLACEMEWITHYOURID
    AWSSecretKey=REPLACEMEWITHYOURSECRET

If you're in a shared system, be sure to set the permissions on this file so that only you can read it.

With these keys in place you will be able to use the ```ec2:instance``` and ```ec2:image``` tasks.

## SSH User Keys

Once you've create and started an instance you will also want to be able to log into the instance (usually as the root user)
via an _SSH_ connection.  You'll need to create and place an SSH public key so that you will be able to log into your
instances. AWS makes a distinction between EC2 key pairs and those used for other features. Be sure you create an EC2
key pair.

The easiest way to create a key pair is to let AWS generate one for you and then download the private key to your
workstation.  Browse to the EC2 dashboard and select the 
[Key Pairs](https://console.aws.amazon.com/ec2/home?region=us-east-1#s=KeyPairs) tab. Click _Create Key Pair_ and enter
the name you want to use to identify the key.  AWS will generate a key and then offer to download the private key.  If
you called your keypair _openshift-root_ then AWS will offer to download a file named ```openshift-root.pem```.  Place
that file in your ```$HOME\.ssh``` directory.  Again, set the permissions on this file so that only you can read it. The
SSH program will not let you use the file if the permissions are not set tightly enough.

Next, add another line to ```.awscred``` like this:

    AWSKeyPairName=openshift-root

This will tell the ```remote:``` tasks to use that key when logging into your instances.

## Remote User

Finally for SSH access you need to tell the tasks which user to log in as.  It seems that the RHEL6 instances only allow
the _root_ user.  Newer instances like Fedora 18 offer a user named _ec2-user_ which is not root but which has ```sudo```
access with no password.  Select which you will use most (you can override it when invoking a task with the ```--username```
option)

    RemoteUser=root

At this point you should have all the information configured to use the ```remote``` tasks as well as the ```ec2``` ones.

## 
