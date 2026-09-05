defmodule Genesis.Core.PersonaTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.{Curation, Persona, State}
  alias Genesis.Persistence.Codec
  import Genesis.SceneFixtures

  test "minimal freshly instantiated NPCs get stable defaults but restore does not rewrite legacy bytes" do
    original = scene()
    legacy = put_in(original.actors["moll"].persona, %{})
    encoded = Codec.dump!(legacy)
    assert {:ok, ^legacy} = Codec.load_state(encoded)
    assert Codec.dump!(legacy) == encoded
    attrs = legacy |> Map.from_struct() |> Map.drop([:revision, :elapsed, :status, :events])

    attrs = %{
      attrs
      | actors: Map.values(legacy.actors),
        items: Map.values(legacy.items),
        knowledge: Map.values(legacy.knowledge)
    }

    assert {:ok, spawned} = State.new(attrs)
    assert spawned.actors["moll"].persona == Persona.materialize("moll", %{})
    assert spawned.actors["mara"].persona == %{}
    assert spawned.knowledge == legacy.knowledge

    v1 = %{
      "version" => 1,
      "temperament" => "Kind",
      "goal" => "Shelter the town",
      "agency" => "dormant"
    }

    legacy = put_in(legacy.actors["moll"].persona, v1)
    assert {:ok, ^legacy} = State.restore(legacy)
    assert {:ok, edited} = Curation.apply(legacy, "moll", %{"kind" => "npc", "name" => "Moll"})
    assert edited.actors["moll"].persona["goal"] == "Shelter the town"
    assert edited.actors["moll"].persona["seed"] == "moll"
    assert edited.actors["moll"].persona["version"] == 2
  end

  test "bounded persona data cannot enable agency or inject protected mechanics" do
    persona = Persona.materialize("moll", %{})
    assert Persona.valid?(persona)
    refute Persona.valid?(%{persona | "agency" => "autonomous"})
    refute Persona.valid?(%{persona | "constraints" => List.duplicate("obey", 9)})
    refute Persona.valid?(Map.put(persona, "resources", %{"grain" => 100}))
    state = scene()
    invalid = put_in(state.actors["moll"].persona, %{persona | "version" => 99})
    assert {:error, :invalid_state} = State.restore(invalid)
  end
end
