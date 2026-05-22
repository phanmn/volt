defmodule Mix.Tasks.Volt.Js.Check do
  use Mix.Task

  @shortdoc "Lint and format-check Volt TypeScript assets"

  @type_aware_extensions ~w(.ts .tsx .js .jsx .mts .mjs .cts .cjs)

  @moduledoc """
  Check formatting and lint Volt's JavaScript and TypeScript assets via NIF.

      mix volt.js.check
      mix volt.js.check --type-aware --type-check

  Reads format options from `config :volt, :format` (falls back to `.oxfmtrc.json`).
  Lint settings come from `config :volt, :lint`.
  File discovery uses `config :volt, sources:` and `ignore:`.

  `--type-aware` runs TypeScript-aware rules through `tsgolint` headless mode.
  Pass `--type-check` to include TypeScript syntactic and semantic diagnostics.
  """

  @impl true
  def run(args) do
    Mix.Task.run("app.config")

    opts = parse_args!(args)
    format_files = Volt.JS.Helpers.discover_format_files()
    lint_files = Volt.JS.Helpers.discover_files()

    if format_files == [] and lint_files == [] do
      Mix.shell().info("No files found")
    else
      format_ok = check_formatting(format_files)
      lint_ok = check_lint(lint_files, opts)

      unless format_ok and lint_ok do
        exit({:shutdown, 1})
      end
    end
  end

  defp check_formatting([]), do: true

  defp check_formatting(files) do
    opts = Volt.JS.Format.load_config()

    {unformatted, errors} =
      Enum.reduce(files, {[], []}, fn file, {unformatted, errors} ->
        source = File.read!(file)

        case OXC.Format.run(source, file, opts) do
          {:ok, formatted} when formatted == source ->
            {unformatted, errors}

          {:ok, _formatted} ->
            {[file | unformatted], errors}

          {:error, format_errors} ->
            {unformatted, [{file, format_errors} | errors]}
        end
      end)

    cond do
      errors != [] ->
        Mix.shell().error("#{length(errors)} file(s) could not be formatted:")

        Enum.each(Enum.reverse(errors), fn {file, format_errors} ->
          Mix.shell().error(
            "  #{file}: #{format_errors |> List.wrap() |> Enum.map_join(", ", &lint_error_message/1)}"
          )
        end)

        false

      unformatted == [] ->
        Mix.shell().info(IO.ANSI.format([:green, "✓ All #{length(files)} files formatted"]))
        true

      true ->
        Mix.shell().error("#{length(unformatted)} file(s) need formatting:")
        unformatted |> Enum.reverse() |> Enum.each(&Mix.shell().error("  #{&1}"))
        false
    end
  end

  defp check_lint([], _opts), do: true

  defp check_lint(files, opts) do
    diags = run_lint(files, opts)

    if diags == [] do
      Mix.shell().info(
        IO.ANSI.format([:green, "✓ No lint issues", :reset, :faint, " (#{length(files)} files)"])
      )

      true
    else
      print_lint_diags(diags)
    end
  end

  defp run_lint(files, opts) do
    config = Application.get_env(:volt, :lint, [])
    rules = Keyword.get(config, :rules, %{})

    if opts[:type_aware] do
      type_aware_lint(files, config, type_aware_rules(rules), opts)
    else
      ast_lint(files, config, rules)
    end
  end

  defp ast_lint(files, config, rules) do
    plugins = Keyword.get(config, :plugins, [:typescript])
    custom_rules = Keyword.get(config, :custom_rules, [])

    Enum.flat_map(files, fn file ->
      source = File.read!(file)

      case OXC.Lint.run(source, file,
             plugins: plugins,
             rules: rules,
             custom_rules: custom_rules
           ) do
        {:ok, diagnostics} -> Enum.map(diagnostics, &Map.put(&1, :file, file))
        {:error, errors} -> Enum.map(errors, &lint_error(&1, file))
      end
    end)
  end

  defp type_aware_lint(files, config, rules, opts) do
    {files, source_overrides, source_files} = type_aware_inputs(files, config)

    lint_opts =
      [
        type_aware: true,
        type_check: opts[:type_check] == true,
        rules: rules,
        source_overrides: Map.merge(source_overrides, Keyword.get(config, :source_overrides, %{}))
      ] ++ type_aware_options(config)

    case OXC.Lint.run(files, lint_opts) do
      {:ok, diagnostics} -> Enum.map(diagnostics, &restore_sfc_file(&1, source_files))
      {:error, errors} -> Enum.map(errors, &lint_error/1)
    end
  end

  defp parse_args!(args) do
    {opts, _argv, invalid} =
      OptionParser.parse(args,
        strict: [type_aware: :boolean, type_check: :boolean],
        aliases: [T: :type_aware]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{Enum.map_join(invalid, ", ", &elem(&1, 0))}")
    end

    opts
  end

  defp type_aware_inputs(files, config) do
    plugins = Keyword.get(config, :plugins, [])

    Enum.reduce(files, {[], %{}, %{}}, fn file, {files, overrides, source_files} ->
      if type_aware_file?(file) do
        {[file | files], overrides, source_files}
      else
        file
        |> embedded_modules(plugins)
        |> Stream.with_index()
        |> Enum.reduce({files, overrides, source_files}, fn {{extension, source}, index}, acc ->
          add_embedded_module(acc, file, source, extension, index)
        end)
      end
    end)
    |> then(fn {files, overrides, source_files} ->
      {Enum.reverse(files), overrides, source_files}
    end)
  end

  defp type_aware_file?(file), do: Path.extname(file) in @type_aware_extensions

  defp embedded_modules(file, plugins) do
    Volt.PluginRunner.embedded_modules(plugins, file, File.read!(file), [])
  end

  defp add_embedded_module({files, overrides, source_files}, file, source, extension, index) do
    virtual_file = "#{file}.script#{index}#{extension}"
    expanded = Path.expand(virtual_file)

    {
      [virtual_file | files],
      Map.put(overrides, expanded, source),
      Map.put(source_files, expanded, file)
    }
  end

  defp restore_sfc_file(diagnostic, source_files) do
    case Map.fetch(source_files, diagnostic.file) do
      {:ok, file} -> %{diagnostic | file: file}
      :error -> diagnostic
    end
  end

  defp type_aware_rules(rules) do
    Map.filter(rules, fn {rule, _config} ->
      String.starts_with?(to_string(rule), "typescript/")
    end)
  end

  defp type_aware_options(config) do
    config
    |> Keyword.take([:tsgolint, :fix, :fix_suggestions, :cwd])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp lint_error(message), do: lint_error(message, "volt.js.check")

  defp lint_error(message, file) do
    %{severity: :deny, file: file, message: lint_error_message(message), rule: "oxc/lint"}
  end

  defp lint_error_message(%{message: message}), do: message
  defp lint_error_message(message) when is_binary(message), do: message
  defp lint_error_message(message), do: inspect(message)

  defp print_lint_diags(diags) do
    errors = Enum.count(diags, &(&1.severity == :deny))
    warnings = Enum.count(diags, &(&1.severity == :warn))

    Enum.each(diags, fn diag ->
      tag = if diag.severity == :deny, do: "error", else: "warn"
      Mix.shell().error("  [#{tag}] #{diag.file}: #{diag.message} (#{diag.rule})")
    end)

    Mix.shell().error("#{errors} error(s), #{warnings} warning(s)")
    errors == 0
  end
end
