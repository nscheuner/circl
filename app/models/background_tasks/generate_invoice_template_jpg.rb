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
# == Schema Information
#
# Table name: background_tasks
#
# *id*::         <tt>integer, not null, primary key</tt>
# *type*::       <tt>string(255)</tt>
# *options*::    <tt>text</tt>
# *created_at*:: <tt>datetime</tt>
# *updated_at*:: <tt>datetime</tt>
#--
# == Schema Information End
#++

# Options are: :invoice_template_id, :person
class BackgroundTasks::GenerateInvoiceTemplateJpg < BackgroundTask
  def self.generate_title(options)
    I18n.t("background_task.tasks.generate_invoice_template_jpg",
      invoice_template_id: options[:invoice_template_id],
      invoice_template_title: InvoiceTemplate.find(options[:invoice_template_id]).title)
  end

  def process!
    invoice_template = InvoiceTemplate.find(options[:invoice_template_id])
    invoice_template.take_snapshot
  end
end
