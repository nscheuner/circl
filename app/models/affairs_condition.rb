# == Schema Information
#
# Table name: affairs_conditions
#
#  id          :integer          not null, primary key
#  title       :string(255)
#  description :text
#  archive     :boolean          default(FALSE), not null
#

class AffairsCondition < ApplicationRecord

  ################
  ### INCLUDES ###
  ################

  #####################
  ### MISCEALLENOUS ###
  #####################

  #################
  ### CALLBACKS ###
  #################

  #################
  ### RELATIONS ###
  #################

  has_many :affairs, foreign_key: :condition_id

  ###################
  ### VALIDATIONS ###
  ###################

  validates_presence_of :title
  validates_presence_of :description

  scope :actives,  -> { where(archive: false)}
  scope :archived, -> { where(archive: true)}

  ########################
  ### INSTANCE METHODS ###
  ########################

  def as_json(options = nil)
    h = super(options)
    h[:affairs_count] = affairs.count
    h
  end

end
