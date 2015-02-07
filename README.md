# DEPRECATED!!!!  Ciborg is no longer under active development.

# Ciborg: Your Chief Administrative Aide on Cloud City

![Ciborg](http://cheffiles.pivotallabs.com/ciborg/logo.png)

[![Code Climate](https://codeclimate.com/github/pivotal/ciborg.png)](https://codeclimate.com/github/pivotal/ciborg)
[![Build Status](https://travis-ci.org/pivotal/ciborg.png?branch=master)](https://travis-ci.org/pivotal/ciborg)


## Easily create your CI server on EC2

Lando Calrissian relies on a cyborg to keep Cloud City afloat, and now you can rely on Ciborg to get your continuous integration server running in the cloud. Ciborg is a gem that will help you spin-up, bootstrap, and install Jenkins CI for your Rails app on Amazon EC2.

# What do I get?

* Commands for creating, starting, stopping, or destroying your CI server on EC2
* The full [Travis CI](http://travis-ci.org) environment on Ubuntu 12.04
* A Jenkins frontend for monitoring your builds

```
Tasks:
  ciborg add_build <name> <repository> <branch> <command>  # Adds a build to Ciborg
  ciborg bootstrap          # Configures Ciborg's master node
  ciborg certificate        # Dump the certificate
  ciborg chef               # Uploads chef recipes and runs them
  ciborg config             # Dumps all configuration data for Ciborg
  ciborg create             # Create a new Ciborg server using EC2
  ciborg create_vagrant     # Creates a vagrant instance
  ciborg destroy_ec2        # Destroys all the ciborg resources on EC2
  ciborg help [TASK]        # Describe available tasks or one specific task
  ciborg open               # Open a browser to Ciborg
  ciborg setup              # Sets up ciborg through a series of questions
  ciborg ssh                # SSH into Ciborg
  ciborg trust_certificate  # Adds the current master's certificate to your OSX keychain
```

Read on for an explanation of what each one of these steps does.

## Install

    gem install ciborg

Ciborg runs independently of your project and is not a dependency.

## Initial Setup

If this is your first time running `ciborg` and you do not have configuration file, yet, run:

    ciborg setup

This will ask you a series of questions that will get you up and running. You will need the following information available:
- The URL of your git repository. Jenkins needs to clone from this URL without supplying user authentication
- An SSH key that has pull access to the repository
- Any shell commands you want to run for your build
- Your AWS credentials
- The SSH key to access your EC2 instance

Your ciborg instance should now be up and running. You will be able to access it at: http://&lt;your instance address&gt;/ with the username and password you
chose during configuration. Or, if you are on a Mac, run `ciborg open`. For more information about Jenkins CI,
see [http://jenkins-ci.org](http://jenkins-ci.org).

## Updating your configuration

Ciborg stores your configuration in the file `config/ciborg.yml`, relative to where you ran `ciborg setup`.
You can update your configuration by running `ciborg chef` after editing the following keys in this file:

### node_attributes

This section contains the basic auth credentials for your EC2 instance and your jenkins build configuration.
The `jenkins.builds.command` field is the shell command that will be run for your build. Here is an example
build script for a ruby project:

```sh
#!/bin/bash -le

source .rvmrc
set -e
gem install bundler --no-ri --no-rdoc && bundle install
echo USER=$USER && ruby --version && which ruby && which bundle
bundle exec rake spec
```

### recipes

The default chef recipes that ciborg uses are:

	["pivotal_ci::jenkins", "pivotal_ci::limited_travis_ci_environment", "pivotal_ci"]

Because we're using the cookbooks from Travis CI, you can look through
[all the recipes Travis has available](https://github.com/travis-ci/travis-cookbooks/), and add any that you need.

### cookbooks

If you need to write your own chef recipes to install your project's dependencies, you can add a cookbooks directory to
the root of your project. Make sure that your `cookbook_paths` is either blank (to use the default values), or contains
`./chef/project-cookbooks`. So, to include a `bacon` recipe, you should have `cookbooks/pork/recipes/bacon.rb` file in
your repository.

## EC2 Configuration

Ciborg provides a set of default EC2 configuration parameters. For example, the instance size is set to "c1.medium".
You can save on EC2 costs by using a tool like [projectmonitor](https://github.com/pivotal/projectmonitor) or ylastic
to schedule when your instances are online. If you want to edit these parameters, you will need to destroy and re-create
your ciborg instance.


## Manually creating your ciborg instance

1. Launch an instance, allocate and associate an elastic IP and update config/ciborg.yml:

        ciborg create

2. Bootstrap the instance using the boostrap_server.sh script. The script installs ruby prerequisites and installs RVM:

        ciborg bootstrap

3. Upload the contents of Ciborg's cookbooks, create a soloistrc, and run chef:

        ciborg chef

## Troubleshooting

Shell access for your instance

    ciborg ssh

Terminate all Ciborg instances on your account and deallocate their elastic IPs

    ciborg destroy_ec2

# Support

* Check out past discussions on the [google groups forum](https://groups.google.com/a/pivotallabs.com/forum/#!forum/ciborg)
* Send the list an email at ciborg@pivotallabs.com
* View the project backlog on [Pivotal Tracker](https://www.pivotaltracker.com/s/projects/278959)
* View the project CI status at [ci.pivotallabs.com](http://ci.pivotallabs.com/)

# License

Ciborg is MIT Licensed and © Pivotal Labs.  See LICENSE.txt for details.
