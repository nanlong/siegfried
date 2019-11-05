defmodule SiegfriedWeb.PageController do
  use SiegfriedWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
