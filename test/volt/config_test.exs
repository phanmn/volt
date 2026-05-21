defmodule Volt.ConfigTest do
  use ExUnit.Case, async: true

  setup do
    on_exit(fn ->
      Application.delete_env(:volt, :tree_shaking)
      Application.delete_env(:volt, :my_app)
      Application.delete_env(:volt, :my_app_web)
    end)

    :ok
  end

  describe "build/0 and build/1 with flat config" do
    test "flat config returns defaults when nothing is set" do
      config = Volt.Config.build()
      assert config.entry == "assets/js/app.ts"
      assert config.tree_shaking == true
    end

    test "build/0 is not affected by profile config" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      assert Volt.Config.build().entry == "assets/js/app.ts"
    end
  end

  describe "build/1 with profile atom" do
    test "returns profile entry" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      assert Volt.Config.build(:my_app).entry == "my_app/js/app.ts"
    end

    test "returns profile outdir" do
      Application.put_env(:volt, :my_app, outdir: "priv/static/my_app")
      assert Volt.Config.build(:my_app).outdir == "priv/static/my_app"
    end

    test "profile values override flat config" do
      current = Application.get_env(:volt, :entry)

      Application.put_env(:volt, :entry, "assets/js/app.ts")
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")

      assert Volt.Config.build(:my_app).entry == "my_app/js/app.ts"

      if current do
        Application.put_env(:volt, :entry, current)
      else
        Application.delete_env(:volt, :entry)
      end
    end

    test "unset profile keys fall back to flat config and defaults" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      config = Volt.Config.build(:my_app)
      assert config.target == :es2020
      assert config.outdir == "priv/static/assets"
    end

    test "unknown profile returns defaults" do
      config = Volt.Config.build(:nonexistent_profile)
      assert config.entry == "assets/js/app.ts"
    end
  end

  describe "build/2 with profile and overrides" do
    test "overrides win over profile" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      config = Volt.Config.build(:my_app, entry: "override/app.ts")
      assert config.entry == "override/app.ts"
    end

    test "overrides win over flat config" do
      config = Volt.Config.build(nil, entry: "override/app.ts")
      assert config.entry == "override/app.ts"
    end

    test "tree shaking is configurable" do
      Application.put_env(:volt, :tree_shaking, false)

      assert Volt.Config.build().tree_shaking == false
      assert Volt.Config.build(nil, tree_shaking: true).tree_shaking == true
    end
  end

  describe "server/0 and server/1" do
    test "returns defaults when nothing is set" do
      assert Volt.Config.server().prefix == "/assets"
    end

    test "profile server config takes precedence over global :server" do
      Application.put_env(:volt, :my_app,
        entry: "my_app/js/app.ts",
        server: [watch_dirs: ["my_app/lib/"]]
      )

      assert Volt.Config.server(:my_app).watch_dirs == ["my_app/lib/"]
    end

    test "falls back to global :server when profile has no :server key" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      assert Volt.Config.server(:my_app).prefix == "/assets"
    end
  end

  describe "tailwind/0 and tailwind/1" do
    test "returns empty list when nothing is set" do
      assert Volt.Config.tailwind() == []
    end

    test "returns profile tailwind config" do
      Application.put_env(:volt, :my_app, tailwind: [css: "my_app/assets/css/app.css"])

      assert Volt.Config.tailwind(:my_app) == [css: "my_app/assets/css/app.css"]
    end

    test "falls back to global tailwind when profile has none" do
      Application.put_env(:volt, :my_app, entry: "my_app/js/app.ts")
      assert Volt.Config.tailwind(:my_app) == []
    end

    test "nil profile returns global tailwind" do
      assert Volt.Config.tailwind(nil) == []
    end
  end
end
