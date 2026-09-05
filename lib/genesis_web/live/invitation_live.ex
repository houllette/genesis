defmodule GenesisWeb.InvitationLive do
  use GenesisWeb, :live_view
  alias Genesis.Invitations

  @impl true
  def mount(%{"token" => token}, _session, socket),
    do: {:ok, assign(socket, token: token, page_title: "Campaign invitation")}

  @impl true
  def handle_event("accept", _params, socket) do
    case Invitations.accept(socket.assigns.current_scope, socket.assigns.token) do
      {:ok, result} ->
        {:noreply,
         push_navigate(socket, to: ~p"/worlds/#{result.world_id}/campaigns/#{result.campaign_id}")}

      {:error, _} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "This invitation is unavailable, expired, already used, or addressed to another email. Ask your GM for a new link."
         )}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <section class="workspace-panel">
        <p class="eyebrow">You have a place at the table</p>
        <h1 class="section-heading">Campaign invitation</h1>
        <p class="mb-6">
          Accept as {@current_scope.user.email}. Only the email chosen by the GM can use this invitation.
        </p>
        <button
          id="accept-invitation"
          class="primary-button"
          phx-click="accept"
          phx-disable-with="Checking…"
        >Accept invitation</button>
      </section>
    </Layouts.app>
    """
  end
end
