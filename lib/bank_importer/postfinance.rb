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

require 'nokogiri'

module BankImporter

  class Postfinance

    class << self

      class ParsingError < StandardError; end

      def parse_receipts(data)
        # load or create receipts in infos hash

        if data.match(/^<\?xml/)
          infos = self.parse_xml_file(data)
        else
          infos = self.parse_v11_file(data)
        end

        infos.each do |line, info|

          next if line == :errors # bypass general errors
          next if line == :summary # bypass summary

          case info[:status]
          when 'correct'
            info[:receipt] = Receipt.new(info[:receipt])

          when 'already_imported'
            info[:receipt] = Receipt.where(info[:receipt]).first

          when 'rectification'
            # extract new value
            new_value = info[:receipt][:new_value_in_cents]
            info[:receipt].delete(:new_value_in_cents)
            # If there is more than one receipt, assume it's the first...

            r = Receipt.where(info[:receipt]).first

            if r.nil?
              info[:errors] = { :message => I18n.t("receipt.import.rectification_for_inexistant_receipt",
                                              :invoice_id => info[:receipt][:invoice_id]),
                                :line => info[:line].strip,
                                :decoded_line => info[:decoded_line] }
              info[:status] = 'error'
              next
            end

            r.value_in_cents = new_value
            info[:receipt] = r
          end
        end

        infos
      end

      def parse_receipt(data)

        if data.match(/^\<Ntry/)
          xml = Nokogiri::XML(data)
          xml.remove_namespaces!
          result = nil
          self.parse_xml_entry(xml.xpath("Ntry")) do |h|
            result = h
          end
          result
        else
          self.parse_v11_line(data)
        end

      end

      def parse_v11_file(data)
        # returns a hash of information extracted from the file, resuming
        # as much as possible by merging rectification lines and verifing
        # its checksum in the last line.

        # returned a hash ordered by its keys, looking like
        # {line_number => { :receipt => {receipt_attributes => value},
        #                   :errors => {:line => line, :message => 'message'}}}
        # and with an errors key for general errors

        infos = {}
        infos[:errors] = [] # general errors

        rectifications = {}

        computed_total = 0
        lines = data.split(/[\r\n]+/)

        # Parse every lines execpt the two lasts which are summary/totals
        lines[0..-2].each_with_index do |line, i|
          hash = parse_v11_line(line)

          line_number = i + 1
          infos[line_number] = {:errors => nil, :status => nil} # line specific errors

          begin
            # Check for errors
            ## Ensure line has been parsed
            if hash == 'parsing_line_error'
              raise ParsingError, I18n.t('receipt.import.cannot_parse_line')
            end

            ## Ensure reference number has been parsed
            if hash == 'reference_number_error'
              raise ParsingError, I18n.t('receipt.import.cannot_parse_reference_number')
            end

            ## Verify checksum
            if hash[:valid] == false
              raise ParsingError, I18n.t('receipt.import.checksum_mismatch')
            end

            # Ok, parsing passed
            computed_total += hash[:value_in_cents]

            # Check if owner exists
            unless Person.exists?(hash[:owner_id])
              raise ParsingError, I18n.t('receipt.import.cannot_find_owner', :owner_id => hash[:owner_id])
            end

            # Check if invoice exists
            if Invoice.exists?(hash[:invoice_id])
              invoice = Invoice.find(hash[:invoice_id])
            else
              raise ParsingError, I18n.t('receipt.import.cannot_find_invoice',
                :invoice_id => hash[:invoice_id],
                :owner_id => hash[:owner_id])
            end

            # Some rare case where the invoice is orphan
            unless invoice.affair
              raise ParsingError, I18n.t('receipt.import.cannot_find_affair_for_this_invoice',
                :affair_id => invoice.affair_id,
                :owner_id => hash[:owner_id],
                :invoice_id => invoice.id)
            end

            # Ensure this is the correct invoice
            ## by comparing creation dates
            if hash[:invoice_date] != invoice.created_at.to_date
              raise ParsingError, I18n.t('receipt.import.invoice_found_but_its_creation_date_mismatch')
            end

            ## and owners
            if hash[:owner_id] != invoice.owner.id
              raise ParsingError, I18n.t('receipt.import.invoice_found_but_its_owner_mismatch')
            end

            # Check if this line were previously imported
            if BankImportHistory.where(:reference_line => line.strip).size > 0
              # this line has already been imported
              receipts = invoice.receipts.where(:value_date => hash[:date_value], :value_in_cents => hash[:value_in_cents])
              if receipts.size > 0
                receipt = {:id => receipts.first.id}
                infos[line_number][:status] = 'already_imported'
                raise ParsingError, I18n.t('receipt.import.already_imported')
              else
                infos[line_number][:status] = 'error'
                raise ParsingError, I18n.t('receipt.import.already_imported_but_corresponding_receipt_not_found')
              end
            end

            # Check what kind of line it is, credit, error correction or rectification
            case hash[:type]
            when /\d{2}2/
              # Type 'Credit', considering it the "normal" line
              receipt = { :invoice_id => invoice.id,
                          :value_date => hash[:date_value],
                          :value_in_cents => hash[:value_in_cents] }
              infos[line_number][:status] = 'correct'

            when /\d{2}(4|5)/
              # Type 'Error correction'
              # We have a correction here, it means that another entry will follow
              # containing the real deposit for the receipt
              computed_total -= hash[:value_in_cents]
              rectifications[invoice.id] = hash[:value_in_cents]
              infos[line_number][:status] = 'error_correction'
              next

            when /\d{2}8/
              # Type 'Rectification'
              # This comes after a correction
              # this receipt is actualy the former receipt with its former values
              receipt = { :invoice_id => hash[:invoice_id], :value_in_cents => rectifications[invoice.id] }
              rectifications.delete(invoice.id)
              if receipt.nil?
                # TODO instead of throwing and error, try to find a receipt that was already updated?
                raise ParsingError, I18n.t('receipt.import.cannot_find_receipt')
              end
              receipt[:new_value_in_cents] = hash[:value_in_cents]
              infos[line_number][:status] = 'rectification'

            else
              # Type unknown, compain about it
              raise ParsingError, I18n.t('receipt.import.unknown_type')

            end

          rescue ParsingError => e
            # on custom ParsingError error
            infos[line_number][:errors] = { :message => e.message,
                                            :line => line.strip,
                                            :decoded_line => hash }
            infos[line_number][:status] = 'error' unless infos[line_number][:status]
            next
          ensure
            # in any case, append line and receipt to the hash
            infos[line_number][:receipt] = receipt
            infos[line_number][:line] = line.strip
            infos[line_number][:decoded_line] = hash
          end
        end

        # Starting from here, infos hash has been populated
        # Now checking summary and general errors

        unless rectifications.empty?
          infos[:errors] << I18n.t('receipt.import.correction_without_rectification')
        end

        # Ensure previously read lines and total matches
        matches = lines[-1].match(/^(\d{3})(\d{9})(\d{27})(\d{12})(\d{12})(\d{6})(\d{9})(\d{9})\s*$/)
        if matches.nil?
          infos[:errors] << I18n.t('receipt.import.total_cannot_parse')
        else
          total = matches.captures[3].to_i
          receipts_count = matches.captures[4].to_i
          computed_receipts_count = lines[0..-2].size

          media_date = Date.strptime(matches.captures[5], '%y%m%d')

          if total != computed_total
            infos[:errors] << I18n.t('receipt.import.total_mismatch',
              { :total => total,
                :computed_total => computed_total })
          end

          if receipts_count != computed_receipts_count
            infos[:errors] << I18n.t('receipt.import.total_receipts_count_mismatch',
              { :receipts_count => receipts_count,
                :computed_receipts_count => computed_receipts_count })
          end

          # Summary
          infos[:summary] = { :value_total => total,
                              :receipts_count => receipts_count,
                              :media_date => media_date }
        end

        infos
      end

      def parse_v11_line(line)
        #   012 - 010800837 - 000001090712000001003157008 - 0000000500          - 1158  0400 - 120709      - 120710        - 120711      - 00002002600000000000090
        #  type -  account  - reference number            - Montant en centimes - depot ref  - Date entrée - Date écriture - Date valeur - ?
        matches = line.match(/^(\d{3})(\d{9})(\d{27})(\d{10})(\d{4}.{2}\d{4})(\d{6})(\d{6})(\d{6})(\d{23})\s*$/)
        return 'parsing_line_error' unless matches

        # Parse reference number first which was generated by CIRCL before payment
        # this will add :application_id, :invoice_date, :owner_id, :invoice_id,
        # :digits_available, :modulo and :valid keys to the hash
        hash = Invoice.parse_bvr_reference_number(matches.captures[2])
        return 'reference_number_error' unless hash

        # Then merge its bank information
        hash[:type]           = matches.captures[0]
        hash[:account]        = matches.captures[1]
        hash[:bvr_ref]        = matches.captures[2]
        hash[:value_in_cents] = matches.captures[3].to_i
        hash[:unknown2]       = matches.captures[4]
        hash[:date_entry]     = Date.strptime(matches.captures[5], '%y%m%d')
        hash[:date_write]     = Date.strptime(matches.captures[6], '%y%m%d')
        hash[:date_value]     = Date.strptime(matches.captures[7], '%y%m%d')
        hash[:unknown3]       = matches.captures[8]

        # Add goodies to speed up/ease import/export
        hash[:owner_name]     = Person.where(:id => hash[:owner_id]).first.try(:name)
        hash[:value]          = Money.new(hash[:value_in_cents]).to_view

        hash
      end

      # camt.053
      def parse_xml_file(data)

        infos = {}
        infos[:errors] = [] # general errors
        rectifications = {}
        computed_total = 0

        # Parse XML
        xml = Nokogiri::XML data
        xmlns_base = "urn:iso:std:iso:20022:tech:xsd:"
        xmlns_tail = xml.namespaces['xmlns'].split(xmlns_base).last
        xsd_path = [Rails.root, "/lib/bank_importer/", xmlns_tail, ".xsd"].join

        xsd = Nokogiri::XML::Schema(File.read(xsd_path))

        errors = xsd.validate(xml).map do |error|
          error.message
        end
        raise ArgumentError, errors.inspect if errors.size > 0

        xml.remove_namespaces!

        # Load mapping
        _document          = xml.xpath("Document")
        _group_headers     = _document.xpath("BkToCstmrDbtCdtNtfctn/GrpHdr")
          _creation_date_time = Date.parse _group_headers.xpath("CreDtTm").text
        _notification      = _document.xpath("BkToCstmrDbtCdtNtfctn/Ntfctn")
          _message_id      = _notification.xpath("MsgId")
          _from_to_date    = _notification.xpath("FrToDt")
            _from_datetime = Date.parse _from_to_date.xpath("FrDtTm").text
            _to_datetime   = Date.parse _from_to_date.xpath("ToDtTm").text
            _account       = _notification.xpath("Acct")
            _iban          = _account.xpath("Id/IBAN").text
            _owner         = _account.xpath("Id/Ownr").text

        _balances = _notification.xpath("Bal")
        _opening_booked_amount = nil
        _opening_booked_date = nil
        _closing_booked_amount = nil
        _closing_booked_date = nil
        _balances.each do |balance|
          # Type/CodeOrProprietary/Code
          case balance.xpath("Tp/CdOrPrtry/Cd").text
            when "OPBD"
              _opening_booked_amount = Money.new(balance.xpath("Amt").text.to_f * 100)
              _opening_booked_date   = Date.parse balance.xpath("Dt/Dt").text
            when "CLBD"
              _closing_booked_amount = Money.new(balance.xpath("Amt").text.to_f * 100)
              _closing_booked_date   = Date.parse balance.xpath("Dt/Dt").text
          end
        end

        values_total = transaction_count = 0
        _entries           = _notification.xpath("Ntry")
        entries = []
        _entries.each_with_index do |entry, idx|

          vt, t_cnt = parse_xml_entry(entry) do |h|

            line_number = h[:line_number]
            infos[line_number] = {:errors => nil, :status => nil} # line specific errors

            begin
              # Check for errors

              ## Ensure reference number has been parsed
              if h == 'reference_number_error'
                raise ParsingError, I18n.t('receipt.import.cannot_parse_reference_number')
              end

              ## Verify checksum
              if h[:valid] == false
                raise ParsingError, I18n.t('receipt.import.checksum_mismatch')
              end

              # Ok, parsing passed
              computed_total += h[:value_in_cents]

              # Check if owner exists
              unless Person.exists?(h[:owner_id])
                raise ParsingError, I18n.t('receipt.import.cannot_find_owner', :owner_id => h[:owner_id])
              end

              # Check if invoice exists
              if Invoice.exists?(h[:invoice_id])
                invoice = Invoice.find(h[:invoice_id])
              else
                raise ParsingError, I18n.t('receipt.import.cannot_find_invoice',
                  :invoice_id => h[:invoice_id],
                  :owner_id => h[:owner_id])
              end

              # Some rare case where the invoice is orphan
              unless invoice.affair
                raise ParsingError, I18n.t('receipt.import.cannot_find_affair_for_this_invoice',
                  :affair_id => invoice.affair_id,
                  :owner_id => h[:owner_id],
                  :invoice_id => invoice.id)
              end

              # Ensure this is the correct invoice
              ## by comparing creation dates
              if h[:invoice_date] != invoice.created_at.to_date
                raise ParsingError, I18n.t('receipt.import.invoice_found_but_its_creation_date_mismatch')
              end

              ## and owners
              if h[:owner_id] != invoice.owner.id
                raise ParsingError, I18n.t('receipt.import.invoice_found_but_its_owner_mismatch')
              end

              # Check if this line were previously imported
              if BankImportHistory.where(:account_servicer_reference => line_number).size > 0

                # this line has already been imported
                receipts = invoice.receipts.where(:value_date => h[:date_value],
                  :value_in_cents => h[:value_in_cents])
                if receipts.size > 0
                  receipt = {:id => receipts.first.id}
                  infos[line_number][:status] = 'already_imported'
                  raise ParsingError, I18n.t('receipt.import.already_imported')
                else
                  infos[line_number][:status] = 'error'
                  raise ParsingError, I18n.t('receipt.import.already_imported_but_corresponding_receipt_not_found')
                end
              end

              # Type of transaction is yet not evaluated
              receipt = { :invoice_id => invoice.id,
                          :value_date => h[:date_value],
                          :value_in_cents => h[:value_in_cents] }
              infos[line_number][:status] = 'correct'

            rescue ParsingError => e
              # on custom ParsingError error
              infos[line_number][:errors] = { :message => e.message,
                                              :line => entry.to_s,
                                              :decoded_line => h }
              infos[line_number][:status] = 'error' unless infos[line_number][:status]
              next
            ensure
              # in any case, append line and receipt to the h
              infos[line_number][:receipt] = receipt
              infos[line_number][:line] = entry.to_s
              infos[line_number][:account_servicer_reference] = line_number
              infos[line_number][:decoded_line] = h
            end

          end # /parse_xml_entry

          values_total += vt
          transaction_count += t_cnt

        end

        if values_total != computed_total
          infos[:errors] << I18n.t('receipt.import.total_mismatch',
            { :total => values_total,
              :computed_total => computed_total })
        end

        # Summary
        infos[:summary] = { :value_total => values_total,
                            :receipts_count => transaction_count,
                            :media_date => _creation_date_time }

        infos

      end

      def parse_xml_entry(entry, &block)

        # pre mapping for clarity
        _entry_reference                = entry.xpath("NtryRef").text
        _total_amount                   = Money.new(entry.xpath("Amt").text.to_f * 100)
        _total_credit_debit_indicator   = entry.xpath("CdtDbtInd").text
        _reversal_indicator             = entry.xpath("RvslInd").text
        _status                         = entry.xpath("sts").text
        _booking_date                   = Date.parse entry.xpath("BookgDt/Dt").text
        _value_date                     = Date.parse entry.xpath("ValDt").text
        _account_servicer_reference     = entry.xpath("AcctSvcrRef").text
        _bank_transaction_code          = entry.xpath("BkTxCd")
          _domain                       = _bank_transaction_code.xpath("Domn")
          _domain_code                  = _domain.xpath("Cd").text
          _family                       = _domain.xpath("Fmly")
            _family_code                = _family.xpath("Cd")
            _sub_family_code            = _family.xpath("SubFmlyCd")
        _entry_details                  = entry.xpath("NtryDtls")
          _batch                        = _entry_details.xpath("Btch")
          _number_of_transactions       = _batch.xpath("NbOfTxs").text.try :to_i
          _transaction_details          = _entry_details.xpath("TxDtls")
        _additional_entry_info          = entry.xpath("AddtlNtryInf").text

        _transaction_details.each do |transaction|

          _refs                         = transaction.xpath("Refs")
            _account_servicer_reference = _refs.xpath("AcctSvcrRef").text
            _proprietary                = _refs.xpath("Prtry")
              _type                     = _proprietary.xpath("Tp").try :text
              _reference                = _proprietary.xpath("Ref").try :text
          _amount                       = Money.new(transaction.xpath("Amt").text.to_f * 100)
          _charges                      = transaction.xpath("Chrgs")
            _total_charges_and_tax_amount = Money.new(_charges.xpath("TtlChrgsAndTaxAmt").text.to_f * 100)
            _record                     = _charges.xpath("Rcrd")
            _taxes_amount               = Money.new(_record.xpath("Amt").text.to_f * 100)
            _taxes_included             = _record.xpath("ChargInclInd").try(:text) == "true"
            _taxes_type                 = _record.xpath("Tp/Prtry/Id").try :text
          _isr_structure                = transaction.xpath("RmtInf/Strd")
            _isr_reference              = _isr_structure.xpath("CdtrRefInf/Ref").try :text
            _reject_code                = _isr_structure.xpath("AddtlRmtInf").try :text
          _related_date                 = Date.parse transaction.xpath("RltdDts/AccptncDtTm").text

          # Parse reference number first which was generated by CIRCL before payment
          # this will add :application_id, :invoice_date, :owner_id, :invoice_id,
          # :digits_available, :modulo and :valid keys to the hash
          h = Invoice.parse_bvr_reference_number(_isr_reference)
          return 'reference_number_error' unless h

          # Then merge its bank information
          h[:type]           = 2
          h[:account]        = _entry_reference
          h[:bvr_ref]        = _isr_reference
          h[:value_in_cents] = _amount.cents
          h[:date_entry]     = _booking_date
          h[:date_write]     = _related_date
          h[:date_value]     = _value_date

          # Available only in CAMT.054
          h[:line_number]    = _account_servicer_reference

          # Add goodies to speed up/ease import/export
          h[:owner_name]     = Person.where(:id => h[:owner_id]).first.try(:name)
          h[:value]          = _amount.to_view

          block.call(h)

        end

        [_total_amount.cents, _number_of_transactions]

      end

    end # self

  end # class

end # module