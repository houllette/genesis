defmodule Genesis.Time.ClockTest do
  use ExUnit.Case, async: true
  alias Genesis.Time.Clock
  alias Tempo.Clock, as: TempoClock
  alias Tempo.Clock.Test, as: TestClock

  test "UTC precision survives the selected Tempo boundary; backward wall movement does not extend deadlines" do
    Process.put({TempoClock, :clock}, TestClock)
    pin = ~U[2026-09-04 12:34:56.123456Z]
    TestClock.put(pin)
    clock = %{Clock.system() | monotonic: fn -> 100 end}
    assert Clock.read(clock) == %{utc: pin, monotonic_ms: 100}
    assert Clock.remaining(150, clock) == 50
    TestClock.advance(-3600)
    later = %{clock | monotonic: fn -> 160 end}
    assert Clock.read(later).utc == DateTime.add(pin, -3600)
    assert Clock.remaining(150, later) == 0
  end

  test "two supervised concurrent children select independent Tempo clock pins" do
    supervisor = start_supervised!(Task.Supervisor)
    parent = self()

    tasks =
      for second <- [1, 2] do
        Task.Supervisor.async_nolink(supervisor, fn ->
          Process.put({TempoClock, :clock}, TestClock)
          TestClock.put(DateTime.add(~U[2026-09-04 00:00:00Z], second))
          send(parent, {:pinned, self()})

          receive do
            :read -> Clock.read().utc
          end
        end)
      end

    for _ <- tasks, do: assert_receive({:pinned, _pid})
    Enum.each(tasks, &send(&1.pid, :read))
    assert Enum.map(tasks, &Task.await/1) == [~U[2026-09-04 00:00:01Z], ~U[2026-09-04 00:00:02Z]]
  end

  test "a parent's pin is not inherited; children receive an explicit clock dependency" do
    Process.put({TempoClock, :clock}, TestClock)
    pin = ~U[2026-09-04 00:00:00.123456Z]
    TestClock.put(pin)
    supervisor = start_supervised!(Task.Supervisor)

    task =
      Task.Supervisor.async_nolink(supervisor, fn ->
        inherited = Process.get({TempoClock, :clock})
        Process.put({TempoClock, :clock}, TestClock)
        error = assert_raise RuntimeError, ~r/no time pinned/, fn -> Clock.read() end
        {inherited, error.message}
      end)

    assert {nil, message} = Task.await(task)
    assert message =~ "no time pinned"

    clock = %{
      utc: fn ->
        Process.put({TempoClock, :clock}, TestClock)
        TestClock.put(pin)
        TempoClock.utc_now()
      end,
      monotonic: fn -> 500 end
    }

    task = Task.Supervisor.async_nolink(supervisor, fn -> Clock.read(clock) end)
    assert Task.await(task) == %{utc: pin, monotonic_ms: 500}
  end
end
