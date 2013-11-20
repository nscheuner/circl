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

class ProductProgram < ActiveRecord::Base

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

  # TODO prevent destroy if has product

  #################
  ### RELATIONS ###
  #################

  has_many :product_items, :class_name => 'AffairsProductsProgram',
                           :foreign_key => 'program_id',
                           :dependent => :destroy
  has_many :products, :through => :product_items
  has_many :affairs,  :through => :product_items

  scope :actives, Proc.new { where(:archive => false)}
  scope :archived, Proc.new { where(:archive => true)}

  ###################
  ### VALIDATIONS ###
  ###################

  validates :key, :presence => true,
                  :length => { :maximum => 255 },
                  :uniqueness => true
  validates :program_group, :presence => true,
                            :length => { :maximum => 255 }

  ########################
  #### CLASS METHODS #####
  ########################


  ########################
  ### INSTANCE METHODS ###
  ########################

end