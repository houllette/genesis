defmodule Genesis.Core.Item do
  @moduledoc "A quantity has exactly one owner. Inventory is a projection of ownership."
  @enforce_keys [:id, :name, :owner]
  defstruct [:id, :name, :owner, quantity: 1, audience: :public]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          owner: {:zone | :actor, String.t()},
          quantity: pos_integer(),
          audience: term()
        }
end
