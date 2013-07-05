# Don't put \r in inject/gsub

# Defaults
WEB_PORT = 5000
WEB_PLATFORM = "heroku"
USER_MODEL = "User"

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
end

gem_group "test" do
  # RSpec
  gem "rspec-rails"

  # Models
  gem "machinist"
  gem "ffaker"
  gem "database_cleaner"
  gem "shoulda-matchers"

  # Mail
  gem "letter_opener"

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
  application(nil, env: env) do
%Q{config.cache_store = :null_store}
  end
end

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
bind "tcp://0.0.0.0:#{$PORT}"}

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
  port = ask("What port would you like the web server to run on? (defaults to 5000)")
  port = WEB_PORT if port.blank?
  
  file ".env", %Q{
PORT=#{port}
  }
end

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

