defmodule SolidExampleWeb.Router do
  use SolidExampleWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SolidExampleWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/", SolidExampleWeb do
    pipe_through :browser
    live "/", HomeLive
  end
end
