defmodule Genesis.Core.CurationTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, State}
  import Genesis.SceneFixtures

  test "NPC identity seeds survive renames and partial persona edits without creating facts" do
    state = scene()
    attrs = %{"kind" => "npc", "name" => "Edda"}
    assert {:ok, created} = Curation.apply(state, "edda", attrs)
    persona = created.actors["edda"].persona
    assert persona["version"] == 2
    assert persona["seed"] == "edda"
    assert persona["role"] == "Resident"
    assert persona["constraints"] == ["Preserve established facts", "No autonomous actions"]

    assert {:ok, edited} =
             Curation.apply(created, "edda", %{
               "kind" => "npc",
               "name" => "Edda Vale",
               "goal" => "Keep the bridge open"
             })

    assert edited.actors["edda"].persona == %{persona | "goal" => "Keep the bridge open"}
    assert edited.knowledge == state.knowledge

    for forbidden <- ["seed", "agency", "facts", "version"] do
      assert {:error, :invalid_record} =
               Curation.apply(created, "edda", Map.put(attrs, forbidden, "forged"))
    end
  end

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

  test "partial edits preserve existing visibility instead of silently publishing a hidden record" do
    state = scene()
    state = put_in(state.actors["moll"].audience, :gm)

    assert {:ok, updated} =
             Curation.apply(state, "moll", %{"kind" => "npc", "name" => "Moll Vale"})

    assert updated.actors["moll"].audience == :gm

    assert {:ok, updated} =
             Curation.apply(updated, "sealed-letter", %{
               "kind" => "item",
               "name" => "Sealed dispatch"
             })

    assert updated.items["sealed-letter"].audience == state.items["sealed-letter"].audience
    assert {:ok, view} = State.view(updated, %{role: :spectator, actor_id: nil})
    refute Enum.any?(view.actors, &(&1.id == "moll"))
    refute Enum.any?(view.items, &(&1.id == "sealed-letter"))
  end
end
