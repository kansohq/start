# Don't put \r in inject/gsub

def using_pow?
  @using_pow ||= yes?("Will pow be used for development?")
end

# Defaults
WEB_PLATFORM = "heroku"
USER_MODEL = "User"

if using_pow?
  HOST_NAME = "#{@app_name}.dev"
else
  HOST_NAME = "0.0.0.0:5000"
end

# Server
gem "puma"
gem "rack-cache"

# Workers
gem "sidekiq"

# Persistence
gem "pg"
gem "dalli"

# Services
gem "airbrake"
gem "postmark-rails"
gem "newrelic_rpm"

# Authorisation
gem "cancan"

# Authentication
gem "devise"

# Extras
gem "friendly_id"
gem "oj" # Faster JSON implementation

# Views
gem "draper"
gem "simple_form"

# Templates
gem "haml"

gem_group "development", "test" do
  # General
  gem "pry-rails"

  # Mail
  gem "letter_opener"
end

gem_group "test" do
  # RSpec
  gem "rspec-rails"

  # Models
  gem "machinist"
  gem "ffaker"
  gem "database_cleaner"
  gem "shoulda-matchers"

  gem "timecop"
end

#gsub_file("Gemfile", %Q{
# Use sqlite3 as the database for Active Record
#gem 'sqlite3'
#}, "")

# Set dalli as cache store in production
gsub_file "config/environments/production.rb", /# config\.cache_store = :mem_cache_store/ do
%Q{config.cache_store = :dalli_store}
end

# Set cache_store as null_store in development/test
%w{development test}.each do |env|
  application %Q{# Config options from start template
  config.cache_store = :null_store
  config.action_mailer.default_url_options = { host: ENV['HOST_NAME'] }
  }, env: env
end

# Set up letter_opener in development
application %Q{config.action_mailer.delivery_method = :letter_opener}, env: :development

# Switch session store to dalli
remove_file "config/initializers/session_store.rb"
file "config/initializers/session_store.rb", %Q{
if Rails.env.production?
  Rails.application.config.session_store ActionDispatch::Session::CacheStore, :expire_after => 20.minutes
end
}

file "config/environments/staging.rb",
%Q{require "production"}

file "Procfile",
%Q{web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq}

file "config/puma.rb",
%q{threads 8,8
bind "tcp://#{ENV['HOST_NAME']}"}

file "config/database.example.yml",
%Q{development:
  adapter: postgresql
  encoding: unicode
  database: #{@app_name}_development
  pool: 5
  username: postgres
  password:
  host: localhost

test:
  adapter: postgresql
  encoding: unicode
  database: #{@app_name}_test
  pool: 5
  username: postgres
  password:
  host: localhost}

# Set up a .env file for development
if yes? "Would you like to generate a .env file for local development?"
  host = ask("What hostname will the application respond to in development? (defaults to #{HOST_NAME})")
  host = HOST_NAME if host.blank?

  file ".env", %Q{
HOST_NAME=#{host}
}

  if using_pow?
    # export all variables in .env for use with pow
    file ".powenv", %q{export $(cat .env)}
  end
end

run 'bundle install'

# Devise
generate "devise:install"

inject_into_file "app/controllers/application_controller.rb", after: "protect_from_forgery with: :exception" do
%Q{
  before_filter :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_in) { |u| u.permit(:username, :email) }
  end
}
end

if yes?("Set up rspec and guard?")
  gem_group "test" do
    gem 'guard'
    gem 'guard-spork'
    gem 'guard-rspec'
    gem 'guard-sidekiq'
  end

  run 'bundle install'

  generate "rspec:install"
  run "bundle binstubs rspec-core"

  application %Q{config.generators do |g|
      g.test_framework :rspec
      g.fixture_replacement :machinist
    end}

  file "spec/support/blueprints.rb", "require 'machinist/active_record'\n"

  remove_file "spec/spec_helper.rb"
  file "spec/spec_helper.rb", %q{require 'rubygems'
require 'spork'

#uncomment the following line to use spork with the debugger
#require 'spork/ext/ruby-debug'

Spork.prefork do
  # Loading more in this block will cause your tests to run faster. However,
  # if you change any configuration or code from libraries loaded here, you'll
  # need to restart spork for it take effect.

  ENV["RAILS_ENV"] ||= 'test'
  require File.expand_path("../../config/environment", __FILE__)
  require 'rspec/rails'

  # Requires supporting ruby files with custom matchers and macros, etc,
  # in spec/support/ and its subdirectories.
  Dir[Rails.root.join("spec/support/**/*.rb")].each do |f|
    require f unless f =~ /\/blueprints\.rb$/
  end
end

Spork.each_run do
  # This code will be run each time you run your specs.
  require_relative 'support/blueprints.rb'
end
  }

  file "Guardfile", %q{notification :tmux, :display_message => true, :timeout => 3

guard 'spork', cucumber_env: { 'RAILS_ENV' => 'test' }, rspec_env: { 'RAILS_ENV' => 'test' }, test_unit: false do
  watch('config/application.rb')
  watch('config/environment.rb')
  watch('config/environments/test.rb')
  watch(%r{^config/initializers/.+\.rb$})
  watch('Gemfile')
  watch('Gemfile.lock')
  watch('spec/spec_helper.rb') { :rspec }
  watch('test/test_helper.rb') { :test_unit }
  watch(%r{features/support/}) { :cucumber }
end

#NOTE: Disabled for now, running jobs inline
### Guard::Sidekiq
#  available options:
#  - :verbose
#  - :queue (defaults to "default")
#  - :concurrency (defaults to 1)
#  - :timeout
#  - :environment (corresponds to RAILS_ENV for the Sidekiq worker)
#guard 'sidekiq', :environment => 'development' do
#  watch(%r{^workers/(.+)\.rb$})
#end

guard 'rspec', :cli => '--drb', :all_after_pass => false do
  watch(%r{^spec/.+_spec\.rb$})
  watch(%r{^lib/(.+)\.rb$})     { |m| "spec/lib/#{m[1]}_spec.rb" }
  watch('spec/spec_helper.rb')  { "spec" }

  # Rails example
  watch(%r{^app/(.+)\.rb$})                           { |m| "spec/#{m[1]}_spec.rb" }
  watch(%r{^app/(.*)(\.erb|\.haml)$})                 { |m| "spec/#{m[1]}#{m[2]}_spec.rb" }
  watch(%r{^app/controllers/(.+)_(controller)\.rb$})  { |m| ["spec/routing/#{m[1]}_routing_spec.rb", "spec/#{m[2]}s/#{m[1]}_#{m[2]}_spec.rb", "spec/acceptance/#{m[1]}_spec.rb"] }
  watch(%r{^spec/support/(.+)\.rb$})                  { "spec" }
  watch('app/controllers/application_controller.rb')  { "spec/controllers" }

  # Capybara request specs
  watch(%r{^app/views/(.+)/.*\.(erb|haml)$})          { |m| "spec/requests/#{m[1]}_spec.rb" }
  # Fabricator
  watch(%r{^spec/fabricators/(.+)_fabricator\.rb$})   { |m| "spec/model/#{m[1]}_spec.rb" }

  # Turnip features and steps
  watch(%r{^spec/acceptance/(.+)\.feature$})
  watch(%r{^spec/acceptance/steps/(.+)_steps\.rb$})   { |m| Dir[File.join("**/#{m[1]}.feature")][0] || 'spec/acceptance' }
end
  }

  file "spec/support/deferred_garbage_collection.rb", %q{class DeferredGarbageCollection
  DEFERRED_GC_THRESHOLD = (ENV['DEFER_GC'] || 10.0).to_f

  @@last_gc_run = Time.now

  def self.start
    GC.disable if DEFERRED_GC_THRESHOLD > 0
  end

  def self.reconsider
    if DEFERRED_GC_THRESHOLD > 0 && Time.now - @@last_gc_run >= DEFERRED_GC_THRESHOLD
      GC.enable
      GC.start
      GC.disable
      @@last_gc_run = Time.now
    end
  end
end

RSpec.configure do |config|
  config.before(:all) do
    DeferredGarbageCollection.start
  end
  config.after(:all) do
    DeferredGarbageCollection.reconsider
  end
end
  }

  file "spec/support/database_cleaner.rb", %q{RSpec.configure do |config|
  config.use_transactional_fixtures = false

  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.before(:each) do
    DatabaseCleaner.start
  end

  # This resolves problems with request specs
  config.before(type: :request) do
    DatabaseCleaner.strategy = :truncation
  end

  config.after(:each) do
    DatabaseCleaner.clean
  end
end
  }

  file "spec/support/controller_macros.rb", %q{module ControllerMacros
  def login_user
    before(:each) do
      @request.env["devise.mapping"] = Devise.mappings[:user]
      sign_in User.new(first_name: 'Test', last_name: 'User')
    end
  end
end
  }

  file "spec/support/devise.rb", %q{require_relative './controller_macros'
RSpec.configure do |config|
  config.include Devise::TestHelpers, type: :controller
  config.extend ControllerMacros, type: :controller
end
  }

  file "spec/support/sidekiq.rb", %q{require 'sidekiq/rails'
require 'sidekiq/testing'

RSpec.configure do |config|
  config.before(:each) do
    Sidekiq::Worker.clear_all
  end
end
  }
end

if yes?("Generate a default devise setup?")
  model_name = ask("Name for the devise model? (default is User)")
  model_name = USER_MODEL if model_name.blank?

  generate :devise, model_name

  lines = [
    "# Setup accessible (or protected) attributes for your model",
    "attr_accessible :email, :password, :password_confirmation, :remember_me"
  ]

  lines.each do |line|
    gsub_file("app/models/#{model_name.downcase}.rb", line, "")
  end
end

platform = ask("What hosting platform are you targetting? (default is heroku)")
platform = WEB_PLATFORM if platform.blank?

case platform
when "heroku"
  gem "memcachier"
end

# Set up database pool improvements
file "config/initializers/database_pool.rb", %q{
module DatabasePool
  def set_db_connection_pool_size!(size=500)
    # bump the AR connection pool
    if ENV['DATABASE_URL'].present? && ENV['DATABASE_URL'] !~ /pool/
      pool_size = ENV.fetch('DATABASE_POOL_SIZE', size)
      db = URI.parse ENV['DATABASE_URL']
      if db.query
       db.query += "&pool=#{pool_size}"
      else
       db.query = "pool=#{pool_size}"
      end
      ENV['DATABASE_URL'] = db.to_s
      ActiveRecord::Base.establish_connection
    end
  end

  module_function :set_db_connection_pool_size!
end

if Puma.respond_to?(:cli_config)
  DatabasePool.set_db_connection_pool_size! Puma.cli_config.options.fetch(:max_threads)
end
}

file "config/initializers/sidekiq.rb", %Q{
  Sidekiq.configure_server do |config|
    DatabasePool.set_db_connection_pool_size!(Sidekiq.options[:concurrency])
  end
}

# Run migrations
if yes?("Run migrations?")
  rake "db:migrate"
  rake "db:test:prepare"
end

# Git setup
git :init

# Add defaults to .gitignore
append_file ".gitignore", %Q{
# Ignore irritating OS X files
.DS_Store

# Ignore local environment files
.env

# Ignore local DB config
config/database.yml
}

git add: "."
git commit: %Q{ -m 'Initial commit' }

