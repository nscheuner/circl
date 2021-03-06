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

# == Schema Information
#
# Table name: subscriptions
#
# *id*::                        <tt>integer, not null, primary key</tt>
# *title*::                     <tt>string(255), default(""), not null</tt>
# *description*::               <tt>text, default("")</tt>
# *interval_starts_on*::        <tt>date</tt>
# *interval_ends_on*::          <tt>date</tt>
# *value_in_cents*::            <tt>integer, default(0), not null</tt>
# *value_currency*::            <tt>string(255), default("CHF"), not null</tt>
# *invoice_template_id*::       <tt>integer</tt>
# *created_at*::                <tt>datetime</tt>
# *updated_at*::                <tt>datetime</tt>
# *pdf_file_name*::             <tt>string(255)</tt>
# *pdf_content_type*::          <tt>string(255)</tt>
# *pdf_file_size*::             <tt>integer</tt>
# *pdf_updated_at*::            <tt>datetime</tt>
# *last_pdf_generation_query*:: <tt>text</tt>
# *parent_id*::                 <tt>integer</tt>
#--
# == Schema Information End
#++

class Subscription < ActiveRecord::Base

  ################
  ### INCLUDES ###
  ################

  # include ChangesTracker
  include ElasticSearch::Mapping
  include ElasticSearch::Indexing
  include ElasticSearch::AutomaticPeopleReindexing

  #################
  ### CALLBACKS ###
  #################

  before_destroy :ensure_is_destroyable
  before_destroy :destroy_affairs
  after_commit :add_catchall_value_if_not_existing

  #################
  ### RELATIONS ###
  #################

  acts_as_tree

  has_and_belongs_to_many :affairs,
                          -> { uniq }

  has_many  :invoices,
            -> { uniq },
            through: :affairs

  has_many  :receipts,
            -> { uniq },
            through: :affairs

  has_many  :people,
            -> { uniq },
            through: :invoices,
            source: :owner

  has_many  :members,
            -> { uniq },
            through: :affairs,
            foreign_key: :owner_id,
            source: :owner

  has_many  :values,
            -> { order('position ASC') },
            class_name: 'SubscriptionValue'

  belongs_to :invoice_template

  has_attached_file :pdf

  ###################
  ### VALIDATIONS ###
  ###################

  validates_presence_of :title
  validates_uniqueness_of :title
  validates_with IntervalValidator
  validates_with DateValidator, attribute: :interval_starts_on
  validates_with DateValidator, attribute: :interval_ends_on
  validate :parent_id_is_not_id

  # Validate fields of type 'string' length
  validates_length_of :title, maximum: 255

  # Validate fields of type 'text' length
  validates_length_of :description, maximum: 65536

  # See invoice.rb for explanations
  validates_attachment_content_type :pdf, :content_type => /\A.*\Z/ # Fake validator
  # validates_attachment :pdf,
  #   content_type: { content_type: "application/pdf" }

  ########################
  ### INSTANCE METHODS ###
  ########################

  # acts as tree consequences
  def tree_level
    compute_tree_level(self)
  end

  def self_and_parents
    parents(self)
  end

  def self_and_descendants
    [self, descendants].flatten
  end

  # recusive!
  def parents(s = self)
    parents = [s]
    parents << parents(s.parent) if s.parent
    parents.flatten
  end

  # recusive!
  def descendants
    all = []
    self.children.each do |child|
      all << child
      all << child.descendants if child.children
    end
    all.flatten
  end

  # Theses methods work for a parent and its children but not the opposit way.
  # It's generaly not necessary to know who paid a parent subscription.
  def receipts_from_self_and_descendants
    self.self_and_descendants.map{|s| s.receipts}.flatten.uniq
  end

  def invoices_from_self_and_descendants
    self.self_and_descendants.map{|s| s.invoices}.flatten.uniq
  end

  # returns an AREL for the list of people (owners) from self and its children subscriptions.
  def people_from_self_and_descendants
    Person.joins(:subscriptions)
          .where('subscriptions.id IN (?)', self.self_and_descendants)
          .uniq
  end

  def people_for(private_tag_name)
    people.joins(:private_tags).where("private_tags.name = ?", private_tag_name)
  end

  def invoice_template_for(person)
    anything_from_values_for(person).invoice_template
  end

  def value_name_for(person)
    anything_from_values_for(person).private_tag.try :name
  end

  # money
  def value_for(person)
    anything_from_values_for(person).value
  end

  def invoices_value
    invoices.map{|i| i.value.to_money(ApplicationSetting.value("default_currency"))}.sum.to_money
  end

  def invoices_value_with_taxes
    invoices.map{|i| i.value_with_taxes.to_money(ApplicationSetting.value("default_currency"))}.sum.to_money
  end

  def receipts_value
    receipts.map{|i| i.value.to_money(ApplicationSetting.value("default_currency"))}.sum.to_money
  end

  def balance_value
    receipts_value - invoices_value_with_taxes
  end

  def overpaid_value
    # FIXME perfs
    # cents = invoices.select("(( SELECT SUM(r.value_in_cents)
    #                           FROM receipts r
    #                           WHERE r.invoice_id = invoices.id
    #                           HAVING invoices.value_in_cents < SUM(r.value_in_cents))
    #                           - invoices.value_in_cents) as val")
    #                 .group("invoices.id")
    #                 .select(&:val) # remove null values (nil)
    #                 .map{|i| i.val.to_i } # convert given strings to integers
    #                 .sum
    # Money.new(cents)
    (balance_value > 0) ? balance_value : 0.to_money
  end

  # Ensure every single invoice has been paid.
  # If the sum of receipts is greater than the sum of invoices, it
  # doesn't means every single invoice has been paid.
  def paid?
    invoices.inject(true) { |sum, i| sum and i.paid? }
  end

  # Returns true if it has overpaid invoices
  def overpaid?
    overpaid_value > 0
  end

  # Workflow and statuses

  # Returns an array of people which has invoices matching the given statuses.
  def get_people_from_invoices_status(statuses)
    mask = Invoice.statuses_value_for(statuses)
    people.where("(invoices.status::bit(16) & ?::bit(16))::int = ?", mask, mask)
  end

  # Returns an array of people which has affairs matching the given statuses.
  def get_people_from_affairs_status(statuses)
    mask = Affair.statuses_value_for(statuses)
    people.joins(:affairs).where("(affairs.status::bit(16) & ?::bit(16))::int = ?", mask, mask)
  end

  # override default JSON serialization
  def as_json(options = nil)
    h = super(options)
    h[:parent_title] = parent.title
    h[:values] = values.map do |v|
      { id: v.id,
        value: v.value.to_f,
        private_tag_id: v.private_tag.try(:id),
        private_tag_name: v.private_tag.try(:name),
        invoice_template_id: v.invoice_template.try(:id),
        invoice_template_title: v.invoice_template.try(:title),
        position: v.position }
    end
    h[:invoices_count] = invoices.count
    h[:invoices_value] = invoices_value.to_f
    h[:receipts_count] = receipts.count
    h[:receipts_value] = receipts_value.to_f
    h[:overpaid_value] = overpaid_value.to_f
    h[:pdf_public_url] = pdf_public_url
    h[:errors]         = errors
    h
  end

  def pdf_public_url
    Rails.configuration.settings["directory_url"] + pdf.url
  end

  def pdf_up_to_date?(current_query)
    return false unless pdf_updated_at

    # Check if pdf requires an update because subscription is newer
    return false if updated_at > pdf_updated_at.to_datetime

    invoices.each do |i|
      return false unless i.pdf_up_to_date?
    end

    last_pdf_generation_query == current_query.to_json
  end

  def destroy_affairs
    # affairs.destroy_all # this destroys only the relation, not the affairs themselves
    affairs.each {|a| a.invoices.destroy_all; a.destroy!}
  end

  # TODO Idealy this method should be in a callback but it takes
  # time to run it. So it has been moved in background task and is
  # called on subscriptions#update.
  def update_invoices!
    invoices.each do |i|
      i.update_attributes title: title

      # Skip invoice if template and value are already the same
      if i.invoice_template_id == invoice_template_for(i.buyer) and i.value == value_for(i.buyer)
        next
      end
      # Set invoice template and value to the subscription's one
      i.invoice_template = invoice_template_for(i.buyer)
      i.value = value_for(i.buyer)

      i.save!
    end
  end

  # TODO Put this and update_invoices in a background task so it doesn't block UI
  def update_affairs!
    # affair value should probably be ajusted if subscription values have change
    # Saving isn't enough, only estimations will see their value changed.
    affairs.each do |a|
      a.update_attributes title: title
      a.update_value!
    end
  end

  #
  # Update ElasticSearch index for all related people
  #   This includes owners, receivers and buyers
  #
  # @return [Array<Person>] list of updated people
  #
  def update_index!
    ids = affairs.pluck(:owner_id, :receiver_id, :buyer_id).flatten.uniq
    Person.find(ids).each do |p|
      p.update_elastic_search_index
    end
  end

  private

  # recusive!
  def compute_tree_level(s, level = 0)
    if s.parent
      level = compute_tree_level(s.parent, level + 1)
    end
    level
  end

  def ensure_is_destroyable
    affairs.each do |a|
      a.invoices.each do |i|
        unless i.receipts.empty?
          errors.add(:base,
                     I18n.t('subscription.errors.can_not_delete_if_has_receipts'))
          return false
        end
      end
    end

    unless self.descendants.empty?
      errors.add(:base, I18n.t('subscription.errors.can_not_delete_if_has_children'))
      return false
    end
  end

  def add_catchall_value_if_not_existing
    catchall = values.where(private_tag_id: nil)
    if catchall.count == 0

      pos = values.size > 0 ? values.last.position + 1 : 0

      values.create!( invoice_template: InvoiceTemplate.first,
                      value: 0,
                      position: pos)

    end
  end

  def anything_from_values_for(person)
    # find the first matching person's private_tags and
    # return its value
    v = values.where(private_tag_id: person.private_tags.map(&:id)).first

    # or return catchall value
    v ||= values.where(private_tag_id: nil).first
    v
  end

  def parent_id_is_not_id
    if id and parent_id == id
      errors.add(:base, I18n.t('subscription.errors.parent_id_must_be_another_subscription'))
      return false
    end
  end

end
