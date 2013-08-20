=begin
  CIRCL Directory
  Copyright (C) 2011 Complex IT sàrl

  This program is free software: you can redistribute it and/or modify
  it under the terms of the GNU Affero General Public License as
  published by the Free Software Foundation, either version 3 of the
  License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU Affero General Public License for more details.

  You should have received a copy of the GNU Affero General Public License
  along with this program.  If not, see <http://www.gnu.org/licenses/>.
=end

if Rails.configuration.settings['mailers']
  h = Rails.configuration.settings['mailers']
  if h.has_key?(Rails.env)
    h[Rails.env].each do |key, value|
      ActionMailer::Base.send(key, value.to_options)
    end
  end
end

# Configure mailer, no matter which environment it is.
Rails.configuration.action_mailer.default_url_options = { :host => Rails.configuration.settings['host'] }
