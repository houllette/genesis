defmodule Genesis.Time.CalendarTest do
  use ExUnit.Case, async: true
  alias Genesis.Core.FictionalTime
  alias Genesis.Time.Calendar

  test "Coptic month/year arithmetic and rollover use an explicit epoch, with no Gregorian substitution" do
    frame = frame("coptic", %{"year" => 1742, "month" => 12, "day" => 30})
    {:ok, point} = FictionalTime.new("world", "village", 1, 0)

    assert {:ok, 5 * 86_400} ==
             Calendar.duration(point, %{"unit" => "month", "value" => 1}, frame)

    assert {:ok, 365 * 86_400} ==
             Calendar.duration(point, %{"unit" => "year", "value" => 1}, frame)

    assert {:ok,
            %{"year" => 1743, "month" => 1, "day" => 1, "hour" => 0, "minute" => 0, "second" => 0}} =
             Calendar.components(%{point | value: 6 * 86_400}, frame)

    assert {:ok, %{"year" => 1742, "month" => 12, "day" => 29}} =
             Calendar.components(%{point | value: -86_400}, frame)
             |> then(fn {:ok, fields} -> {:ok, Map.take(fields, ~w(year month day))} end)

    assert {:error, :unsupported_calendar} =
             Calendar.duration(point, %{"unit" => "month", "value" => 1}, %{
               frame
               | "implementation" => "user.module"
             })

    assert {:error, :incompatible_time} =
             Calendar.components(%{point | calendar_version: 2}, frame)
  end

  test "Gregorian leap and clamp semantics preserve seconds and explicit half-open bounds" do
    frame = frame("gregorian", %{"year" => 2024, "month" => 1, "day" => 31})
    {:ok, point} = FictionalTime.new("world", "village", 1, 123)

    assert {:ok, 29 * 86_400} ==
             Calendar.duration(point, %{"unit" => "month", "value" => 1}, frame)

    assert {:ok, 366 * 86_400} ==
             Calendar.duration(point, %{"unit" => "year", "value" => 1}, frame)

    assert {:ok, %{"minute" => 2, "second" => 3}} =
             Calendar.components(point, frame)
             |> then(fn {:ok, fields} -> {:ok, Map.take(fields, ~w(minute second))} end)

    assert {:ok, :meets} =
             Calendar.relation(
               point,
               %{point | value: 200},
               %{point | value: 200},
               %{point | value: 300},
               frame
             )

    assert {:error, :empty_span} =
             Calendar.relation(point, point, point, %{point | value: 300}, frame)

    assert {:ok, 0} = Calendar.duration(point, %{"unit" => "second", "value" => 0}, %{})

    assert {:error, :unsupported_calendar} =
             Calendar.duration(point, %{"unit" => "month", "value" => 1}, %{})
  end

  defp frame(implementation, epoch),
    do: %{
      "format" => 1,
      "id" => "village",
      "version" => 1,
      "implementation" => implementation,
      "epoch" => epoch
    }

  test "calendar mapping rejects malformed definitions, unbounded coordinates and cross-world intervals" do
    frame = frame("coptic", %{"year" => 1743, "month" => 13, "day" => 6})
    {:ok, point} = FictionalTime.new("world", "village", 1, 0)
    assert Calendar.validate(frame) == :ok

    assert {:error, :unsupported_calendar} =
             Calendar.validate(put_in(frame["epoch"]["year"], 1742))

    assert {:error, :calendar_range} =
             Calendar.components(%{point | value: -9_000_000_000_000}, frame)

    assert {:error, :calendar_range} =
             Calendar.components(%{point | value: 9_000_000_000_000}, frame)

    assert {:error, :incompatible_time} =
             Calendar.relation(
               point,
               %{point | value: 1},
               %{point | world_id: "elsewhere"},
               %{point | world_id: "elsewhere", value: 1},
               frame
             )

    assert {:error, :unsupported_duration} =
             Calendar.duration(point, %{"unit" => "second", "value" => 0.5}, frame)
  end
end
