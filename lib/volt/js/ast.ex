defmodule Volt.JS.AST do
  @moduledoc false

  def string_literal_span(node) when is_map(node) do
    case literal_value(node) do
      value when is_binary(value) ->
        with start_pos when is_integer(start_pos) <- node[:start],
             end_pos when is_integer(end_pos) <- node[:end] do
          {:ok, value, start_pos, end_pos}
        else
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def string_literal_span(_), do: nil

  defp literal_value(%{type: :template_literal, expressions: [], quasis: [quasi]}) do
    get_in(quasi, [:value, :cooked])
  end

  defp literal_value(node), do: node[:value]

  def call_arguments(node, name) when is_map(node) do
    if node[:type] == :call_expression and identifier_name(node[:callee]) == name do
      {:ok, node[:arguments] || []}
    end
  end

  def call_arguments(_, _), do: nil

  def new_arguments(node, names) when is_map(node) do
    name = identifier_name(node[:callee])

    if node[:type] == :new_expression and name in names do
      {:ok, name, node[:arguments] || []}
    end
  end

  def new_arguments(_, _), do: nil

  defp identifier_name(%{type: :identifier, name: name}), do: name
  defp identifier_name(_), do: nil
end
