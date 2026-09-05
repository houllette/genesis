defmodule Genesis.Systems.WorldProfile do
  @moduledoc "Versioned local society presets. These choices are data, not alternate engine implementations."

  @spec preset(id :: String.t()) :: {:ok, map()} | {:error, atom()}
  def preset("temple_market"),
    do:
      {:ok,
       %{
         "id" => "temple_market",
         "version" => 1,
         "exchange" => "currency",
         "tradition_kind" => "religious"
       }}

  def preset("mutual_aid"),
    do:
      {:ok,
       %{
         "id" => "mutual_aid",
         "version" => 1,
         "exchange" => "barter",
         "tradition_kind" => "secular"
       }}

  def preset(_id), do: {:error, :unsupported_profile}

  @spec valid?(profile :: term()) :: boolean()
  def valid?(%{"id" => id} = profile), do: preset(id) == {:ok, profile}
  def valid?(_profile), do: false
end
