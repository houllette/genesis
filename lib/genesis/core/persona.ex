defmodule Genesis.Core.Persona do
  @moduledoc "Versioned NPC identity data, not inference or authority. Legacy snapshots are validated without rewriting them."
  alias Genesis.Core.Scope

  @editable ~w(temperament goal role culture motivation constraints)

  @spec editable_fields() :: [String.t()]
  def editable_fields, do: @editable

  @spec valid?(persona :: term()) :: boolean()
  def valid?(persona) when persona == %{}, do: true

  def valid?(
        %{"version" => 1, "temperament" => temperament, "goal" => goal, "agency" => "dormant"} =
          persona
      ),
      do: map_size(persona) == 4 and Scope.id?(temperament) and Scope.id?(goal)

  def valid?(%{"version" => 2, "agency" => "dormant", "constraints" => constraints} = persona),
    do:
      Enum.sort(Map.keys(persona)) == Enum.sort(@editable ++ ~w(version agency seed)) and
        Enum.all?(~w(seed temperament goal role culture motivation), &Scope.id?(persona[&1])) and
        is_list(constraints) and length(constraints) in 1..8 and
        Enum.all?(constraints, &Scope.id?/1) and Enum.uniq(constraints) == constraints

  def valid?(_persona), do: false

  @doc "Materializes new/fallback actors or an explicitly edited legacy persona; never used to rewrite a checkpoint."
  @spec materialize(id :: String.t(), persona :: map()) :: map()
  def materialize(id, persona) do
    Map.merge(
      %{
        "version" => 2,
        "seed" => id,
        "temperament" => "Watchful",
        "goal" => "Protect their place in the community",
        "role" => "Resident",
        "culture" => "Unspecified",
        "motivation" => "Maintain belonging and security",
        "constraints" => ["Preserve established facts", "No autonomous actions"],
        "agency" => "dormant"
      },
      Map.take(persona, @editable ++ ["seed"])
    )
  end

  @spec edit(id :: String.t(), persona :: map(), attrs :: map()) :: map()
  def edit(id, persona, attrs),
    do: id |> materialize(persona) |> Map.merge(Map.take(attrs, @editable))
end
