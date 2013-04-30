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

## Setup

If this is your first time running `ciborg` and you do not have configuration file, yet, run:

    ciborg setup

It will ask you a series of questions that will get you up and running.

## Adjust Defaults (Optional)

If you don't like the default, Rails-centric, build script you can create your own:

```sh
#!/bin/bash -le

source .rvmrc

# install bundler if necessary
set -e

gem install bundler --no-ri --no-rdoc && bundle install

# debugging info
echo USER=$USER && ruby --version && which ruby && which bundle

bundle exec rake spec
```

In your config/ciborg.yml, there are defaults set for recommended values. For example, the EC2 instance size is set to "c1.medium".

You can save on EC2 costs by using a tool like [projectmonitor](https://github.com/pivotal/projectmonitor) or ylastic to schedule when your instances are online.

## Commit and push your changes

At this point you will need to create a commit of the files generated or modified and push those changes to your remote git repository so Jenkins can execute the build script when it pulls down your repo for the first time.

If you must, you can do this on a branch.  Then later you can change the branch in ciborg.yml later and rechef.

## Modify recipe list

You can modify the chef run list by setting the `recipes` key in config/ciborg.yml.  The default is:

	["pivotal_ci::jenkins", "pivotal_ci::limited_travis_ci_environment", "pivotal_ci"]`

Because we're using the cookbooks from Travis CI, you can look through [all the recipes Travis has available](https://github.com/travis-ci/travis-cookbooks/), and add any that you need.

## Manually starting your ciborg instance

1. Launch an instance, allocate and associate an elastic IP and update config/ciborg.yml:

        ciborg create

2. Bootstrap the instance using the boostrap_server.sh script. The script installs ruby prerequisites and installs RVM:

        ciborg bootstrap

3. Upload the contents of Ciborg's cookbooks, create a soloistrc, and run chef:

        ciborg chef

Your ciborg instance should now be up and running. You will be able to access your CI server at: http://&lt;your instance address&gt;/ with the username and password you chose during configuration. Or, if you are on a Mac, run `ciborg open`. For more information about Jenkins CI, see [http://jenkins-ci.org](http://jenkins-ci.org).

## Custom Chef Recipes

If you need to write your own chef recipes to install your project's dependencies, you can add a cookbooks directory to
the root of your project.  Make sure to delete the cookbook_paths section from your ciborg.yml (to use the default values),
or add ./chef/project-cookbooks to the cookbook_paths section.

So, to have a bacon recipe, you should have cookbooks/pork/recipes/bacon.rb file in your repository.

## Troubleshooting

Shell access for your instance

    ciborg ssh

Terminate all Ciborg instances on your account and deallocate their elastic IPs

    ciborg destroy_ec2

## Color

Ciborg installs the ansicolor plugin, however you need to configure rspec to generate colorful output. One way is to include `--color` in your .rspec and update your spec_helper.rb to include

``` ruby
RSpec.configure do |config|
 config.tty = true
end
```

## Dependencies

* ci_reporter
* fog
* godot
* haddock
* hashie
* httpclient
* net-ssh
* thor

## Forking

Please be aware that Ciborg uses git submodules.  In order to git source Ciborg in your `Gemfile`, you will need the following line:

    gem "ciborg", :github => "pivotal/ciborg", :submodules => true

## Testing

Ciborg is tested using rspec, vagrant and test kitchen.  You will need to set environment variables with your AWS credentials to run tests which rely on ec2:

    export EC2_KEY=FOO
    export EC2_SECRET=BAR

# Contributing

We welcome pull requests.  Pull requests should have test coverage for quick consideration.  Please fork, make your changes on a branch, and open a pull request.

# Support

* Check out past discussions on the [google groups forum](https://groups.google.com/a/pivotallabs.com/forum/#!forum/ciborg)
* Send the list an email at ciborg@pivotallabs.com
* View the project backlog on [Pivotal Tracker](https://www.pivotaltracker.com/s/projects/278959)

# License

Ciborg is MIT Licensed and © Pivotal Labs.  See LICENSE.txt for details.
