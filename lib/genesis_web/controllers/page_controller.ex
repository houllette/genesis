defmodule GenesisWeb.PageController do
  use GenesisWeb, :controller

  def home(conn, _params) do
    if conn.assigns.current_scope, do: redirect(conn, to: ~p"/worlds"), else: render(conn, :home)
  end
end
