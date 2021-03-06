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

GenericTemplate = App.GenericTemplate
Language = App.Language

$.fn.template = ->
  elementID   = $(@).data('id')
  elementID ||= $(@).parents('[data-id]').data('id')
  GenericTemplate.find(elementID)

class ClassNamesExtension extends App.ExtendedController

  constructor: ->
    super
    @class_names = {}
    @class_names['Salaries::Salary'] = I18n.t("activerecord.models.salary")
    @class_names['Affair']           = I18n.t("activerecord.models.affair")
    @class_names['Invoice']          = I18n.t("activerecord.models.invoice")
    @class_names['Receipt']          = I18n.t("activerecord.models.receipt")
    @class_names['Task']             = I18n.t("activerecord.models.task")
    @class_names['Person']           = I18n.t("activerecord.models.person")
    @class_names['Product']          = I18n.t("activerecord.models.product")
    @class_names['Extra']            = I18n.t("activerecord.models.extra")
    @class_names['Creditor']         = I18n.t("activerecord.models.creditor")

class New extends ClassNamesExtension
  events:
    'submit form' : 'submit'
    'click a[name="reset"]': 'reset'

  constructor: ->
    super

  active: (params) ->
    console.log "test"
    if params and params.clone_id
      clone = GenericTemplate.find(params.clone_id)
      @_template = clone.attributes()
      @_template.id = null
    else
      @_template = {plural: false}

    @render()

  render: ->
    @template = new GenericTemplate(@_template)
    @html @view('settings/generic_templates/form')(@)

  submit: (e) ->
    e.preventDefault()
    data = $(e.target).serializeObject()
    @template.load(data)
    @template.plural = data.plural?
    @save_with_notifications @template, (id) =>
      @trigger 'edit', id

class Edit extends ClassNamesExtension
  events:
    'submit form' : 'submit'
    'click a[name="cancel"]': 'cancel'
    'click button[name=settings-template-destroy]': 'destroy'
    'click button[name=settings-template-copy]': 'copy'
    'click #settings_template_upload': 'stack_upload_window'

  active: (params) ->
    @id = params.id if params.id
    @render()

  render: =>
    return unless GenericTemplate.exists(@id)
    @show()
    @template = GenericTemplate.find(@id)
    @html @view('settings/generic_templates/form')(@)
    @el.find("#settings_template_download").tooltip(placement: 'bottom', container: 'body')
    @el.find("#settings_template_upload").tooltip(placement: 'bottom', container: 'body')

  submit: (e) =>
    e.preventDefault()
    data = $(e.target).serializeObject()
    @template.load(data)
    @template.plural = data.plural?
    @save_with_notifications @template

  copy: (e) ->
    e.preventDefault()
    @trigger 'copy', {clone_id: @id, type: 'copy'}

  destroy: (e) ->
    e.preventDefault()
    @confirm I18n.t('common.are_you_sure'), 'warning', =>
      @destroy_with_notifications @template, @hide

  stack_upload_window: (e) ->
    e.preventDefault()

    win = $("<div class='modal fade' id='settings-template-upload-modal' tabindex='-1' role='dialog' />")
    # render partial to modal
    modal = JST["app/views/helpers/modal"]()
    win.append modal
    win.modal(keyboard: true, show: false)

    controller = new App.UploadGenericOdt({el: win.find('.modal-content'); id: @template.id})

    controller.activate()
    win.modal('show')

class Index extends ClassNamesExtension
  events:
    'click tr.item': 'edit'
    'datatable_redraw': 'table_redraw'

  constructor: (params) ->
    super
    GenericTemplate.bind('refresh', @render)

  render: =>
    @html @view('settings/generic_templates/index')(@)

  new: (e) ->
    @trigger 'new'

  edit: (e) ->
    template = $(e.target).template()
    @activate_in_list(e.target)
    @trigger 'edit', template.id

  table_redraw: =>
    if @template
      target = $(@el).find("tr[data-id=#{@template.id}]")

    @activate_in_list(target)

class App.UploadGenericOdt extends App.ExtendedController
  events:
    'submit form': 'send'

  constructor: (params) ->
    super
    @template = GenericTemplate.find(params.id)

  render: ->
    @html @view('settings/generic_templates/upload')(@)

  send: (e) ->
    e.preventDefault()
    template = $(e.target).serializeObject()

    # jquery.iframe-transport (and this technique) doesn't allows
    # me to trigger error or success event. No matter which status
    # is sent back, the plugin trig the success event.
    on_complete = (xhr, status) =>

      response = JSON.parse(xhr.responseText)
      # error
      if Object.keys(response.errors).length > 0
        text = I18n.t('common.errors.failed_to_update')
        @render_errors(response.errors)

      # success
      else
        # if a validation failed before, remove it's explanation
        @el.find('.validation_errors_placeholder').css('display', 'none')
        text = I18n.t('common.notices.successfully_updated')

        # update template item on template widget/list
        GenericTemplate.fetch(id: template.template_id)
        @el.closest(".modal").modal('hide')


    settings =
      url: "/settings/generic_templates/#{@template.id}/upload_odt.json"
      type: 'post'
      data: {authenticity_token: App.authenticity_token()}
      files: @el.find(':file')
      iframe: true
      processData: false

    GenericTemplate.ajax().ajax(settings).complete(on_complete)

  activate: ->
    super
    @render()

class App.SettingsGenericTemplates extends Spine.Controller
  className: 'settings_templates'

  constructor: (params) ->
    super

    @new = new New
    @edit = new Edit
    @index = new Index

    @append(@new, @edit, @index)

    @new.bind 'edit', (id) =>
      @edit.active(id: id)
    @index.bind 'edit', (id) =>
      @edit.active(id: id)

    @edit.bind 'show', => @new.hide()
    @edit.bind 'hide', =>
      @new.render()
      @new.show()

    @edit.bind 'destroyError', (id, errors) =>
      @edit.active id: id
      @edit.render_errors errors

    @edit.bind 'copy', (params) =>
      @new.active(params)
      @edit.hide()

  activate: ->
    super
    Language.one "refresh", =>
      GenericTemplate.fetch()
      @new.render()
    Language.fetch()
