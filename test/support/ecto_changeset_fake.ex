defmodule Ecto.Changeset do
  @moduledoc false

  def validate_change(changeset, _field, _fun), do: changeset
  def validate_required(changeset, _fields, _opts \\ []), do: changeset
  def add_error(changeset, _key, _message, _keys \\ []), do: changeset
  def apply_changes(changeset), do: changeset.data
end
