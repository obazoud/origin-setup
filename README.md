# origin-setup

Tools to help setup an OpenShift Origin service on EC2

These are a set of Thor scripts and several file templates which,
together can be used to create the basis for an OpenShift Origin
service in EC2.

The Thor scripts proper are stored in the [tasks](tasks) subdirectory.

In addition, there is a small library used to provide configuration
and communications with the Amazon Web Services EC2 and Route53
systems.  Set the `RUBYLIB` environment variable so that ruby can find
the `aws.rb` module:

> git clone <giturl>/origin-setup
> cd origin-setup
> export RUBYLIB=\`pwd\`/lib

From there, each of the tasks can be called using the standard `thor`
invocation. To list all of the available tasks:

> thor list
> ... lots of tasks ...

To list tasks in the _remote_ namespace:

> thor list remote
> ... fewer tasks ...

To get help for a specific task:

> thor help remote:
