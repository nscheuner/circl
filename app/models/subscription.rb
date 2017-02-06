# == Schema Information
#
# Table name: subscriptions
#
#  id                        :integer          not null, primary key
#  title                     :string(255)      default(""), not null
#  description               :text             default("")
#  interval_starts_on        :date
#  interval_ends_on          :date
#  created_at                :datetime
#  updated_at                :datetime
#  pdf_file_name             :string(255)
#  pdf_content_type          :string(255)
#  pdf_file_size             :integer
#  pdf_updated_at            :datetime
#  last_pdf_generation_query :text
#  parent_id                 :integer
#

class Subscription < ApplicationRecord

  ################
  ### INCLUDES ###
  ################

  include SearchEngineConcern

  #################
  ### CALLBACKS ###
  #################

  before_save do
    values.new(value: 0) if values.count == 0
  end

  before_destroy :ensure_is_destroyable
  before_destroy :destroy_affairs
  after_commit :add_catchall_value_if_not_existing

  #################
  ### RELATIONS ###
  #################

  acts_as_tree

  has_and_belongs_to_many :affairs,
                          -> { distinct }

  has_many  :invoices,
            -> { distinct },
            through: :affairs

  has_many  :receipts,
            -> { distinct },
            through: :affairs

  has_many  :people,
            -> { distinct },
            through: :invoices,
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
  validates_with Validators::Interval
  validates_with Validators::Date, attribute: :interval_starts_on
  validates_with Validators::Date, attribute: :interval_ends_on

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
    people_from_self_and_descendants.joins(:invoices)
      .where("(invoices.status::bit(16) & ?::bit(16))::int = ?", mask, mask)
  end

  # Returns an array of people which has affairs matching the given statuses.
  def get_people_from_affairs_status(statuses)
    mask = Affair.statuses_value_for(statuses)
    people_from_self_and_descendants.joins(:affairs)
      .where("(affairs.status::bit(16) & ?::bit(16))::int = ?", mask, mask)
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

end
