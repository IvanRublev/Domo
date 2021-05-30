defmodule AvialiaWeb.ErrorHelpers do
  @moduledoc """
  Conveniences for translating and building error messages.
  """

  use Phoenix.HTML

  @doc """
  Generates tag for inlined form input errors.
  """
  def error_tag(form, field) do
    Enum.map(Keyword.get_values(form.errors, field), fn error ->
      content_tag(:span, error,
        class: "invalid-feedback",
        phx_feedback_for: input_name(form, field)
      )
    end)
  end
end
