# == Schema Information
#
# Table name: salaries_taxes_is2014
#
#  id                   :integer          not null, primary key
#  tax_id               :integer          not null
#  year                 :integer          not null
#  tax_group            :string(255)      not null
#  children_count       :integer          not null
#  ecclesiastical       :string(255)      default("N"), not null
#  salary_from_in_cents :integer          default(0), not null
#  salary_from_currency :string(255)      default("CHF"), not null
#  salary_to_in_cents   :integer          default(0), not null
#  salary_to_currency   :string(255)      default("CHF"), not null
#  tax_value_in_cents   :integer          default(0), not null
#  tax_value_currency   :string(255)      default("CHF"), not null
#  tax_value_percentage :float            default(0.0), not null
#  created_at           :datetime
#  updated_at           :datetime
#

# TODO refactor this into a polymorphic association
class Salaries::Taxes::Is2014 < ApplicationRecord

  self.table_name = :salaries_taxes_is2014

  ################
  ### INCLUDES ###
  ################

  include SearchEngineConcern
  extend  MoneyComposer

  #################
  ### RELATIONS ###
  #################

  belongs_to :tax

  # money
  money :salary_from
  money :salary_to
  money :tax_value

  ###################
  ### VALIDATIONS ###
  ###################

  validates :year,
            :numericality => {:only_integer => true},
            :presence => true

  validates :tax_group, :presence => true

  validates :children_count,
            :numericality => {:only_integer => true}

  validates :salary_from_in_cents,
            :numericality => {:only_integer => true}

  validates :salary_to_in_cents,
            :numericality => {:only_integer => true}

  validates :tax_value_in_cents,
            :numericality => {:only_integer => true}

  validates :tax_value_percentage,
            :numericality => {:greater_than_or_equal_to => 0, :less_than_or_equal_to => 100}


  ########################
  ### CLASS METHODS ###
  ########################

  def self.compute(reference_value, year, infos, tax)
    data = where(:tax_id => tax.id, :year => year)
          .where('salary_from_in_cents <= ? and ? < salary_to_in_cents', *([reference_value.cents] * 2))

    # TODO improve the whole stack by allowing user to select which
    # code (A-P) is applied to the followin tax in Ui.
    if infos.married?
      data = data.where :tax_group => "B"
    else
      data = data.where :tax_group => "A"
    end

    # Limit children count to 9
    children_count = infos.children_count > 9 ? 9 : infos.children_count
    data = data.where :children_count => children_count

    # TODO define ecclesiastical tax to Y or N in UI.
    data = data.where :ecclesiastical => "N"

    # Pick the first (and probably the only) tax
    data = data.first

    if data

      {
        :taxed_value => reference_value,
        :employer =>
        {
          :percent => 0,
          :value   => 0.to_money,
          :use_percent  => true
        },
        :employee =>
        {
          :percent => data.tax_value_percentage,
          :value   => reference_value / 100 * data.tax_value_percentage,
          :use_percent  => true
        }
      }

    else

      {
        :taxed_value => reference_value,
        :employer =>
        {
          :percent => 0,
          :value   => 0.to_money,
          :use_percent  => true
        },
        :employee =>
        {
          :percent => 0,
          :value   => 0.to_money,
          :use_percent  => false
        }
      }

    end
  end

  def self.process_data(tax, data)
    transaction do
      #begin
        # parse file and build an array of generic tax
        items = []
        data.split(/\r?\n/).map do |line|

          case line.size
            when 110 # Starting line
              if line[0..1] == "00"
                puts "starting line"
              else
                puts "line size is 110 chars but not signed as a start of file (99)"
              end
            when 62 # record
              if line[0..1] == "06" # it is a new record
                case line[2..3]
                  when "01" # new record
                    items << new( :tax                  => tax,
                                  :tax_group            => line[6], # code
                                  :children_count       => line[7], # kids
                                  :ecclesiastical       => line[8], # ecclesiastical
                                  :year                 => line[16..19].to_i,
                                  :salary_from          => line[24..32].to_i / 100.0, # salary value start
                                  :salary_to            => (line[24..32].to_i / 100.0) + (line[33..41].to_i / 100.0), # steps
                                  :tax_value            => Money.new(line[45..53].to_i), # tax in francs, but always null
                                  :tax_value_percentage => line[54..58].to_i / 100.0)
                  when "02" # record modification
                    puts "record modification"
                  when "03" # record removed
                    puts "record removed"
                end
              else
                puts "line size is 62 chars but not signed as a record (06)"
              end
            when 39 # final line
              if line[0..1] == "99"
                puts "checksum"
              else
                puts "line size is 39 chars but not signed as a end of file (99)"
              end
            else
              puts "wrong line length"
          end

        end
        return if items.empty?

        # remove currently stored data for the same year(s)
        items.map(&:year).uniq.each do |year|
          where(:year => year, :tax_id => tax.id).destroy_all
        end

        # try to save taxes (it's a transaction...)
        items.each(&:save!)
        true # returns true instead of the tax

      #rescue
      #  false
      #end
    end
  end

end
