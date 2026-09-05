defmodule Genesis.Core.Knowledge do
  @moduledoc "Sourced knowledge. Beliefs and memories do not become engine facts."
  @enforce_keys [:id, :kind, :subject_id, :predicate, :value, :scope, :source_ids]
  defstruct [
    :id,
    :kind,
    :subject_id,
    :object_id,
    :predicate,
    :value,
    :scope,
    :occurred_at,
    :learned_at,
    :recorded_at,
    source_ids: [],
    audience: :gm,
    version: 1
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          kind: atom(),
          subject_id: String.t(),
          object_id: String.t() | nil,
          predicate: String.t(),
          value: term(),
          scope: Genesis.Core.Scope.t(),
          occurred_at: integer() | nil,
          learned_at: integer() | nil,
          recorded_at: DateTime.t() | nil,
          source_ids: [String.t()],
          audience: term(),
          version: pos_integer()
        }

  @spec kinds() :: [atom()]
  def kinds, do: [:event, :fact, :observation, :belief, :relationship, :obligation, :memory]
end
