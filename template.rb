# Don't put \r in inject/gsub

# Defaults
WEB_PORT = 5000

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

gsub_file "config/environments/production.rb", /# config\.cache_store = :mem_cache_store/ do
%Q{
  config.cache_store = :dalli_store
}
end

%w{development test}.each do |env|
  inject_into_file "config/environments/#{env}.rb", after: "config.eager_load = false\n" do
%Q{
  config.cache_store = :null_store
}
  end
end

# Switch session store to dalli

file "config/environments/staging.rb", %Q{
require "production"
}

file "Procfile", %Q{
web: bundle exec puma -C config/puma.rb
worker: bundle exec sidekiq
}

file "config/puma.rb", %q{
threads 8,8
bind "tcp://0.0.0.0:#{ENV['PORT']}"
}

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
generate :devise, "User"

gsub_file("app/models/user.rb", %Q{
  # Setup accessible (or protected) attributes for your model
  attr_accessible :email, :password, :password_confirmation, :remember_me
}, "")

inject_into_file "app/controllers/application_controller.rb", after: "protect_from_forgery with: :exception" do
%Q{
  \n
  before_filter :configure_permitted_parameters, if: :devise_controller?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.for(:sign_in) { |u| u.permit(:username, :email) }
  end
}
end

# Run migrations
rake "db:migrate"

# Git setup
git :init

# Add defaults to .gitignore
append_file ".gitignore", %Q{
.env
}

git add: "."
git commit: %Q{ -m 'Initial commit' }
