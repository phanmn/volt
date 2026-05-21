defmodule Volt.DevServer.CacheEntry do
  @moduledoc "Cached development-server compilation result."

  defstruct code: "",
            sourcemap: nil,
            css: nil,
            hashes: nil,
            content_type: "application/javascript"
end
