# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'active_loaders/version'

Gem::Specification.new do |spec|
  spec.name          = "active_loaders"
  spec.version       = ActiveLoaders::VERSION
  spec.authors       = ["Jan Berdajs"]
  spec.email         = ["mrbrdo@gmail.com"]
  spec.summary       = %q{Ruby library to automatically preload data for your Active Model Serializers}
  spec.homepage      = "https://github.com/kundi/active_loaders"
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_dependency 'active_model_serializers', '~> 0.9'
  spec.add_dependency 'datasource', '~> 0.3'
  spec.add_development_dependency "bundler", "~> 1.6"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rspec", "~> 3.2"
  spec.add_development_dependency 'sqlite3', '~> 1.3'
  spec.add_development_dependency 'activerecord', '~> 4'
  spec.add_development_dependency 'pry', '~> 0.9'
  spec.add_development_dependency 'sequel', '~> 4.17'
  spec.add_development_dependency 'database_cleaner', '~> 1.3'
end
