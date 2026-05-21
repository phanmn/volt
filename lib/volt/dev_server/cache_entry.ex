defmodule Volt.DevServer.CacheEntry do
  @moduledoc false

  defstruct code: "",
            sourcemap: nil,
            css: nil,
            hashes: nil,
            content_type: "application/javascript"
end
