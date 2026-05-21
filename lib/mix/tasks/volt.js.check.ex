defmodule Mix.Tasks.Volt.Js.Check do
  use Mix.Task

  @shortdoc "Lint and format-check Volt TypeScript assets"

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

    unformatted =
      Enum.filter(files, fn file ->
        source = File.read!(file)
        formatted = OXC.Format.run!(source, file, opts)
        formatted != source
      end)

    if unformatted == [] do
      Mix.shell().info(IO.ANSI.format([:green, "✓ All #{length(files)} files formatted"]))
      true
    else
      Mix.shell().error("#{length(unformatted)} file(s) need formatting:")
      Enum.each(unformatted, &Mix.shell().error("  #{&1}"))
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
      type_aware_lint(files, config, rules, opts)
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
        {:error, _errors} -> []
      end
    end)
  end

  defp type_aware_lint(files, config, rules, opts) do
    lint_opts =
      [
        type_aware: true,
        type_check: opts[:type_check] == true,
        rules: rules
      ] ++ type_aware_options(config)

    case OXC.Lint.run(files, lint_opts) do
      {:ok, diagnostics} -> diagnostics
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

  defp type_aware_options(config) do
    config
    |> Keyword.take([:tsgolint, :source_overrides, :fix, :fix_suggestions, :cwd])
    |> Enum.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp lint_error(message) do
    %{severity: :deny, file: "volt.js.check", message: message, rule: "oxc/type-aware"}
  end

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
