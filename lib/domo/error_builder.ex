defmodule Domo.ErrorBuilder do
  @moduledoc false

  def build_error(spec_string, [precond_description: _description, precond_type: _type_string] = opts) do
    {template, keywords} = build_error(spec_string, nil)

    template =
      template <>
        " And a true value from the precondition" <>
        " function \"%{precond_description}\" defined for %{precond_type} type."

    keywords = Keyword.merge(keywords, opts)

    {template, keywords}
  end

  def build_error(spec_string, nil) do
    {"Expected the value matching the %{type} type.", type: spec_string}
  end

  def pretty_error_by_key({:error, {_, _, field, _, _, _}} = error) do
    {field || :t, pretty_error(error)}
  end

  def pretty_error({:error, {:type_mismatch, _struct_module, _field, _value, _expected_types, {:bypass, message}}}) do
    message
  end

  def pretty_error({:error, {:type_mismatch, struct_module, field, value, _expected_types, [single_error_template]}}) do
    invalid_value = invalid_value_message(value, field, struct_module)
    general_error_string = general_error_message(single_error_template)

    "#{invalid_value} #{general_error_string}"
  end

  def pretty_error({:error, {:type_mismatch, struct_module, field, value, expected_types, error_templates}}) do
    top_level_error = generate_top_level_error(expected_types)
    underlying_errors = collect_deepest_underlying_errors(error_templates)

    invalid_value = invalid_value_message(value, field, struct_module)
    general_error_string = general_error_message(top_level_error)
    underlying_errors_string = underlying_errors_message(underlying_errors)

    "#{invalid_value} #{general_error_string}#{underlying_errors_string}"
  end

  defp generate_top_level_error(expected_types) do
    expected_types
    |> Enum.join(" | ")
    |> build_error(nil)
  end

  defp collect_deepest_underlying_errors([[_ | _] | _] = error_or_templates) do
    error_by_count =
      error_or_templates
      |> Enum.reduce([], fn list, templates_and_length ->
        updated_list = maybe_drop_top_level_error(list)

        if match?([], updated_list) do
          templates_and_length
        else
          [{updated_list, Enum.count(updated_list)} | templates_and_length]
        end
      end)
      |> Enum.reverse()

    max_length =
      error_by_count
      |> Enum.map(fn {_list, length} -> length end)
      |> Enum.max(&>=/2, fn -> 0 end)

    error_by_count
    |> Enum.filter(fn {_list, length} -> length == max_length end)
    |> Enum.map(fn {list, _length} -> list end)
  end

  defp collect_deepest_underlying_errors(error_templates) do
    error_templates
  end

  defp maybe_drop_top_level_error(list) do
    first_error = hd(list)
    {_template, args} = first_error

    if match?([type: _], args) do
      tl(list)
    else
      list
    end
  end

  defp invalid_value_message(value, nil = _field, _struct_module) do
    "Invalid value #{inspect(value)}."
  end

  defp invalid_value_message(value, field, struct_module) do
    "Invalid value #{inspect(value)} for field #{inspect(field)} of %#{inspect(struct_module)}{}."
  end

  defp general_error_message({template, args} = _error) do
    interpolate_error_template(template, args)
  end

  defp underlying_errors_message([[_ | _] | _] = error_or_groups) do
    lines =
      error_or_groups
      |> Enum.map(&interpolate_first_indent/1)
      |> List.flatten()

    ["\nUnderlying errors:"]
    |> Enum.concat(lines)
    |> Enum.join("\n")
  end

  defp underlying_errors_message([_ | _] = errors) do
    lines =
      errors
      |> interpolate_indent_unerlying()

    ["\nUnderlying errors:"]
    |> Enum.concat(lines)
    |> Enum.join("\n")
  end

  defp underlying_errors_message(_errors), do: nil

  defp interpolate_first_indent(errors) do
    errors
    |> Enum.with_index()
    |> Enum.map(fn {{template, args}, level} ->
      String.duplicate("  ", Enum.min([level, 1])) <> "   - " <> interpolate_error_template(template, args)
    end)
  end

  defp interpolate_error_template(template, args) do
    Enum.reduce(args, template, fn {key, value}, template ->
      string = if is_nil(value), do: "nil", else: to_string(value)
      String.replace(template, "%{#{key}}", string)
    end)
  end

  defp interpolate_indent_unerlying(errors) do
    Enum.map(errors, fn {template, args} ->
      updated_args = maybe_indent_underlying(args)
      "   - " <> interpolate_error_template(template, updated_args)
    end)
  end

  defp maybe_indent_underlying([error: error] = args) do
    parts = String.split(error, "\nUnderlying errors:\n", parts: 2)

    if Enum.count(parts) == 2 do
      shifted_underlying =
        parts
        |> Enum.at(1)
        |> String.split("\n")
        |> Enum.map(&("  " <> &1))
        |> Enum.join("\n")

      [error: Enum.join(["the following:", shifted_underlying], "\n")]
    else
      args
    end
  end

  defp maybe_indent_underlying(args) do
    args
  end
end
