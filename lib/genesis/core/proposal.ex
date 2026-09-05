defmodule Genesis.Core.Proposal do
  @moduledoc "Server-retained exact action and revision binding. No reservation and no speculative draws."
  @enforce_keys [:id, :scope, :actor_id, :revision, :intent, :terms, :rules_ref]
  defstruct [:id, :scope, :actor_id, :revision, :intent, :terms, :rules_ref]

  @type t :: %__MODULE__{
          id: String.t(),
          scope: Genesis.Core.Scope.t(),
          actor_id: String.t(),
          revision: non_neg_integer(),
          intent: map(),
          terms: map(),
          rules_ref: term()
        }
end
