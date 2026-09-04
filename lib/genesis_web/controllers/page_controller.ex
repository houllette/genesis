defmodule GenesisWeb.PageController do
  use GenesisWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
