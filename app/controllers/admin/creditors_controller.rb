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

class Admin::CreditorsController < ApplicationController

  respond_to :json

  layout false

  load_and_authorize_resource except: :index

  before_filter :set_money, only: [:create, :update]

  def index
    authorize! :index, Creditor

    errors = {}
    # pseudo validation
    unless params[:from].blank?
      if validate_date_format(params[:from])
        from = Date.parse params[:from]
      else
        errors[:from] = I18n.t("creditor.errors.wrong_date")
      end
    end

    unless params[:to].blank?
      if validate_date_format(params[:to])
        to = Date.parse params[:to]
      else
        errors[:to] = I18n.t("creditor.errors.wrong_date")
      end
    end

    if from and to and from > to
      errors[:from] = I18n.t("salary.errors.from_date_should_be_before_to_date")
    end

    if ['pdf', 'odt'].index params[:format]
      unless params[:generic_template_id]
        errors[:generic_template_id] = I18n.t("activerecord.errors.messages.blank")
      end
    end

    respond_to do |format|

      if errors.empty?
        ######### PREPARE ############

        @creditors = Creditor.order(:created_at)

        if from and to
          @creditors = @creditors.where("created_at BETWEEN ? AND ?", from, to)
        end

        if ['pdf', 'odt'].index params[:format]
          # Ensure at least a template is given
          # build generator using selected generic template
          fake_object = OpenStruct.new
          fake_object.template = GenericTemplate.find params[:generic_template_id]
          fake_object.creditors = @creditors

          generator = AttachmentGenerator.new(fake_object, nil)
        end

        ######### RENDER ############

        format.json { render json: CreditorsDatatable.new(view_context) }

        format.csv do
          fields = []
          fields << 'id'
          fields << 'owner_id'
          fields << 'owner.try(:name)'
          fields << 'buyer_id'
          fields << 'buyer.try(:name)'
          fields << 'receiver_id'
          fields << 'receiver.try(:name)'
          fields << 'title'
          fields << 'description'
          fields << 'value'
          fields << 'overpaid_value'
          fields << 'get_statuses.join(", ")'
          fields << 'created_at'
          fields << 'updated_at'
          render inline: csv_ify(@creditors, fields)
        end

        format.pdf do
          send_data generator.pdf,
            filename: "creditors.pdf",
            type: 'application/pdf'
        end

        format.odt do
          send_data generator.odt,
            filename: "creditors.odt",
            type: 'application/vnd.oasis.opendocument.text'
        end

      else
        format.json do
          render json: errors, status: :unprocessable_entity
        end
      end
    end
  end

  def show
    respond_with(@creditor)
  end

  def create
    if @creditor.save
      respond_with(@creditor)
    else
      render json: @creditor.errors, status: :unprocessable_entity
    end
  end

  def edit
    respond_with(@creditor)
  end

  def update
    if @creditor.update_attributes(creditor_params)
      respond_with(@creditor)
    else
      render json: @creditor.errors, status: :unprocessable_entity
    end
  end

  def destroy
    @creditor.destroy
    respond_with(@creditor)
    # format.json { render json: @creditor.errors, status: :unprocessable_entity }
  end

  private

    def set_money
      @creditor.value = Money.new(params[:value].to_f * 100, params[:value_currency]) if params[:value]
      @creditor.vat = Money.new(params[:vat].to_f * 100, params[:vat_currency]) if params[:vat]
    end

    def creditor_params
      params.require(:creditor).permit(
        :creditor_id,
        :affair_id,
        :title,
        :description,
        :value,
        :value_in_cents,
        :value_currency,
        :vat,
        :vat_in_cents,
        :vat_currency,
        :invoice_received_on,
        :invoice_ends_on,
        :invoice_in_books_on,
        :discount_percentage,
        :discount_ends_on,
        :paid_on,
        :payment_in_books_on,
        :updated_at )
    end

end