defmodule Genesis.Travel do
  @moduledoc "Preview and confirm bounded movement of your bound participant within an Experience."
  alias Genesis.Engine.Runtime
  alias Genesis.Persistence.Transfers

  @spec preview(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          actor :: String.t(),
          destination :: String.t()
        ) :: term()
  defdelegate preview(scope, world, experience, actor, destination), to: Transfers

  @spec preview(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          actor :: String.t(),
          destination :: String.t(),
          exchange :: map() | nil
        ) :: term()
  defdelegate preview(scope, world, experience, actor, destination, exchange), to: Transfers

  @spec move(
          scope :: term(),
          world :: String.t(),
          experience :: String.t(),
          actor :: String.t(),
          token :: map(),
          request :: String.t()
        ) :: term()
  def move(scope, world, experience, actor, token, request),
    do: Runtime.call(scope, world, {:travel, experience, actor, token, request})
end
