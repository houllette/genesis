defmodule Genesis.Core.FictionalTime do
  @moduledoc "Exact world/calendar coordinates. Zero duration stays a point; no clock reads."
  alias Genesis.Core.Scope
  @enforce_keys [:world_id, :calendar_id, :calendar_version, :value]
  defstruct [:world_id, :calendar_id, :calendar_version, :value, unit: :second]

  @type t :: %__MODULE__{
          world_id: String.t(),
          calendar_id: String.t(),
          calendar_version: pos_integer(),
          value: integer(),
          unit: :second
        }
  @type duration :: %{unit: :second, value: non_neg_integer()}

  @spec new(
          world :: String.t(),
          calendar :: String.t(),
          version :: pos_integer(),
          value :: integer()
        ) ::
          {:ok, t()} | {:error, :invalid_time}
  def new(world, calendar, version, value) do
    time = %__MODULE__{
      world_id: world,
      calendar_id: calendar,
      calendar_version: version,
      value: value
    }

    if valid?(time), do: {:ok, time}, else: {:error, :invalid_time}
  end

  @spec valid?(time :: term()) :: boolean()
  def valid?(%__MODULE__{
        world_id: world,
        calendar_id: calendar,
        calendar_version: version,
        value: value,
        unit: :second
      }) do
    Scope.id?(world) and Scope.id?(calendar) and is_integer(version) and version > 0 and
      is_integer(value) and abs(value) <= 9_000_000_000_000
  end

  def valid?(_time), do: false

  @spec advance(time :: t(), duration :: duration()) :: {:ok, t()} | {:error, atom()}
  def advance(time, %{unit: :second, value: value} = duration)
      when is_integer(value) and value >= 0 and map_size(duration) == 2 do
    if valid?(time) and value <= 9_000_000_000_000 and
         abs(time.value + value) <= 9_000_000_000_000,
       do: {:ok, %{time | value: time.value + value}},
       else: {:error, :invalid_time}
  end

  def advance(_time, _duration), do: {:error, :unsupported_duration}

  @spec compare(left :: t(), right :: t()) ::
          {:ok, :lt | :eq | :gt} | {:error, :incompatible_time}
  def compare(
        %{world_id: w, calendar_id: c, calendar_version: v, unit: u} = left,
        %{world_id: w, calendar_id: c, calendar_version: v, unit: u} = right
      ) do
    if valid?(left) and valid?(right),
      do: {:ok, order(left.value, right.value)},
      else: {:error, :incompatible_time}
  end

  def compare(_left, _right), do: {:error, :incompatible_time}
  defp order(a, b) when a < b, do: :lt
  defp order(a, b) when a > b, do: :gt
  defp order(_a, _b), do: :eq
end
