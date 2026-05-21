defmodule Volt.JS.AST do
  @moduledoc "Helpers for matching and editing OXC JavaScript AST nodes."

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

  def import_meta_property?(
        %{
          type: :member_expression,
          computed: false,
          property: %{type: :identifier, name: property},
          object: %{type: :meta_property, meta: %{name: "import"}, property: %{name: "meta"}}
        },
        property
      ),
      do: true

  def import_meta_property?(%{type: :member_expression, property: %{name: property}}, property),
    do: true

  def import_meta_property?(_node, _property), do: false

  def call_member_arguments(node, object, property) when is_map(node) do
    if node[:type] == :call_expression and member_expression?(node[:callee], object, property) do
      {:ok, node[:arguments] || []}
    end
  end

  def call_member_arguments(_node, _object, _property), do: nil

  def member_expression?(%{type: :member_expression} = node, object, property) do
    node[:computed] == false and node_name(node[:object]) == object and
      node_name(node[:property]) == property
  end

  def member_expression?(_node, _object, _property), do: false

  def property_key(%{name: name}) when is_binary(name), do: {:ok, name}
  def property_key(%{value: value}) when is_binary(value), do: {:ok, value}
  def property_key(_key), do: :error

  def replace_literal(ast, old_value, new_value) do
    OXC.postwalk(ast, fn
      %{type: :literal, value: ^old_value} = node ->
        %{node | value: new_value, raw: Jason.encode!(new_value)}

      node ->
        node
    end)
  end

  defp identifier_name(%{type: :identifier, name: name}), do: name
  defp identifier_name(_), do: nil

  defp node_name(%{type: :identifier, name: name}), do: name
  defp node_name(%{type: :meta_property, property: %{name: name}}), do: name
  defp node_name(_node), do: nil
end
