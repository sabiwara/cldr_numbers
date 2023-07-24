defmodule Cldr.Number.Format.Options do
  @moduledoc """
  Functions to validate and transform
  options that guide number formatting
  """

  alias Cldr.Number.{System, Symbol, Format}
  alias Cldr.Number.Format.Compiler
  alias Cldr.Currency
  alias Cldr.LanguageTag

  import DigitalToken, only: :macros

  # These are the options set in the
  # struct guide formatting
  @options [
    :locale,
    :number_system,
    :currency,
    :format,
    :currency_format,
    :currency_digits,
    :currency_spacing,
    :currency_symbol,
    :symbols,
    :minimum_grouping_digits,
    :pattern,
    :rounding_mode,
    :fractional_digits,
    :maximum_integer_digits,
    :round_nearest,
    :wrapper
  ]

  # These are the options that can be supplied
  # through the api
  @valid_options @options --
                   ([:currency_spacing, :pattern] ++ [:cash])

  @short_format_styles [
    :currency_short,
    :currency_long_with_symbol,
    :currency_long,
    :decimal_short,
    :decimal_long
  ]

  @rounding_modes [
    :down,
    :half_up,
    :half_even,
    :ceiling,
    :floor,
    :half_down,
    :up
  ]

  @standard_formats [
    :standard,
    :accounting,
    :currency,
    :scientific,
    :percent,
    :currency_no_symbol,
    :accounting_no_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  @currency_formats_requiring_a_currency [
    :currency_long,
    :currency_long_with_symbol,
    :currency_short,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  @currency_symbol [
    :standard,
    :iso,
    :narrow,
    :symbol
  ]

  @type fixed_formats :: :standard | :currency | :accounting | :short | :long
  @type format :: binary() | fixed_formats()
  @type currency_symbol :: :standard | :iso
  @type short_format_styles ::
          :currency_short
          | :currency_long
          | :currency_long_with_symbol
          | :decimal_short
          | :decimal_long

  @type t :: %__MODULE__{
          locale: LanguageTag.t(),
          number_system: System.system_name(),
          currency: Currency.t() | :from_locale,
          format: format(),
          currency_format: :currency | :accounting,
          currency_digits: pos_integer(),
          currency_spacing: map(),
          symbols: Symbol.t(),
          minimum_grouping_digits: pos_integer(),
          pattern: String.t(),
          rounding_mode: Decimal.rounding(),
          fractional_digits: pos_integer(),
          maximum_integer_digits: pos_integer(),
          round_nearest: pos_integer(),
          wrapper: (String.t(), atom -> String.t())
        }

  defstruct @options

  @spec validate_options(Cldr.Math.number_or_decimal(), Cldr.backend(), list({atom, term})) ::
          {:ok, t} | {:error, {module(), String.t()}}

  def validate_options(number, backend, options) do
    with {:ok, options} <- ensure_only_valid_keys(@valid_options, options),
         {:ok, backend} <- Cldr.validate_backend(backend) do
      options =
        Module.concat(backend, Number).default_options()
        |> Keyword.merge(options)
        |> Map.new()

      options
      |> validate_each_option(backend)
      |> confirm_currency_format_has_currency()
      |> maybe_adjust_currency_format(options.currency, options.format)
      |> resolve_standard_format(backend)
      |> maybe_expand_currency_symbol(number)
      |> maybe_apply_alpha_next_to_number(backend)
      |> set_pattern(number)
      |> structify(__MODULE__)
      |> wrap_ok()
    end
  end

  defp validate_each_option(options, backend) do
    Enum.reduce_while(@options, options, fn option, options ->
      case validate_option(option, options, backend, Map.get(options, option)) do
        {:ok, result} -> {:cont, Map.put(options, option, result)}
        {:error, _} = error -> {:halt, error}
      end
    end)
  end

  defp wrap_ok(%__MODULE__{} = options) do
    {:ok, options}
  end

  defp wrap_ok(other) do
    other
  end

  # TODO for ex_cldr_numbers 3.0
  defp ensure_only_valid_keys(_valid_options, options) do
    {:ok, options}
  end

  # def ensure_only_valid_keys(valid_options, options) do
  #   option_keys = Keyword.keys(options)
  #
  #   if (invalid = (option_keys -- valid_options)) == [] do
  #     {:ok, options}
  #   else
  #     {:error, {ArgumentError, "Invalid options found: #{inspect invalid}"}}
  #   end
  # end

  # If the format is :narrow and we have a currency then we set the currency_symbol to
  # :narrow, the format to :currency

  @doc false
  defp maybe_adjust_currency_format(options, currency, :narrow) when not is_nil(currency) do
    currency_format = derive_currency_format(options)

    options
    |> Map.put(:currency_symbol, :narrow)
    |> Map.put(:format, currency_format)
    |> Map.put(:currency_format, currency_format)
  end

  # We keep a record of whether the currency format is :currency or :accounting
  # because later on we may need to adjust the "alpha_next_to_number" format

  defp maybe_adjust_currency_format(%{format: format} = options, currency, _)
       when not is_nil(currency) and format in [:accounting, :currency] do
    Map.put(options, :currency_format, options.format)
  end

  defp maybe_adjust_currency_format(options, _currency, _format) do
    options
  end

  # As of CLDR 42 there is a format for a currency that excludes the
  # currency symbol.

  @doc false
  def resolve_standard_format(%{format: :currency, currency: nil} = options, backend) do
    options = Map.put(options, :format, :currency_no_symbol)
    resolve_standard_format(options, backend)
  end

  def resolve_standard_format(%{format: :accounting, currency: nil} = options, backend) do
    options = Map.put(options, :format, :accounting_no_symbol)
    resolve_standard_format(options, backend)
  end

  def resolve_standard_format(%{format: format} = options, backend)
      when format in @standard_formats do
    locale = Map.fetch!(options, :locale)
    number_system = Map.fetch!(options, :number_system)

    with {:ok, formats} <- Format.formats_for(locale, number_system, backend),
         {:ok, resolved_format} <- get_standard_format(formats, format, locale, number_system) do
      Map.put(options, :format, resolved_format)
    end
  end

  def resolve_standard_format(other, _backend) do
    other
  end

  def get_standard_format(formats, format, locale, number_system) do
    case Map.fetch(formats, format) do
      {:ok, nil} ->
        {:error,
         {Cldr.UnknownFormatError,
          "The locale #{inspect(Map.fetch!(locale, :cldr_locale_name))} " <>
            "with number system #{inspect(number_system)} " <>
            "does not define a format #{inspect(format)}"}}

      {:ok, format} ->
        {:ok, format}
    end
  end

  @currency_placeholder Compiler.placeholder(:currency)
  #  @iso_placeholder Compiler.placeholder(:currency) <> Compiler.placeholder(:currency)

  defp confirm_currency_format_has_currency(%{format: format, currency: nil} = options)
       when is_binary(format) do
    if String.contains?(format, @currency_placeholder) do
      {:error,
       {Cldr.FormatError,
        "currency format #{inspect(format)} requires that " <>
          "options[:currency] be specified"}}
    else
      options
    end
  end

  defp confirm_currency_format_has_currency(other) do
    other
  end

  # From TR35
  # The alt="alphaNextToNumber" pattern, if available, should be used instead of the standard
  # pattern when the currency symbol character closest to the numeric value has Unicode General
  # Category L (letter). The alt="alphaNextToNumber" pattern is typically provided when the
  # standard currency pattern does not have a space between currency symbol and numeric value; the
  # alphaNextToNumber variant adds a non-breaking space if appropriate for the locale.

  defp maybe_apply_alpha_next_to_number(%{currency_format: currency_format} = options, backend)
       when currency_format in [:currency, :accounting] do
    cond do
      String.starts_with?(options.format, @currency_placeholder) &&
          Regex.match?(~r/\p{L}$/u, options.currency_symbol) ->
        resolve_alpha_next_to_number(options, backend)

      String.ends_with?(options.format, @currency_placeholder) &&
          Regex.match?(~r/^\p{L}/u, options.currency_symbol) ->
        resolve_alpha_next_to_number(options, backend)

      true ->
        options
    end
  end

  defp maybe_apply_alpha_next_to_number(options, _backend) do
    options
  end

  # If we resolve an :currency_alpha_next_to_number format then
  # we set :currency_spacing to nil so it doesn't need to be evaluated

  defp resolve_alpha_next_to_number(options, backend) do
    format =
      if options.currency_format == :accounting,
        do: :accounting_alpha_next_to_number,
        else: :currency_alpha_next_to_number

    resolve_options = Map.put(options, :format, format)

    case resolve_standard_format(resolve_options, backend) do
      {:error, _} ->
        options

      resolved_options ->
        options
        |> Map.put(:format, resolved_options.format)
        |> Map.put(:currency_spacing, nil)
    end
  end

  defp set_pattern(options, number) when is_map(options) and is_number(number) and number < 0 do
    Map.put(options, :pattern, :negative)
  end

  defp set_pattern(options, %Decimal{sign: sign}) when is_map(options) and sign < 0 do
    Map.put(options, :pattern, :negative)
  end

  defp set_pattern(options, _number) when is_map(options) do
    Map.put(options, :pattern, :positive)
  end

  defp set_pattern(other, _number) do
    other
  end

  defp structify(options, module) when is_map(options) do
    struct(module, options)
  end

  defp structify(other, _module) do
    other
  end

  # Validate each option separately

  defp validate_option(:locale, _options, backend, nil) do
    {:ok, backend.get_locale()}
  end

  defp validate_option(:locale, _options, backend, locale) do
    with {:ok, locale} <- Cldr.validate_locale(locale, backend) do
      {:ok, locale}
    end
  end

  # Number system is extracted from the locale
  defp validate_option(:number_system, options, backend, number_system)
       when is_nil(number_system) or number_system == :default do
    number_system =
      options
      |> Map.fetch!(:locale)
      |> System.number_system_from_locale(backend)

    {:ok, number_system}
  end

  defp validate_option(:number_system, options, backend, number_system) do
    locale = Map.fetch!(options, :locale)
    System.system_name_from(number_system, locale, backend)
  end

  # Currency validation returns a t: Cldr.Currency.t/0

  defp validate_option(:currency, %{locale: locale}, backend, :from_locale) do
    currency_from_locale(locale, backend)
  end

  defp validate_option(:currency, %{format: format, locale: locale}, backend, nil)
       when format in @currency_formats_requiring_a_currency do
    currency_from_locale(locale, backend)
  end

  defp validate_option(:currency, %{format: format, locale: locale}, backend, nil)
       when is_binary(format) do
    if String.contains?(format, @currency_placeholder) do
      currency_from_locale(locale, backend)
    else
      {:ok, nil}
    end
  end

  defp validate_option(:currency, _options, _backend, nil) do
    {:ok, nil}
  end

  defp validate_option(:currency, _options, _backend, %Cldr.Currency{} = currency) do
    {:ok, currency}
  end

  defp validate_option(:currency, options, backend, currency) do
    with {:ok, currency_code} <- Cldr.validate_currency(currency),
         {:ok, currency} <-
           Cldr.Currency.currency_for_code(currency_code, backend, locale: options.locale) do
      {:ok, currency}
    else
      {:error, _} ->
        case DigitalToken.validate_token(currency) do
          {:ok, token} -> {:ok, token}
          {:error, _} -> {:error, Cldr.unknown_currency_error(currency)}
        end
    end
  end

  # If a currency code is provided but no format then a currency
  # format is forced.

  defp validate_option(:format, options, backend, nil) do
    locale = Map.fetch!(options, :locale)

    if Map.fetch!(options, :currency) do
      {:ok, derive_currency_format(backend, locale)}
    else
      {:ok, :standard}
    end
  end

  # If its a short format and a currency is provided then
  # force a currency short format

  defp validate_option(:format, options, _backend, :short) do
    if Map.get(options, :currency) do
      {:ok, :currency_short}
    else
      {:ok, :decimal_short}
    end
  end

  # If its a long format and a currency is provided then
  # force a currency long format

  defp validate_option(:format, options, _backend, :long) do
    if Map.get(options, :currency) do
      {:ok, :currency_long}
    else
      {:ok, :decimal_long}
    end
  end

  @exclude_formats [
    :currency,
    :accounting,
    :currency_short,
    :currency_long,
    :currency_long_with_symbol,
    :currency_alpha_next_to_number,
    :accounting_alpha_next_to_number
  ]

  # If a currency is specified with a non-currency format
  # then derive a currency format from the locale.

  defp validate_option(:format, options, _backend, format)
       when is_atom(format) and format not in @exclude_formats do
    if Map.get(options, :currency) do
      {:ok, derive_currency_format(options)}
    else
      {:ok, format}
    end
  end

  defp validate_option(:format, _options, _backend, format) do
    {:ok, format}
  end

  # Currency digits is an opaque option that is a proxy
  # for the `:cash` parameter which is set to true or false

  defp validate_option(:currency_digits, options, _backend, _currency_digits) do
    if Map.get(options, :cash) do
      {:ok, :cash}
    else
      {:ok, :accounting}
    end
  end

  # :currency_format isn't really a user specified option (it is set
  # based upon :format) but we validate anyway.

  defp validate_option(:currency_format, _options, _backend, currency_format)
       when currency_format in [:currency, :accounting, nil] do
    {:ok, currency_format}
  end

  defp validate_option(:currency_format, _options, _backend, currency_format) do
    {:error, "Invalid :currency_format: #{inspect(currency_format)}"}
  end

  # Currency spacing isn't really a user option
  # Its derived for currency formats only.

  defp validate_option(:currency_spacing, %{format: format} = options, backend, _spacing)
       when format in [:currency, :accounting, :currency_short] do
    locale = Map.fetch!(options, :locale)
    number_system = Map.fetch!(options, :number_system)
    module = Module.concat(backend, Number.Format)

    {:ok, module.currency_spacing(locale, number_system)}
  end

  defp validate_option(:currency_spacing, _options, _backend, _currency_spacing) do
    {:ok, nil}
  end

  defp validate_option(:currency_symbol, _options, _backend, nil) do
    {:ok, nil}
  end

  defp validate_option(:currency_symbol, _options, _backend, currency_symbol)
       when currency_symbol in @currency_symbol do
    {:ok, currency_symbol}
  end

  defp validate_option(:currency_symbol, _options, _backend, currency_symbol)
       when is_binary(currency_symbol) do
    {:ok, currency_symbol}
  end

  defp validate_option(:currency_symbol, _options, _backend, other) do
    {:error,
     {ArgumentError,
      ":currency_symbol must be :standard, :iso, :narrow, :symbol, " <>
        "a string or nil. Found #{inspect(other)}"}}
  end

  defp validate_option(:symbols, options, backend, _any) do
    locale = Map.fetch!(options, :locale)
    number_system = Map.fetch!(options, :number_system)

    case Symbol.number_symbols_for(locale, number_system, backend) do
      {:ok, symbols} -> {:ok, symbols}
      _other -> {:ok, nil}
    end
  end

  defp validate_option(:wrapper, _options, _backend, wrapper)
       when is_nil(wrapper) or is_function(wrapper, 2) do
    {:ok, wrapper}
  end

  defp validate_option(:minimum_grouping_digits, _options, _backend, nil) do
    {:ok, 0}
  end

  defp validate_option(:minimum_grouping_digits, _options, _backend, int)
       when is_integer(int) and int >= 0 do
    {:ok, int}
  end

  defp validate_option(:minimum_grouping_digits, _options, _backend, other) do
    {:error,
     {ArgumentError,
      ":minimum_grouping_digits must be a positive integer or nil. Found #{inspect(other)}"}}
  end

  defp validate_option(:fractional_digits, _options, _backend, nil) do
    {:ok, nil}
  end

  defp validate_option(:fractional_digits, _options, _backend, int)
       when is_integer(int) and int >= 0 do
    {:ok, int}
  end

  defp validate_option(:fractional_digits, _options, _backend, other) do
    {:error,
     {ArgumentError,
      ":fractional_digits must be a an integer >= 0 or nil. Found #{inspect(other)}"}}
  end

  defp validate_option(:maximum_integer_digits, _options, _backend, nil) do
    {:ok, nil}
  end

  defp validate_option(:maximum_integer_digits, _options, _backend, int)
       when is_integer(int) and int >= 0 do
    {:ok, int}
  end

  defp validate_option(:maximum_integer_digits, _options, _backend, other) do
    {:error,
     {ArgumentError,
      ":maximum_integer_digits must be a an integer >= 0 or nil. Found #{inspect(other)}"}}
  end

  defp validate_option(:round_nearest, _options, _backend, nil) do
    {:ok, nil}
  end

  defp validate_option(:round_nearest, _options, _backend, int)
       when is_integer(int) and int > 0 do
    {:ok, int}
  end

  defp validate_option(:round_nearest, _options, _backend, other) do
    {:error,
     {ArgumentError, ":round_nearest must be a positive integer or nil. Found #{inspect(other)}"}}
  end

  defp validate_option(:rounding_mode, _options, _backend, nil) do
    {:ok, :half_even}
  end

  defp validate_option(:rounding_mode, _options, _backend, rounding_mode)
       when rounding_mode in @rounding_modes do
    {:ok, rounding_mode}
  end

  defp validate_option(:rounding_mode, _options, _backend, other) do
    {:error,
     {ArgumentError,
      ":rounding_mode must be one of #{inspect(@rounding_modes)}. Found #{inspect(other)}"}}
  end

  defp validate_option(:pattern, _options, _backend, _pattern) do
    {:ok, nil}
  end

  # When no format is requested but a currency is then we derive
  # the currency format which will be either :currency or :accounting

  defp derive_currency_format(%Cldr.LanguageTag{backend: backend} = locale) do
    derive_currency_format(backend, locale)
  end

  defp derive_currency_format(%{locale: locale}) do
    derive_currency_format(locale)
  end

  defp derive_currency_format(backend, locale) do
    default_currency_format = Map.get(backend.__cldr__(:config), :default_currency_format)

    if default_currency_format do
      default_currency_format
    else
      Currency.currency_format_from_locale(locale)
    end
  end

  # Returns a Cldr.Currency.t from a locale and backend
  defp currency_from_locale(locale, backend) do
    with currency_code when is_atom(currency_code) <- Cldr.Currency.currency_from_locale(locale),
         {:ok, currency} <-
           Cldr.Currency.currency_for_code(currency_code, backend, locale: locale) do
      {:ok, currency}
    end
  end

  @doc false
  @spec short_format_styles() :: list(atom())
  def short_format_styles do
    @short_format_styles
  end

  # # Sometimes we want the standard format for a currency but we want the
  # # ISO code instead of the currency symbol
  #
  # @doc false
  # def maybe_adjust_currency_symbol(%{format: format} = options, :iso) when is_binary(format) do
  #   format = String.replace(format, @currency_placeholder, @iso_placeholder)
  #   Map.put(options, :format, format)
  # end
  #
  # def maybe_adjust_currency_symbol(options, _currency_symbol) do
  #   options.format
  # end

  # Expand the currency symbol from its atom code to
  # the actual symbole. This replaces :narrow, :iso and
  # so on with the actual symbol

  @doc false
  def maybe_expand_currency_symbol(%{currency: %Currency{}, format: format} = options, number)
      when is_binary(format) do
    expand_currency_symbol(options, number)
  end

  def maybe_expand_currency_symbol(%{currency: currency, format: format} = options, number)
      when is_digital_token(currency) and is_binary(format) do
    expand_currency_symbol(options, number)
  end

  def maybe_expand_currency_symbol(options, _number) do
    options
  end

  defp expand_currency_symbol(%{currency: currency, format: format} = options, number) do
    backend = options.locale.backend

    size =
      Module.concat(backend, Number.Formatter.Decimal).metadata!(format).currency.symbol_count

    symbol =
      currency_symbol(currency, options.currency_symbol, number, size, options.locale, backend)

    Map.put(options, :currency_symbol, symbol)
  end

  # Extract the appropriate currency symbol based upon how many currency
  # placeholders are in the format as follows:
  #   ¤      Standard currency symbol
  #   ¤¤     ISO currency symbol (constant)
  #   ¤¤¤    Appropriate currency display name for the currency, based on the
  #          plural rules in effect for the locale
  #   ¤¤¤¤   Narrow currency symbol.
  #
  # Can also be forced to :narrow, :symbol, :iso or a string

  @doc false
  def currency_symbol(%Currency{} = currency, :narrow, _number, _size, _locale, _backend) do
    currency.narrow_symbol || currency.symbol
  end

  def currency_symbol(%Currency{} = currency, :symbol, _number, _size, _locale, _backend) do
    currency.symbol
  end

  def currency_symbol(%Currency{} = currency, :iso, _number, _size, _locale, _backend) do
    currency.code
  end

  def currency_symbol(%Currency{} = _currency, symbol, _number, _size, _locale, _backend)
      when is_binary(symbol) do
    symbol
  end

  def currency_symbol(%Currency{} = currency, _symbol, _number, 1, _locale, _backend) do
    currency.symbol
  end

  def currency_symbol(%Currency{} = currency, _symbol, _number, 2, _locale, _backend) do
    currency.code
  end

  def currency_symbol(%Currency{} = currency, _symbol, number, 3, locale, backend) do
    Module.concat(backend, Number.Cardinal).pluralize(number, locale, currency.count)
  end

  def currency_symbol(%Currency{} = currency, _symbol, _number, 4, _locale, _backend) do
    currency.narrow_symbol || currency.symbol
  end

  def currency_symbol(digital_token, :iso, _number, _size, _locale, _backend)
      when is_digital_token(digital_token) do
    {:ok, token} = DigitalToken.get_token(digital_token)
    hd(token.informative.short_names)
  end

  def currency_symbol(digital_token, symbol, _number, _size, _locale, _backend)
      when is_digital_token(digital_token) and is_binary(symbol) do
    symbol
  end

  def currency_symbol(digital_token, _symbol, _number, size, _locale, _backend)
      when is_digital_token(digital_token) do
    {:ok, symbol} = DigitalToken.symbol(digital_token, size)
    symbol
  end

  # ========= This is here for compatibility and needs review =========

  @doc false
  def validate_other_format(other_type, backend, options) do
    format_module = Module.concat(backend, Number.Format)

    with {:ok, formats} <- format_module.formats_for(options.locale, options.number_system) do
      if format = Map.get(formats.other, other_type) do
        {:ok, format}
      else
        locale_name = options.locale.cldr_locale_name

        {
          :error,
          {
            Cldr.UnknownFormatError,
            "The locale #{inspect(locale_name)} with number system " <>
              "#{inspect(options[:number_system])} does not define a format " <>
              "#{inspect(other_type)}."
          }
        }
      end
    end
  end
end
