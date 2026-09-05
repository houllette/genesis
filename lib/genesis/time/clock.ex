defmodule Genesis.Time.Clock do
  @moduledoc "Shell clock boundary. Tempo supplies UTC instants; OTP monotonic milliseconds measure deadlines."
  @type t :: %{utc: (-> DateTime.t()), monotonic: (-> integer())}

  @spec system() :: t()
  def system,
    do: %{utc: &Tempo.Clock.utc_now/0, monotonic: fn -> System.monotonic_time(:millisecond) end}

  @spec read(clock :: t()) :: %{utc: DateTime.t(), monotonic_ms: integer()}
  def read(clock \\ system()) do
    %DateTime{time_zone: "Etc/UTC", utc_offset: 0, std_offset: 0} = utc = clock.utc.()
    monotonic = clock.monotonic.()
    true = is_integer(monotonic)
    %{utc: utc, monotonic_ms: monotonic}
  end

  @spec remaining(deadline_ms :: integer(), clock :: t()) :: non_neg_integer()
  def remaining(deadline_ms, clock \\ system()), do: max(0, deadline_ms - clock.monotonic.())
end
