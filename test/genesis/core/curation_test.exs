defmodule Genesis.Core.CurationTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, State}
  import Genesis.SceneFixtures

  test "curation preserves typed ownership, defaults dormant agency, and cannot inject engine facts" do
    state = scene()
    assert {:ok, next} = Curation.apply(state, "new-person", %{"kind" => "npc", "name" => "Edda"})
    assert next.actors["new-person"].persona["agency"] == "dormant"
    assert next.revision == state.revision + 1
    assert next.time == state.time
    assert next.knowledge == state.knowledge

    assert {:error, :invalid_record} =
             Curation.apply(state, "bad", %{"kind" => "npc", "name" => "Edda", "facts" => []})

    assert {:error, :invalid_record} =
             Curation.apply(state, "bad", %{"kind" => "item", "name" => "Coin", "quantity" => -1})

    assert {:ok, view} = State.view(next, %{role: :spectator, actor_id: nil})
    refute Map.has_key?(Enum.find(view.actors, &(&1.id == "new-person")), :persona)
  end
end
