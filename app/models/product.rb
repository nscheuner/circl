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

class Product < ActiveRecord::Base

  ################
  ### INCLUDES ###
  ################

  include ChangesTracker
  include ElasticSearch::Mapping
  include ElasticSearch::Indexing
  extend  MoneyComposer

  #################
  ### CALLBACKS ###
  #################


  #################
  ### RELATIONS ###
  #################

  has_one   :provider, :class_name => 'Person'
  has_one   :after_sale, :class_name => 'Person'

  has_many  :variants,  :class_name => 'ProductVariant',
                        :dependent => :destroy

  has_many  :programs,  :through => :variants

  scope :actives, Proc.new { where(:archive => false)}
  scope :archived, Proc.new { where(:archive => true)}

  ###################
  ### VALIDATIONS ###
  ###################

  validates :key, :presence => true,
                  :length => { :maximum => 255 },
                  :uniqueness => true

  ########################
  #### CLASS METHODS #####
  ########################


  ########################
  ### INSTANCE METHODS ###
  ########################

end
