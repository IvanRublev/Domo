defmodule Domo.TypeEnsurerFactory.CleanerTest do
  use Domo.FileCase, async: false

  alias Domo.TypeEnsurerFactory.Cleaner
  alias Domo.MixProject

  test "rm!/1 removes list of paths" do
    path1 = MixProject.out_of_project_tmp_path("/file1.tmp")
    path2 = MixProject.out_of_project_tmp_path("/file2.tmp")

    File.write!(path1, "")
    File.write!(path2, "")

    assert File.exists?(path1)
    assert File.exists?(path2)

    assert :ok = Cleaner.rm!([path1, path2])

    refute File.exists?(path1)
    refute File.exists?(path2)
  end

  test "rmdir_if_needed/1 removes the directory if it exists" do
    dir_path = MixProject.out_of_project_tmp_path("/#{to_string(__MODULE__)}/")
    File.mkdir_p!(dir_path)
    File.write!(Path.join(dir_path, "/file.tmp"), "")

    assert File.exists?(dir_path)

    assert :ok == Cleaner.rmdir_if_exists!(dir_path)

    refute File.exists?(dir_path)

    nonexisting_dir_path = MixProject.out_of_project_tmp_path("/nonexisting/")
    refute File.exists?(nonexisting_dir_path)

    assert :ok == Cleaner.rmdir_if_exists!(nonexisting_dir_path)
  end
end
