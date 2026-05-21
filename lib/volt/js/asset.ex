defmodule Volt.JS.Asset do
  @moduledoc "Access to JavaScript and TypeScript support assets bundled with Volt."

  @priv_ts Application.app_dir(:volt, "priv/ts")

  @doc "Path to the priv/ts directory containing bundled TypeScript assets."
  @spec priv_dir :: String.t()
  def priv_dir, do: @priv_ts

  @spec read!(String.t()) :: String.t()
  def read!(filename) do
    filename
    |> path_for()
    |> File.read!()
  end

  @doc """
  Read a TypeScript asset, compile to JavaScript, and cache in persistent_term.

  Returns compiled JS on subsequent calls without recompilation.
  """
  @spec compiled!(String.t()) :: String.t()
  def compiled!(filename) do
    key = {__MODULE__, :compiled, filename}

    case :persistent_term.get(key, nil) do
      nil ->
        code = read!(filename) |> compile_ts(filename)
        :persistent_term.put(key, code)
        code

      code ->
        code
    end
  end

  @doc "Compile a TypeScript support asset and replace string placeholders with JavaScript literals."
  @spec compiled_template!(String.t(), %{String.t() => String.t()}) :: String.t()
  def compiled_template!(filename, replacements) do
    Enum.reduce(replacements, compiled!(filename), fn {placeholder, value}, code ->
      String.replace(code, Jason.encode!(placeholder), Jason.encode!(value))
    end)
  end

  @spec path_for(String.t()) :: String.t()
  def path_for(filename), do: Path.join(@priv_ts, filename)

  # OXC.transform returns a plain string with sourcemap: false,
  # or %{code: string, sourcemap: string} with sourcemap: true.
  defp compile_ts(source, filename) do
    case OXC.transform(source, filename, sourcemap: false) do
      {:ok, code} when is_binary(code) -> code
      {:ok, %{code: code}} -> code
      _ -> source
    end
  end
end
