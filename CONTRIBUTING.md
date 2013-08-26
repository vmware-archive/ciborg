# Contributing

We welcome pull requests.  Pull requests should have test coverage for quick consideration.  Please fork, make your changes on a branch, and open a pull request.

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
