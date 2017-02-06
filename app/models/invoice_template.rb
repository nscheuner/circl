# == Schema Information
#
# Table name: invoice_templates
#
#  id                     :integer          not null, primary key
#  title                  :string(255)      default(""), not null
#  html                   :text             default(""), not null
#  created_at             :datetime
#  updated_at             :datetime
#  with_bvr               :boolean          default(FALSE)
#  bvr_address            :text             default("")
#  bvr_account            :string(255)      default("")
#  snapshot_file_name     :string(255)
#  snapshot_content_type  :string(255)
#  snapshot_file_size     :integer
#  snapshot_updated_at    :datetime
#  show_invoice_value     :boolean          default(TRUE)
#  language_id            :integer          not null
#  account_identification :string(255)
#  odt_file_name          :string(255)
#  odt_content_type       :string(255)
#  odt_file_size          :integer
#  odt_updated_at         :datetime
#

class InvoiceTemplate < ApplicationRecord

  ################
  ### INCLUDES ###
  ################

  # include ChangesTracker

  #################
  ### CALLBACKS ###
  #################

  before_destroy :ensure_there_is_no_invoices, :ensure_there_is_no_subscriptions

  #################
  ### RELATIONS ###
  #################

  belongs_to :language
  has_many :invoices
  has_many :subscriptions, through: :subscription_values
  has_many :subscription_values

  has_attached_file :odt,
                    default_url: '/assets/invoice_with_bvr.odt',
                    use_timestamp: true

  has_attached_file :snapshot,
                    default_url: '/images/missing_thumbnail.png',
                    default_style: :thumb,
                    use_timestamp: true,
                    styles: {medium: ["420x594>", :png], thumb: ["105x147>", :png]}

  ###################
  ### VALIDATIONS ###
  ###################

  # validations
  validates_presence_of :title, :language_id
  validate :bvr_address_and_account_are_set
  validate :bvr_account_match_requirements
  validates_uniqueness_of :title

  # Validate fields of type 'string' length
  validates_length_of :title, maximum: 255
  validates_length_of :bvr_account, maximum: 255

  # Validate fields of type 'text' length
  validates_length_of :html, maximum: 65536
  validates_length_of :bvr_address, maximum: 65536

  validates_length_of :account_identification,
                      is: 6,
                      allow_blank: true

  validates_attachment :odt,
    content_type: { content_type: /^application\// }

  validates_attachment :snapshot,
    content_type: { content_type: [ /^image\//, "application/pdf" ] }

  ########################
  ### INSTANCE METHODS ###
  ########################

  def thumb_url
    snapshot.url(:thumb) if snapshot_file_name
  end

  def as_json(options = nil)
    h = super(options)

    h[:thumb_url] = thumb_url
    h[:odt_url] = odt.url

    h[:language_name] = language.try(:name)
    h[:invoices_count] = invoices.count
    h[:errors] = errors

    h
  end

  private

  def bvr_address_and_account_are_set
    if with_bvr
      if bvr_address.blank? or bvr_account.blank?
        errors.add(:with_bvr,
                   I18n.t('invoice_template.errors.bvr_address_and_bvr_account_are_required_if_with_bvr_is_set'))
        return false
      end
    end
  end

  def bvr_account_match_requirements
    if with_bvr # don't check if with_bvr isn't set
      unless bvr_account.match(/^[0-9]{1,2}-[0-9]{1,6}-[0-9]$/)
        errors.add(:bvr_account,
                   I18n.t('invoice_template.errors.bvr_account_must_match_format'))
        return false
      end
    end
  end

  def ensure_there_is_no_invoices
    unless invoices.empty?
      errors.add(:base,
                 I18n.t('invoice_template.errors.can_not_delete_if_invoices_are_subscribed'))
      return false
    end
  end

  def ensure_there_is_no_subscriptions
    unless subscriptions.empty?
      errors.add(:base,
                 I18n.t('invoice_template.errors.can_not_delete_if_subscriptions_are_subscribed'))
      return false
    end
  end

end
