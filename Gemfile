source 'http://rubygems.org'

gem 'rails', '5.0.0'
gem 'tilt'
gem 'rake-progressbar'
gem 'rake'

# Servers
gem 'foreman'
gem 'passenger'
gem 'activerecord-session_store'

### database
gem 'pg'
gem 'redis'
gem 'elasticsearch-rails'
gem 'elasticsearch-model'
gem 'acts_as_tree'
gem 'net-ldap', :git => 'git://github.com/ruby-ldap/ruby-net-ldap.git'

# pdf and images
gem 'pdfkit'
gem 'imgkit'
gem 'paperclip'
gem 'serenity', '0.2.4', :git => 'git://github.com/theoo/serenity.git'
gem 'rubyzip'
gem 'recursive-open-struct'

### Views/UI specific
gem 'responders'
gem 'will_paginate'
gem 'jquery-rails'
gem 'jquery-ui-rails'
gem 'sass-rails'
gem 'haml-rails'
gem 'haml_coffee_assets', github: "emilioforrer/haml_coffee_assets", branch: "release/v2.0.0"
gem 'dotiw', github: 'radar/dotiw'
gem 'coffee-rails'

gem 'jquery-turbolinks'
gem 'turbolinks'

gem 'gon'

gem 'jbuilder'
gem 'execjs'
gem 'therubyracer', platforms: :ruby
gem "i18n-js", ">= 3.0.0.rc12"
gem 'i18n-tasks'
gem 'lit'
gem 'yui-compressor'

### maps
gem 'geoip'
gem 'geokit'

### authentication and authorization
gem 'password_strength'
gem 'devise'
gem 'devise-i18n'
gem 'devise-encryptable'
gem 'cancancan'

### Finances
gem 'money'
gem 'monetize'

### MailChimp
gem 'mailchimp-api', require: 'mailchimp'

# Background jobs
gem 'resque'
gem 'resque-web', require: 'resque_web'
# gem 'resque-status'

# Monitoring
gem 'rails_exception_handler', "~> 2"

### custom gem
# gem 'plugin', :path => 'path/to/circl/plugin'

### development console and testing
group :development, :test do
  ### Documentation
  gem 'railroady'
  gem 'byebug'

  ### Test
  gem 'factory_girl_rails'
  gem 'rspec-rails'
  gem 'syntax'
  gem 'database_cleaner'

  ### Misc
  gem 'pry'
  gem 'pry-rails'
  gem 'pry-byebug'
  gem 'awesome_print'
  gem 'coolline'
  gem 'coderay'
  gem 'spring'

  gem 'meta_request'
  gem 'net-ssh'
  gem 'net-sftp'
end

gem 'web-console', group: :development

# iCalendar
# gem 'icalendar'

# Misc

group :doc do
#   # bundle exec rake doc:rails generates the API under doc/api.
#   gem 'sdoc', require: false
  gem 'annotate'
end

ruby '2.3.1'
