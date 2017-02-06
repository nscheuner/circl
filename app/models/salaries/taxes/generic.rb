# TODO refactor this into a polymorphic association
class Salaries::Taxes::Generic < ApplicationRecord

  self.table_name = :salaries_taxes_generic

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
  money :employer_value
  money :employee_value

  ###################
  ### VALIDATIONS ###
  ###################

  validates :year,
            numericality: {only_integer: true},
            presence: true

  validates :salary_from_in_cents,
            numericality: {only_integer: true}

  validates :salary_to_in_cents,
            numericality: {only_integer: true}

  validates :employer_value_in_cents,
            numericality: {only_integer: true}

  validates :employer_percent,
            numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 100}

  validates :employer_use_percent,
            inclusion: { in: [true, false] }

  validates :employee_value_in_cents,
            numericality: {only_integer: true}

  validates :employee_percent,
            numericality: {greater_than_or_equal_to: 0, less_than_or_equal_to: 100}

  validates :employee_use_percent,
            inclusion: { in: [true, false] }

  #####################
  ### CLASS METHODS ###
  #####################

  def self.compute(reference_value, year, infos, tax)
    data = where(tax_id: tax.id, year: year).first
    raise RuntimeError, 'Cannot find tax data' unless data

    if data
      if infos.yearly_salary && (data.salary_from_in_cents? || data.salary_to_in_cents?)
        from = data.salary_from
        to = data.salary_to || infos.yearly_salary
        to = infos.yearly_salary if to > infos.yearly_salary
        if from >= to
          taxed_value = 0
        else
          range = to - from
          ratio = Rational(range.cents, infos.yearly_salary.cents)
          taxed_value = reference_value * ratio.to_f
        end
      else
        taxed_value = reference_value
      end

      taxed_value = taxed_value.to_money

      # TODO
      # create a helper class foo_data for the employee/employer (:attr_accessor %w{percent value use_percent})
      # create another helper class that uses two foo_data as `composed_of` that splits fields
      # over the appropriate db fields
      {
        taxed_value: taxed_value,
        employer:
        {
          percent: data.employer_percent,
          value: taxed_value * (data.employee_percent / 100),
          use_percent: true
        },
        employee:
        {
          percent: data.employee_percent,
          value: taxed_value * (data.employee_percent / 100),
          use_percent: true
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
          :use_percent  => true
        }
      }

    end

  end

  def self.process_data(tax, data)
    transaction do
      begin
        # parse file and build an array of generic tax
        items = CSV.parse(data, encoding: 'UTF-8')[1..-1].map do |row|
          return false if row.size != 9

          # TODO Move validation to lib an include it in every taxes type.

          # validates integers
          [0].each do |i|
            # This will raise an error if the string doesn't represent an integer
            Integer(row[i]) unless row[i].nil?
          end

          # validates floats
          [1,2,3,4,6,7].each do |i|
            # This will raise an error if the string doesn't represent a float
            Float(row[i]) unless row[i].nil?
          end

          # validates booleans
          [5,8].each do |i|
            return false unless ['true', 'false'].index(row[i])
          end

          new tax: tax,
              year: row[0].to_i,
              salary_from: row[1].to_i,
              salary_to: row[2].to_i,
              employer_value: row[3].to_i,
              employer_percent: row[4].to_f,
              employer_use_percent: (row[5] == "true"),
              employee_value: row[6].to_i,
              employee_percent: row[7].to_f,
              employee_use_percent: (row[8] == "true")
        end
        return if items.empty?

        # remove currently stored data for the same year(s)
        items.map(&:year).uniq.each do |year|
          where(year: year, tax_id: tax.id).destroy_all
        end

        # try to save taxes (it's a transaction...)
        items.each(&:save!)
        true # returns true instead of the tax
      rescue
        # Don't raise an error if file isn't the correct format.
        # Simply cancel the transaction
        false
      end
    end
  end

end
