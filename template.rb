# Don't put \r in inject/gsub

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

# Authentication
gem "devise"

# Authorisation
gem "cancan"

# Extras
gem "friendly_id"
gem "oj" # Faster JSON implementation

# Views
gem "draper"
gem "simple_form"

# Templates 
gem "haml"

gem_group "assets" do

end

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

# Platform specific config
platform = ask("Which platform will this app be running on? (defaults to heroku)")
case platform
when "something"
  # Blah
else
  gem "foreman"
end

gsub_file "config/environments/production.rb", /# config\.cache_store = :mem_cache_store/ do
<<-CODE
  config.cache_store = :dalli_store
CODE
end

%w{development test}.each do |env|
  inject_into_file "config/environments/#{env}.rb", after: "config.eager_load = false\n" do
<<-CODE
  config.cache_store = :null_store
CODE
  end
end

# Switch session store to dalli

file "config/environments/staging.rb", <<-CODE
  require "production"
CODE

file "Procfile", <<-CODE
  web: bundle exec puma -C config/puma.rb
  worker: bundle exec sidekiq
CODE

file "config/puma.rb", <<-CODE
  threads 8,8
  port $PORT
CODE

generate "devise:install"
generate :devise, "User"

inject_into_file "app/controllers/application_controller.rb", after: "protect_from_forgery with: :exception" do <<-CODE
  \n
  before_filter :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_in) { |u| u.permit(:username, :email) }
  end
CODE
end

rake "db:migrate"

git :init
git add: "."
git commit: %Q{ -m 'Initial commit' }
