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

class PersonAffairsDatatable
  delegate :params, :h, :link_to, :number_to_currency, to: :@view

  include ApplicationHelper
  include Haml::Helpers

  def initialize(view, person)
    @view = view
    @person = person

    init_haml_helpers
  end

  def as_json(options = {})
    total = Affair.where("(owner_id = ? OR buyer_id = ? OR receiver_id = ?) AND archive = false", *([@person.id]*3)).count
    {
      sEcho: params[:sEcho].to_i,
      iTotalRecords: total,
      iTotalDisplayRecords: total, # total_entries won't work with as_tree stored proc
      aaData: data
    }
  end

  private

  def data
    affairs.map do |affair|

      classes = []
      # Colorize active affairs
      if affair.owner_id != @person.id
        # Foreign affairs
        classes.push 'info'
      elsif ! affair.has_status?(:cancelled) \
          and ! affair.has_status?(:offered) \
          and ! affair.has_status?(:paid)
          classes.push("success") unless affair.estimate
          classes.push("warning") if affair.estimate
      end

      description = capture_haml do
        haml_concat affair.title

        if affair.owner_id != @person.id
          haml_tag :br
          haml_tag :b, I18n.t("affair.views.owner")  + ": " + affair.owner.try(:name)
        end

        if affair.receiver_id != @person.id
          haml_tag :br
          haml_tag :b, I18n.t("affair.views.receiver")  + ": " + affair.receiver.try(:name)
        end

        if affair.buyer_id != @person.id
          haml_tag :br
          haml_tag :b, I18n.t("affair.views.buyer")  + ": " + affair.buyer.try(:name)
        end
      end

      value = affair_value_summary(affair)

      h = {
        0 => affair.id,
        1 => affair.parent_id,
        2 => description,
        3 => value,
        4 => affair.invoices_value_with_taxes.to_view, # sql shortcut
        5 => affair.receipts_value.to_view, # sql shortcut
        6 => affair.translated_statuses,
        7 => affair.created_at,
        8 => affair.sold_at.try(:to_date),
        'id' => affair.id,
        'number_columns' => [3,4,5],
        'classes' => classes.join(" ")
      }
    end
  end

  def affairs
    @affairs ||= fetch_affairs
  end

  # TODO: improve search like "Firstname Lastname", actually returns zero results.
  def fetch_affairs
    affairs = Affair.select('a.*,
                            COUNT(invoices.id) as invoices_count,
                            COUNT(receipts.id) as receipts_count,
                            COALESCE(SUM(invoices.value_in_cents)/100.0, 0.0) as invoices_sum,
                            COALESCE(SUM(receipts.value_in_cents)/100.0, 0.0) as receipts_sum')
                    .from("person_affairs_as_tree() a")
                    .where("owner_id = ? OR buyer_id = ? OR receiver_id = ?", *([@person.id]*3))
                    .where("a.archive = false") # exclude archive
                    .joins('LEFT JOIN invoices ON invoices.affair_id = a.id')
                    .joins('LEFT JOIN receipts ON receipts.invoice_id = invoices.id')
                    .joins("LEFT JOIN people ON a.owner_id = people.id")
                    .group('a.id,
                      a.parent_id,
                      a.owner_id,
                      a.receiver_id,
                      a.seller_id,
                      a.buyer_id,
                      a.condition_id,
                      a.title,
                      a.value_in_cents,
                      a.value_currency,
                      a.vat_in_cents,
                      a.vat_currency,
                      a.sold_at,
                      a.created_at,
                      a.updated_at,
                      a.status,
                      a.estimate,
                      a.archive,
                      a.sort,
                      people.last_name')
    if params[:sSearch].present?
      param = params[:sSearch].to_s.gsub('\\'){ '\\\\' } # We use the block form otherwise we need 8 backslashes
      if param.is_i?
        affairs = affairs.where("a.id = ?", param)
      else
        affairs = affairs.where("a.title ~* ?
                                 OR people.first_name ~* ?
                                 OR people.last_name ~* ?", *([param] * 3))
      end
    end

    if sort_column == "id" or sort_column == "parent_id"
      order = "a.sort #{sort_direction}, a.id #{sort_direction}"
    else
      order = "#{sort_column} #{sort_direction}"
    end

    affairs = affairs.order(order)
    affairs = affairs.page(page).per_page(per_page)
    affairs
  end

  def page
    (params[:iDisplayStart].to_i/per_page) + 1
  end

  def per_page
    (params[:iDisplayLength].to_i > 0) ? params[:iDisplayLength].to_i : 10
  end

  def sort_column
    columns = %w(id parent_id title value_in_cents invoices_sum receipts_sum status created_at sold_at)
    columns[params[:iSortCol_0].to_i]
  end

  def sort_direction
    params[:sSortDir_0] == 'desc' ? 'desc' : 'asc'
  end
end
