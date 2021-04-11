defmodule Domo.TypeEnsurerFactory.Cleaner do
  @moduledoc false

  def rm!(files) do
    Enum.each(files, &File.rm!(&1))
  end

  def rmdir_if_exists!(path) do
    if File.exists?(path) do
      File.rm_rf!(path)
    end

    :ok
  end
end
