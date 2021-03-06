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

Person = App.Person
PersonAffair = App.PersonAffair
PersonAffairReceipt = App.PersonAffairReceipt
PersonAffairInvoice = App.PersonAffairInvoice
Permissions = App.Permissions

$.fn.receipt = ->
  elementID   = $(@).data('id')
  elementID ||= $(@).parents('[data-id]').data('id')
  PersonAffairReceipt.find(elementID)

class New extends App.ExtendedController
  events:
    'submit form': 'submit'
    'click a[name="reset"]': 'reset'

  constructor: (params) ->
    super
    PersonAffair.bind('refresh', @active)
    PersonAffairInvoice.bind('refresh', @active)
    PersonAffairReceipt.bind('refresh', @active)

  active: (params) =>
    if params
      @person_id = params.person_id if params.person_id
      @affair_id = params.affair_id if params.affair_id
      @invoice = params.invoice if params.invoice
      @can = params.can if params.can
    @render()

  render: =>
    @receipt = new PersonAffairReceipt(value: 0)

    # TODO replace CCP by global variable
    @receipt.means_of_payment = 'CCP'

    # update receipt value if not existing
    if @affair_id and PersonAffair.exists(@affair_id) and not @receipt.value
      @affair = PersonAffair.find(@affair_id)
      if @affair.invoices_value > @affair.receipts_value
        @receipt.value = (@affair.invoices_value_with_taxes - @affair.receipts_value).toFixed(2)

    # link invoice to the new receipt if invoice ref exist
    if @invoice
      @receipt.value = @invoice.value_with_taxes
      @receipt.invoice_id = @invoice.id
      @receipt.invoice_title = @invoice.title

    @html @view('people/affairs/receipts/form')(@)
    if @disabled() then @disable_panel() else @enable_panel()

  disabled: =>
    PersonAffairReceipt.url() == undefined

  submit: (e) ->
    e.preventDefault()

    # reset invoice so next receipt is empty
    @invoice = undefined

    @save_with_notifications @receipt.fromForm(e.target), (id) =>
      PersonAffair.fetch(id: @affair_id)
      PersonAffairInvoice.fetch()
      @trigger('edit', id)

class Edit extends App.ExtendedController
  events:
    'submit form': 'submit'
    'click a[name="cancel"]': 'cancel'
    'click button[name="receipt-destroy"]': 'destroy'

  constructor: (params) ->
    super

  active: (params) ->
    if params
      @id = params.id if params.id
      @can = params.can if params.can
    @show()
    @render()

  render: =>
    return unless PersonAffairReceipt.exists(@id)
    @receipt = PersonAffairReceipt.find(@id)

    @affair = PersonAffair.find(@receipt.affair_id)

    @html @view('people/affairs/receipts/form')(@)

  update_callback: =>
    PersonAffair.fetch(id: @affair.id)
    PersonAffairInvoice.fetch()

  submit: (e) ->
    e.preventDefault()
    @receipt.fromForm(e.target)
    @save_with_notifications @receipt, @update_callback

  destroy: (e) ->
    e.preventDefault()
    @confirm I18n.t('common.are_you_sure'), 'warning', =>
      @destroy_with_notifications @receipt, =>
        @update_callback()
        @hide()

class Index extends App.ExtendedController
  events:
    'click tr.item':    'edit'
    'datatable_redraw': 'table_redraw'
    'mouseover tr.item':'item_over'
    'mouseout tr.item': 'item_out'
    'click a[name=affair_receipts_csv]': 'csv'
    'click a[name=affair_receipts_pdf]': 'pdf'
    'click a[name=affair_receipts_odt]': 'odt'

  constructor: (params) ->
    super
    PersonAffairReceipt.bind('refresh', @render)

  active: (params) ->
    @render()

  render: =>
    @receipts = PersonAffairReceipt.all()
    @html @view('people/affairs/receipts/index')(@)
    if @disabled() then @disable_panel() else @enable_panel()

  disabled: =>
    PersonAffairReceipt.url() == undefined

  edit: (e) ->
    e.preventDefault()
    receipt = $(e.target).receipt()
    @activate_in_list(e.target)

    # Activate invoice in its list
    $("#person_affair_invoices").data('controller').index.render()
    @toggle_item e, true, 'success'

    @trigger 'edit', receipt.id

  table_redraw: =>
    if @receipt
      target = $(@el).find("tr[data-id=#{@receipt.id}]")
    @activate_in_list(target)

  item_over: (e) =>
    @toggle_item e, true

  item_out: (e) =>
    @toggle_item e, false

  toggle_item: (e, status, sclass = 'warning') =>
    invoice_id = $(e.target).receipt().invoice_id

    if invoice_id
      person_affair_invoices_ctrl = $("#person_affair_invoices").data('controller')
      invoice_item = person_affair_invoices_ctrl.el.find("tr[data-id=#{invoice_id}]")

      if invoice_item
        if status
          invoice_item.addClass(sclass)
        else
          invoice_item.removeClass(sclass)

  csv: (e) ->
    e.preventDefault()
    window.location = PersonAffairReceipt.url() + ".csv"

  pdf: (e) ->
    e.preventDefault()
    @template_id = @el.find("#affair_receipts_template").val()
    window.location = PersonAffairReceipt.url() + ".pdf?template_id=#{@template_id}"

  odt: (e) ->
    e.preventDefault()
    @template_id = @el.find("#affair_receipts_template").val()
    window.location = PersonAffairReceipt.url() + ".odt?template_id=#{@template_id}"


class App.PersonAffairReceipts extends Spine.Controller
  className: 'receipts'

  constructor: (params) ->
    super

    if params
      @person_id = params.person_id if params.person_id
      @affair_id = params.affair_id if params.affair_id

    @index = new Index
    @edit = new Edit
    @new = new New
    @append(@new, @edit, @index)

    @index.bind 'new', (params) =>
      @new.active(params)

    @index.bind 'edit', (id) =>
      @edit.active(id: id)

    @new.bind 'edit', (id) =>
      @edit.active(id: id, person_id: @person_id)
      @index.active(receipt_id: id, person_id: @person_id)

    @edit.bind 'show', => @new.hide()
    @edit.bind 'hide', =>
      @new.show()
      @new.render()

    @edit.bind 'error', (id, errors) =>
      @edit.active id: id
      @edit.render_errors errors

    @edit.bind 'destroyError', (id, errors) =>
      @edit.active id: id
      @edit.render_errors errors

  activate: (params) ->
    super

    if params
      @person_id = params.person_id if params.person_id
      @affair_id = params.affair_id if params.affair_id

    Permissions.get { person_id: @person_id, can: { receipt: ['create', 'update'] }}, (data) =>
      @new.active { person_id: @person_id, affair_id: @affair_id, can: data }
      @index.active {can: data}
      @edit.active {can: data}
      @edit.hide()
