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

class Templates::GenericThumbnails

  @queue = :documents
  include ResqueHelper

  def perform(params = nil)
    # Resque::Plugins::Status options
    params ||= options
    set_status(title: I18n.t("templates.jobs.generic_thumbnails.title"))

    ids = params[:ids]
    ids ||= GenericTemplate.all.map(&:id)

    gts = GenericTemplate.find([ids].flatten)
    total = gts.count
    gts.each_with_index do |gt, index|
      at(index + 1, total, I18n.t("common.jobs.progress", index: index + 1, total: total))
      AttachmentGenerator.take_snapshot(gt)
    end

    true
  end

end