defmodule Volt.HMR.Message do
  @moduledoc "JSON message sent over the HMR WebSocket protocol."

  @derive Jason.Encoder
  defstruct [:type, :payload]
end
