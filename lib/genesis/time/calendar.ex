defmodule Genesis.Time.Calendar do
  @moduledoc "Pure Tempo 1.6.4 adapter. Explicit midnight epochs, second precision, Gregorian/Coptic only."
  alias Genesis.Core.{FictionalTime, Scope}
  @fixed %{"second" => 1, "minute" => 60, "hour" => 3600, "day" => 86_400}
  @relative %{"month" => :month, "year" => :year}

  @spec validate(definition :: term()) :: :ok | {:error, atom()}
  def validate(
        %{"format" => 1, "id" => id, "version" => 1, "implementation" => kind, "epoch" => epoch} =
          frame
      )
      when map_size(frame) == 5 do
    with true <- Scope.id?(id),
         {:ok, calendar} <- implementation(kind),
         {:ok, _} <- epoch(epoch, calendar) do
      :ok
    else
      _ -> {:error, :unsupported_calendar}
    end
  end

  def validate(_frame), do: {:error, :unsupported_calendar}

  @spec duration(time :: FictionalTime.t(), amount :: map(), definition :: map()) ::
          {:ok, non_neg_integer()} | {:error, atom()}
  def duration(time, %{"unit" => unit, "value" => value} = amount, frame)
      when map_size(amount) == 2 and is_integer(value) and value in 0..31_622_400 do
    cond do
      not FictionalTime.valid?(time) ->
        {:error, :invalid_time}

      Map.has_key?(@fixed, unit) ->
        bounded(value * @fixed[unit])

      Map.has_key?(@relative, unit) and value <= 1200 ->
        relative(time, frame, @relative[unit], value)

      true ->
        {:error, :unsupported_duration}
    end
  end

  def duration(_time, _amount, _frame), do: {:error, :unsupported_duration}

  @spec components(time :: FictionalTime.t(), definition :: map()) ::
          {:ok, map()} | {:error, atom()}
  def components(time, frame) do
    with {:ok, tempo} <- point(time, frame),
         do: {:ok, Map.new(tempo.time, fn {key, value} -> {Atom.to_string(key), value} end)}
  end

  @doc "Allen relation for two nonempty half-open spans. Point events are never widened into spans."
  @spec relation(
          a :: FictionalTime.t(),
          b :: FictionalTime.t(),
          c :: FictionalTime.t(),
          d :: FictionalTime.t(),
          definition :: map()
        ) :: {:ok, atom()} | {:error, atom()}
  def relation(a, b, c, d, frame) do
    with :ok <- span(a, b),
         :ok <- span(c, d),
         {:ok, _} <- FictionalTime.compare(a, c),
         {:ok, af} <- point(a, frame),
         {:ok, at} <- point(b, frame),
         {:ok, bf} <- point(c, frame),
         {:ok, bt} <- point(d, frame),
         {:ok, first} <- Tempo.Interval.new(af, at),
         {:ok, second} <- Tempo.Interval.new(bf, bt) do
      {:ok, Tempo.Interval.relation(first, second)}
    end
  end

  defp span(a, b) do
    case FictionalTime.compare(a, b) do
      {:ok, :lt} -> :ok
      {:ok, _} -> {:error, :empty_span}
      error -> error
    end
  end

  @doc "A point belongs to [from, to); ordinal worlds use explicit integer coordinates, mapped calendars use Tempo intervals."
  @spec contains?(
          time :: FictionalTime.t(),
          from :: integer(),
          to :: integer(),
          definition :: map()
        ) :: boolean()
  def contains?(time, first, last, frame)
      when is_integer(first) and is_integer(last) and first < last do
    if frame == %{} do
      FictionalTime.valid?(time) and first <= time.value and time.value < last
    else
      with {:ok, point} <- point(time, frame),
           {:ok, start} <- point(%{time | value: first}, frame),
           {:ok, finish} <- point(%{time | value: last}, frame),
           {:ok, interval} <- Tempo.Interval.new(start, finish) do
        Tempo.Compare.compare_endpoints(Tempo.Interval.from(interval), point) in [:earlier, :same] and
          Tempo.Compare.compare_endpoints(point, Tempo.Interval.to(interval)) == :earlier
      else
        _ -> false
      end
    end
  end

  def contains?(_time, _first, _last, _frame), do: false

  defp point(time, frame) do
    with :ok <- validate(frame),
         true <- FictionalTime.valid?(time),
         true <- time.calendar_id == frame["id"] and time.calendar_version == frame["version"],
         {:ok, calendar} <- implementation(frame["implementation"]),
         {:ok, epoch} <- epoch(frame["epoch"], calendar),
         :ok <- range(frame["epoch"], calendar, time.value) do
      checked_point(Tempo.shift(epoch, second: time.value))
    else
      false -> {:error, :incompatible_time}
      error -> error
    end
  end

  defp checked_point(%{time: fields} = result) when is_list(fields) do
    if Keyword.fetch!(fields, :year) in 1..9999,
      do: {:ok, result},
      else: {:error, :calendar_range}
  end

  defp checked_point(_value), do: {:error, :calendar_range}

  defp range(%{"year" => y, "month" => m, "day" => d}, calendar, seconds) do
    day = calendar.date_to_iso_days(y, m, d) + Integer.floor_div(seconds, 86_400)

    if day >= calendar.date_to_iso_days(1, 1, 1) and day < calendar.date_to_iso_days(10_000, 1, 1),
      do: :ok,
      else: {:error, :calendar_range}
  end

  defp relative(time, frame, unit, value) do
    with {:ok, start} <- point(time, frame),
         {:ok, finish} <- checked_point(Tempo.shift(start, [{unit, value}])),
         {:ok, a} <- Tempo.to_naive_date_time(start),
         {:ok, b} <- Tempo.to_naive_date_time(finish) do
      bounded(NaiveDateTime.diff(b, a, :second))
    else
      {:error, reason} when is_atom(reason) -> {:error, reason}
      {:error, _} -> {:error, :calendar_range}
    end
  end

  defp bounded(seconds) when seconds in 0..31_622_400, do: {:ok, seconds}
  defp bounded(_seconds), do: {:error, :time_capacity_limit}
  defp implementation("gregorian"), do: {:ok, Calendrical.Gregorian}
  defp implementation("coptic"), do: {:ok, Calendrical.Coptic}
  defp implementation(_kind), do: {:error, :unsupported_calendar}

  defp epoch(%{"year" => y, "month" => m, "day" => d} = fields, calendar)
       when map_size(fields) == 3 and is_integer(y) and y in 1..9999 and is_integer(m) and
              is_integer(d),
       do: Tempo.new(year: y, month: m, day: d, hour: 0, minute: 0, second: 0, calendar: calendar)

  defp epoch(_fields, _calendar), do: {:error, :unsupported_calendar}
end
