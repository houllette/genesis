defmodule Genesis.Core.Audience do
  @moduledoc "Current projections and fixed event audiences; GM authority is a trusted shell grant."
  alias Genesis.Core.Scope

  @spec valid?(audience :: term()) :: boolean()
  def valid?(audience) when audience in [:public, :gm], do: true

  def valid?({:actors, ids}) when is_list(ids),
    do: length(ids) <= 100 and Enum.all?(ids, &Scope.id?/1) and Enum.uniq(ids) == ids

  def valid?(_audience), do: false

  @spec permits?(audience :: term(), viewer :: map()) :: boolean()
  def permits?(_audience, %{role: :gm}), do: true
  def permits?(:public, %{actor_id: actor}) when is_binary(actor), do: true
  def permits?({:actors, ids}, %{actor_id: actor}), do: actor in ids
  def permits?(_audience, _viewer), do: false

  @spec freeze(audience :: term(), actor_ids :: [String.t()]) :: term()
  def freeze(:public, ids), do: {:actors, Enum.sort(ids)}
  def freeze(audience, _ids), do: audience
end
