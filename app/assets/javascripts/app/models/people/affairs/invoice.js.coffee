#  CIRCL Directory
#  Copyright (C) 2011 Complex IT sàrl
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU Affero General Public License as
#  published by the Free Software Foundation, either version 3 of the
#  License, or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU Affero General Public License for more details.
#
#  You should have received a copy of the GNU Affero General Public License
#  along with this program.  If not, see <http://www.gnu.org/licenses/>.

class App.PersonAffairInvoice extends Spine.Model

  @configure 'PersonAffairInvoice', 'invoice_template_id', 'affair_id',
             'title', 'description', 'printed_address', 'value', 'cancelled',
             'offered', 'created_at', 'value_currency', 'vat', 'vat_currency',
             'vat_percentage', 'conditions', 'condition_id', 'custom_value_with_taxes'

  @extend Spine.Model.Ajax

  # URL is defined when loading an affair
  @url: -> undefined

  constructor: ->
    super

  @billable: ->
    (i for i in @all() when not i.offered and not i.cancelled)

  @unbillable: ->
    (i for i in @all() when i.offered or i.cancelled)
