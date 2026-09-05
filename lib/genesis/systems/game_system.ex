defmodule Genesis.Systems.GameSystem do
  @moduledoc "Pure variable game-system operations and declarative sheet metadata."
  @callback metadata(bundle :: map()) :: map()
  @callback validate_character(bundle :: map(), character :: map()) :: :ok | {:error, atom()}
  @callback resolve(
              bundle :: map(),
              character :: map(),
              action_id :: String.t(),
              draws :: [integer()]
            ) ::
              {:ok, map(), map()} | {:error, atom()}
end
