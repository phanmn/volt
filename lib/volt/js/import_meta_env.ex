defmodule Volt.JS.ImportMetaEnv do
  @moduledoc false

  @prefix "import.meta.env."

  @spec inject(String.t(), String.t(), %{String.t() => String.t()}) ::
          {:ok, String.t()} | {:error, term()}
  def inject(source, _filename, define) when define in [%{}, nil], do: {:ok, source}

  def inject(source, filename, define) do
    env = env_from_define(define)

    if map_size(env) == 0 do
      {:ok, source}
    else
      with {:ok, ast} <- OXC.parse(source, filename) do
        if references_import_meta_env?(ast) do
          {:ok, env_assignment(env) <> source}
        else
          {:ok, source}
        end
      end
    end
  end

  defp env_from_define(define) do
    define
    |> Enum.filter(fn {key, _value} -> String.starts_with?(key, @prefix) end)
    |> Map.new(fn {key, value} -> {String.replace_prefix(key, @prefix, ""), value} end)
  end

  defp references_import_meta_env?(ast) do
    {_ast, found?} =
      OXC.postwalk(ast, false, fn
        node, true ->
          {node, true}

        %{type: :member_expression} = node, false ->
          {node, import_meta_env?(node)}

        node, false ->
          {node, false}
      end)

    found?
  end

  defp import_meta_env?(%{
         type: :member_expression,
         computed: false,
         property: %{type: :identifier, name: "env"},
         object: %{type: :meta_property, meta: %{name: "import"}, property: %{name: "meta"}}
       }),
       do: true

  defp import_meta_env?(_node), do: false

  defp env_assignment(env) do
    properties =
      env
      |> Enum.sort_by(fn {key, _value} -> key end)
      |> Enum.map_join(", ", fn {key, value} -> "#{Jason.encode!(key)}: #{value}" end)

    "import.meta.env = { #{properties} };\n"
  end
end
