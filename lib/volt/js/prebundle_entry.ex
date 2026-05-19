defmodule Volt.JS.PrebundleEntry do
  @moduledoc false

  def source({:proxy, _filename, opts}) do
    code =
      opts
      |> Keyword.get(:imports, [])
      |> Enum.map(&import_statement/1)
      |> Enum.intersperse("\n")
      |> append_lines(export_statements(Keyword.get(opts, :exports, [])))

    case OXC.parse!(code, "prebundle-entry.js") do
      _ast -> code
    end
  end

  defp import_statement(%{default: name, from: specifier}) do
    "import #{identifier!(name)} from #{literal!(specifier)};"
  end

  defp export_statements(exports) do
    Enum.map(exports, fn
      %{default: expression} ->
        "export default #{expression!(expression)};"

      %{members: members} ->
        members
        |> Enum.map(fn {name, expression} ->
          ["export const ", identifier!(name), " = ", expression!(expression), ";"]
        end)
        |> Enum.intersperse("\n")

      %{named_from: specifier, names: names} ->
        names = names |> Enum.map(&export_name!/1) |> Enum.intersperse(", ")
        ["export { ", names, " } from ", literal!(specifier), ";"]

      %{all_from: specifier} ->
        "export * from #{literal!(specifier)};"
    end)
  end

  defp append_lines([], lines), do: IO.iodata_to_binary([join_lines(lines), "\n"])

  defp append_lines(prefix, lines),
    do: IO.iodata_to_binary([prefix, "\n", join_lines(lines), "\n"])

  defp join_lines(lines), do: Enum.intersperse(lines, "\n")

  defp export_name!({name, as}) do
    "#{identifier!(name)} as #{identifier!(as)}"
  end

  defp export_name!(name), do: identifier!(name)

  defp identifier!(name) when is_binary(name) do
    if Regex.match?(~r/^[A-Za-z_$][A-Za-z0-9_$]*$/, name) do
      name
    else
      raise ArgumentError, "invalid JavaScript identifier: #{inspect(name)}"
    end
  end

  defp literal!(value) when is_binary(value) do
    :json.encode(value)
  end

  defp expression!(expression) when is_binary(expression) do
    OXC.parse!("const __volt_expression = #{expression};", "prebundle-expression.js")
    expression
  end
end
