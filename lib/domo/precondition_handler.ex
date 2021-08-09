defmodule Domo.PreconditionHandler do
  @moduledoc false

  alias Domo.ErrorBuilder

  def cast_to_ok_error(precond_result, opts) do
    case precond_result do
      true ->
        :ok

      :ok ->
        :ok

      false ->
        message = apply(ErrorBuilder, :build_precond_field_error, [opts])
        {:error, opts[:value], [message]}

      {:error, message} ->
        wraped_message = apply(ErrorBuilder, :build_precond_type_error, [message])
        {:error, opts[:value], [wraped_message]}

      _ ->
        raise "precond function defined for #{opts[:precond_type]} type should return true | false | :ok | {:error, any()} value"
    end
  end
end
