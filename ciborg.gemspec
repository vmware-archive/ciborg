# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'ciborg/version'

Gem::Specification.new do |spec|
  spec.name          = "ciborg"
  spec.version       = Ciborg::VERSION
  spec.authors       = ["Pivotal Labs"]
  spec.email         = ["ciborg@pivotallabs.com"]
  spec.description   = %q{CI in the Cloud}
  spec.summary       = %q{}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files`.split($/)
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.3"
  spec.add_development_dependency "rake"
end
