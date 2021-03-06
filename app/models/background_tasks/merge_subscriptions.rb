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

# Options are:
#   required: [:source_subscriptions_id, :destination_subscriptions_id, :person]
class BackgroundTasks::MergeSubscriptions < BackgroundTask

  def self.generate_title(options)
    I18n.t("background_task.tasks.merge_subscriptions",
      source_subscription_id: options[:source_subscription_id],
      destination_subscription_id: options[:destination_subscription_id])
  end

  def process!
    source_subscription = Subscription.find(options[:source_subscription_id])
    destination_subscription = Subscription.find(options[:destination_subscription_id])

    # add destination subscription to all current affairs
    source_subscription.affairs.each do |a|
      # Append the new subscription to the current subscription's affair
    	a.subscriptions << destination_subscription
      # Change affair's title so it's easier to read
      a.update_attributes(title: destination_subscription.title)
      a.invoices.each do |invoice|
        invoice.update_attributes(title: destination_subscription.title)
      end
    end

    # detach from all affairs
    source_subscription.affairs = []

    source_subscription_title = source_subscription.title
    source_subscription_id = source_subscription.id

    # and remove
    source_subscription.destroy

    # inform current user
    PersonMailer.send_subscriptions_merged(options[:person],
                  source_subscription_id,
                  source_subscription_title,
                  destination_subscription.id).deliver
  end
end
