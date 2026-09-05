defmodule Genesis.Core.Scope do
  @moduledoc "Serializable identity of a single world state scope, independent of campaigns."
  @enforce_keys [:world_id, :generation, :kind]
  defstruct [:world_id, :generation, :kind, :window_id, :id]

  @type t :: %__MODULE__{
          world_id: String.t(),
          generation: non_neg_integer(),
          kind: :published | :experience | :candidate | :rehearsal,
          window_id: String.t() | nil,
          id: String.t() | nil
        }

  @spec new(attrs :: map()) :: {:ok, t()} | {:error, :invalid_scope}
  def new(attrs) when is_map(attrs) do
    if Enum.all?(Map.keys(attrs), &(&1 in [:world_id, :generation, :kind, :window_id, :id])) do
      scope = struct(__MODULE__, attrs)
      if valid?(scope), do: {:ok, scope}, else: {:error, :invalid_scope}
    else
      {:error, :invalid_scope}
    end
  end

  def new(_attrs), do: {:error, :invalid_scope}

  @spec valid?(scope :: term()) :: boolean()
  def valid?(%__MODULE__{world_id: world, generation: generation} = scope)
      when is_integer(generation) and generation >= 0 do
    id?(world) and valid_kind?(scope)
  end

  def valid?(_scope), do: false

  @spec key(scope :: t()) :: tuple()
  def key(scope), do: {scope.world_id, scope.generation, scope.kind, scope.window_id, scope.id}

  @doc "IDs are bounded nonempty UTF-8 strings, never dynamically created atoms."
  @spec id?(id :: term()) :: boolean()
  def id?(id) when is_binary(id), do: byte_size(id) in 1..128 and String.valid?(id)
  def id?(_id), do: false

  defp valid_kind?(%{kind: :published, window_id: nil, id: nil}), do: true

  defp valid_kind?(%{kind: kind, window_id: window, id: id})
       when kind in [:experience, :candidate],
       do: id?(window) and id?(id)

  defp valid_kind?(%{kind: :rehearsal, window_id: nil, id: id}), do: id?(id)
  defp valid_kind?(_scope), do: false
end
