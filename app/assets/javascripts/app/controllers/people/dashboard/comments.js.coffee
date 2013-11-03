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

PersonComment = App.PersonComment

class Index extends App.ExtendedController
  events:
    'click tr.item': 'show'

  constructor: (params) ->
    super
    PersonComment.bind('refresh', @render)

  render: =>
    # Spine orders by ID, no matter what server sends.
    @comments = _.sortBy PersonComment.all(), (d) -> d.created_at
    @html @view('people/dashboard/comments')(@)

  show: (e) ->
    e.preventDefault()
    # We expect resource_id to be a the ID of a Person.
    # the plural of ressource_type gives the right path
    # but there is no pluralize method nor a way to convert
    # rails path to a decent route.
    id = $(e.target).parents('[data-id]').data('id')
    window.location = "#{Spine.Model.host}/people/#{id}#activities"

class App.DashboardComments extends Spine.Controller
  className: 'comments'

  constructor: (params) ->
    super
    @person_id = params.person_id

    PersonComment.url = =>
      "#{Spine.Model.host}/people/#{@person_id}/dashboard/comments"

    @index = new Index
    @append(@index)

  activate: ->
    super
    PersonComment.fetch()
