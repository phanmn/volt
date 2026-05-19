defmodule Volt.JS.AssetURLRewriter do
  @moduledoc """
  Rewrites `new URL("./asset.ext", import.meta.url)` references to asset imports.

  Vite treats relative asset URL constructors as part of the module graph so
  production builds can copy, hash, and rewrite the referenced file. Volt does
  the same by converting the asset argument into a generated `?url` import before
  the normal import rewriting and bundling phases run.

  Only relative specifiers that point at known static asset extensions are
  rewritten. Absolute URLs, package URLs, and non-asset files are left unchanged.
  """

  @doc """
  Rewrites matching asset URL constructors in `source`.

  Returns the original source unchanged when parsing fails or no matching
  constructor is found.
  """
  @spec rewrite(String.t(), String.t()) :: String.t()
  def rewrite(source, filename) do
    case OXC.parse(source, filename) do
      {:ok, ast} ->
        rewrites = collect_rewrites(ast)
        if rewrites == [], do: source, else: apply_rewrites(source, rewrites)

      {:error, _} ->
        source
    end
  end

  defp collect_rewrites(ast) do
    {_ast, rewrites} =
      OXC.postwalk(ast, [], fn node, acc ->
        case Volt.JS.AST.new_arguments(node, ["URL"]) do
          {:ok, _name, [source_node, meta_url | _]} ->
            maybe_collect_url_rewrite(node, source_node, meta_url, acc)

          _ ->
            {node, acc}
        end
      end)

    Enum.reverse(rewrites)
  end

  defp maybe_collect_url_rewrite(node, source_node, meta_url, acc) do
    with true <- import_meta_url?(meta_url),
         {:ok, specifier, start_pos, end_pos} <- Volt.JS.AST.string_literal_span(source_node),
         true <- relative_asset_specifier?(specifier) do
      {node, [{specifier, start_pos, end_pos} | acc]}
    else
      _ -> {node, acc}
    end
  end

  defp import_meta_url?(node) do
    node[:type] == :member_expression and get_in(node, [:property, :name]) == "url"
  end

  defp relative_asset_specifier?(specifier) do
    {path, _query} = Volt.JS.Query.split(specifier)

    (String.starts_with?(path, "./") or String.starts_with?(path, "../")) and
      Volt.Assets.asset?(path)
  end

  defp apply_rewrites(source, rewrites) do
    {imports, patches} =
      rewrites
      |> Enum.with_index()
      |> Enum.map_reduce([], fn {{specifier, start_pos, end_pos}, index}, patches ->
        ident = "__volt_asset_url_#{index}"

        import_line = [
          "import ",
          ident,
          " from ",
          Jason.encode!(Volt.JS.Query.append(specifier, "url")),
          ";"
        ]

        {import_line, [Volt.JS.Patch.new(start_pos, end_pos, ident) | patches]}
      end)

    [Enum.intersperse(imports, "\n"), "\n", Volt.JS.Patch.apply(source, patches)]
    |> IO.iodata_to_binary()
  end
end
