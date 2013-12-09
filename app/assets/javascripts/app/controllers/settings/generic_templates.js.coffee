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

class New extends App.ExtendedController
  events:
    'submit form' : 'submit'

  constructor: ->
    super

  active: ->
    @render()

  render: ->
    @template = new GenericTemplate
    # TODO add header/footer
    @html @view('settings/generic_templates/form')(@)

  submit: (e) ->
    e.preventDefault()
    data = $(e.target).serializeObject()
    @template.load(data)
    @template.body = @view('settings/generic_templates/template')()
    @save_with_notifications @template, (id) =>
      @trigger 'edit', id

class Edit extends App.ExtendedController
  events:
    'submit form' : 'submit'
    'click button[name=settings-template-destroy]': 'destroy'
    'click button[name=settings-template-edit]': 'edit_template'

  active: (params) ->
    @id = params.id if params.id
    @render()

  render: =>
    return unless GenericTemplate.exists(@id)
    @show()
    @template = GenericTemplate.find(@id)
    @html @view('settings/generic_templates/form')(@)

  submit: (e) =>
    e.preventDefault()
    data = $(e.target).serializeObject()
    @template.load(data)
    @save_with_notifications @template, @hide

  edit_template: (e) ->
    e.preventDefault()
    console.log "#{GenericTemplate.url()}/#{@template.id}/edit.html"
    window.open "#{GenericTemplate.url()}/#{@template.id}/edit.html", "template"

  destroy: (e) ->
    e.preventDefault()
    if confirm(I18n.t('common.are_you_sure'))
      @destroy_with_notifications @template, @hide

class Index extends App.ExtendedController
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
    @edit.bind 'hide', => @new.show()

    @edit.bind 'destroyError', (id, errors) =>
      @edit.active id: id
      @edit.render_errors errors

  activate: ->
    super
    Language.one "refresh", =>
      GenericTemplate.fetch()
      @new.render()
    Language.fetch()
