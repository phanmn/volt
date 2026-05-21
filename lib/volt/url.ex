defmodule Volt.URL do
  @moduledoc false

  def join(prefix, path) do
    prefix = to_string(prefix)
    path = "/" <> (path |> to_string() |> String.trim_leading("/"))

    if prefix == "" do
      String.trim_leading(path, "/")
    else
      prefix
      |> URI.parse()
      |> URI.append_path(path)
      |> URI.to_string()
    end
  end

  def append_query(path, ""), do: path
  def append_query(path, nil), do: path
  def append_query(path, query), do: %{URI.parse(path) | query: query} |> URI.to_string()

  def append_fragment(path, nil), do: path

  def append_fragment(path, fragment),
    do: %{URI.parse(path) | fragment: fragment} |> URI.to_string()
end
