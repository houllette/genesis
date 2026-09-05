defmodule Genesis.Persistence.CodecTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.Scene
  alias Genesis.Persistence.{Codec, Transition}
  import Genesis.SceneFixtures

  test "phase-05 snapshot bytes keep their digest and exact round trip after additive local fields" do
    old = "test/fixtures/phase05_snapshot.json" |> File.read!() |> Jason.decode!()
    assert {:ok, restored} = Codec.load_state(old)
    assert restored.local_rules == nil
    assert restored.settlement == nil
    assert restored.items["ration"].commodity == nil
    assert Codec.dump!(restored) == old
  end

  test "a resolved state survives JSON with exact types, scope, draws and UTC microseconds" do
    original = scene()

    {:ok, next, _} =
      Scene.reduce(original, "mara", %{type: "help", target_id: "moll"}, inputs(original, "help"))

    assert {:ok, stored} = Codec.dump(next)
    assert {:ok, ^next} = stored |> Jason.encode!() |> Jason.decode!() |> Codec.load_state()
    assert hd(next.events).recorded_at.microsecond == {123_456, 6}
    assert {:error, :unsupported_format} = Codec.load(%{"format" => 99, "value" => []})

    assert {:error, :invalid_format} =
             Codec.load(%{"format" => 1, "value" => ["a", "invented_runtime_atom"]})

    assert {:error, :invalid_format} = Codec.dump(fn -> :unsafe end)
  end

  test "replay applies recorded changes and rejects wrong bases or corrupted transitions" do
    initial = scene()

    {:ok, next, _} =
      Scene.reduce(initial, "mara", %{type: "take", target_id: "ration"}, inputs(initial, "take"))

    assert {:ok, delta} = Transition.between(initial, next)
    assert {:ok, ^next} = Transition.apply(initial, delta)
    assert {:error, :replay_conflict} = Transition.apply(next, delta)

    assert {:error, :replay_conflict} =
             Transition.apply(initial, Map.put(delta, "after", "corrupt"))

    refute Map.has_key?(delta, "snapshot")
  end
end
