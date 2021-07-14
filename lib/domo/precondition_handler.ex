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
        message =
          apply(ErrorBuilder, :build_error, [
            opts[:spec_string],
            [precond_description: opts[:precond_description], precond_type: opts[:precond_type]]
          ])

        {:error, opts[:value], [message]}

      {:error, message} ->
        {:error, opts[:value], [{:bypass, message}]}

      _ ->
        raise "precond function defined for #{opts[:precond_type]} type should return true | false | :ok | {:error, any()} value"
    end
  end
end
