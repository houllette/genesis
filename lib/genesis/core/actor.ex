defmodule Genesis.Core.Actor do
  @moduledoc "An actor is scoped data. Traits and skills here have already been approved by authority."
  @enforce_keys [:id, :name, :kind]
  defstruct [
    :id,
    :name,
    :kind,
    :companion_of,
    :companion_policy,
    :commitment,
    persona: %{},
    traits: [],
    skills: %{},
    resources: %{},
    revision: 0,
    alive: true,
    retired: false,
    audience: :public
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          kind: :pc | :npc,
          companion_of: String.t() | nil,
          companion_policy: map() | nil,
          commitment: map() | nil,
          persona: map(),
          traits: [String.t()],
          skills: map(),
          resources: map(),
          revision: non_neg_integer(),
          alive: boolean(),
          retired: boolean(),
          audience: term()
        }
end
