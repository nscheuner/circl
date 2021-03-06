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

class AdminController < ApplicationController

  layout 'application'

  def index
    authorize! :index, Admin

    # GON
    gon.affairs_count = Affair.count

    gon.selected_admin_creditors = session[:selected_admin_creditors]
    gon.creditor_statuses = {all: I18n.t("common.all")}.merge(Creditor.statuses)
    gon.creditor_date_fields = Creditor.date_fields

    gon.selected_admin_affairs = session[:selected_admin_affairs]
    gon.affair_statuses = {all: I18n.t("common.all")}.merge(Affair.translated_statuses)
    gon.affair_date_fields = Affair.translated_date_fields

    respond_to do |format|
      format.html { render }
    end
  end

end
