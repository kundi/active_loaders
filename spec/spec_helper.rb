ENV["RAILS_ENV"] ||= 'test'
require 'rspec/core'
require 'rspec/expectations'
require 'rspec/mocks'
require 'database_cleaner'
require 'pry'

require 'active_support/all'
require 'active_record'
require 'sequel'
require 'datasource'
require 'active_loaders/test'
require 'active_model_serializers'

Datasource.setup do |config|
  config.adapters = [:activerecord, :sequel, :ams]
  config.simple_mode = true
end

Dir["#{File.dirname(__FILE__)}/support/**/*.rb"].each { |f| require f }

RSpec.configure do |config|
  config.order = "random"

  config.filter_run_including focus: true
  config.run_all_when_everything_filtered = true

  config.before(:suite) do
    DatabaseCleaner.strategy = :truncation
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before :each do
    DatabaseCleaner.start
  end

  config.after :each do
    DatabaseCleaner.clean
  end
end
