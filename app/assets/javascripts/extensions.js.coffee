##################
### PROTOTYPING ##
##################

# very simple humanize method...
String.prototype.humanize = ->
  string = @
  string = string.replace(/_/g, " ")
  string = string.substring(0, 1).toUpperCase() + string.substring(1)
  string

Array.prototype.to_property = ->
  hash = {}
  hash[@[0]] = @[1]
  hash

Number.prototype.to_view = (currency = null)->
    # this defines currency precision - decimals
    num = @
    negative = num < 0

    num = Math.abs num

    defaults = JSON.parse App.ApplicationSetting.value("default_currency_details")
    thousands_separator = defaults.separator
    decimal_mark = defaults.delimiter
    precision = (defaults.subunit_to_unit + "").match(/0+/)[0].length

    money = num.toFixed(precision)

    # Format money corresponding to currency configuration
    if num >= 1000
      # split the fixed in two
      a = String(money).match(/^(\d+)(.\d{2})$/)
      integers = a[1]
      decimals = a[2]

      # test the length and save remains of the modulo of three
      remaining_digits_length = integers.length % 3
      remaining_digits = integers.slice(0,remaining_digits_length) # from the begining to the index
      thousands = integers.slice(remaining_digits_length) # from the index to the end

      if thousands.length > 3
        thousands = thousands.match(/\d{3}/g)
      else
        thousands = [thousands]

      thousands.splice(0,0,remaining_digits) if remaining_digits_length > 0
      integers_with_separators = thousands.join(thousands_separator)

      money = integers_with_separators + decimals

    if currency
      if c = App.Currency.findByAttribute("iso_code", currency)
        money += " " + c.symbol

    money = "-" + money if negative

    return money # as a string

Number.prototype.pad = (length) ->
  str = @ + ""
  while (str.length < length)
    str = "0" + str;
  str.substring(0,2)

# If I dared to write somewhere how javascript sucks that would be here.
Date.prototype.to_view = (date)->
  # TODO localization, check also the rest of the code for localization
  @.getDate().pad(2) + "-" + (@.getMonth() + 1).pad(2) + "-" + @.getFullYear()

String.prototype.to_date = ->
  ary = @.split("-").reverse()
  new Date(parseInt(ary[0]), parseInt(ary[1]) - 1, parseInt(ary[2]))
