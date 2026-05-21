defmodule Volt.JsCheckTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  @tmp_dir "tmp/js_check_test_#{:erlang.unique_integer([:positive])}"

  setup do
    File.mkdir_p!(@tmp_dir)
    on_exit(fn -> File.rm_rf!(@tmp_dir) end)
    original_root = Application.get_env(:volt, :root)
    original_lint = Application.get_env(:volt, :lint)
    Application.put_env(:volt, :root, @tmp_dir)

    on_exit(fn ->
      if original_root,
        do: Application.put_env(:volt, :root, original_root),
        else: Application.delete_env(:volt, :root)

      if original_lint,
        do: Application.put_env(:volt, :lint, original_lint),
        else: Application.delete_env(:volt, :lint)
    end)

    :ok
  end

  test "type-aware check reports tsgolint diagnostics" do
    File.write!(Path.join(@tmp_dir, "typed.ts"), "export const value = Promise.resolve(1)\n")
    tsgolint = fake_tsgolint!(@tmp_dir)

    Application.put_env(:volt, :lint,
      tsgolint: tsgolint,
      rules: %{"typescript/no-floating-promises" => :deny}
    )

    output =
      capture_io(:stderr, fn ->
        catch_exit(Mix.Tasks.Volt.Js.Check.run(["--type-aware"]))
      end)

    assert output =~ "floating promise"
    assert output =~ "typescript/no-floating-promises"
  end

  defp fake_tsgolint!(dir) do
    path = Path.join(dir, "tsgolint")

    File.write!(path, """
    #!/bin/sh
    elixir -e 'json = ~s({"rule":"no-floating-promises","message":{"description":"floating promise"},"file_path":"typed.ts","range":{"pos":0,"end":5}}); IO.binwrite(<<byte_size(json)::little-32, 1, json::binary>>)'
    """)

    File.chmod!(path, 0o755)
    path
  end
end
