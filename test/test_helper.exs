test_structs_path = Application.fetch_env!(:domo, :test_structs_path)

{output, code} = System.cmd("mix", ["compile"], cd: test_structs_path, env: [{"MIX_ENV", "test"}])

unless code == 0 do
  raise output
end

build_path =
  Mix.Project.in_project(:test_struct_modules, test_structs_path, fn _module ->
    Mix.Project.build_path()
  end)

struct_beams_path = Path.join([build_path, "lib", "test_struct_modules", "ebin"])
domo_beams_path = Path.join([Mix.Project.build_path(), "lib", "domo", "ebin"])

struct_beams_path
|> File.ls!()
|> Enum.filter(&(&1 |> String.downcase() |> String.ends_with?(".beam")))
|> Enum.each(fn file_name ->
  module_name =
    file_name
    |> String.split(".")
    |> List.delete_at(-1)
    |> Enum.join(".")
    |> String.to_atom()

  src_path = Path.join([struct_beams_path, file_name])
  dst_path = Path.join([domo_beams_path, file_name])

  src_stat = File.lstat!(src_path).size
  dst_stat = if File.exists?(dst_path), do: File.lstat!(dst_path).size

  if src_stat != dst_stat do
    File.cp!(src_path, dst_path)
    IO.puts(module_name)
  end

  :ok == Code.ensure_loaded(module_name)
end)

ExUnit.start()
