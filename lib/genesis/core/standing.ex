defmodule Genesis.Core.Standing do
  @moduledoc "A reported contribution changes one institution's standing, not universal reputation or local membership."
  alias Genesis.Core.Scope
  @spec new() :: map()
  def new,
    do: %{
      "version" => 1,
      "standing" => 0,
      "relief_supported" => false,
      "sources" => [],
      "audience_users" => []
    }

  @spec valid?(value :: term()) :: boolean()
  def valid?(
        %{
          "version" => 1,
          "standing" => n,
          "relief_supported" => flag,
          "sources" => sources,
          "audience_users" => users
        } = data
      ),
      do:
        map_size(data) == 5 and ids?(sources, 200) and ids?(users, 256) and
          n == length(sources) and flag == n > 0

  def valid?(_data), do: false

  defp ids?(ids, max) when is_list(ids),
    do: length(ids) <= max and Enum.all?(ids, &Scope.id?/1) and Enum.uniq(ids) == ids

  defp ids?(_ids, _max), do: false
  @spec report(before :: map(), source :: String.t(), audience :: [String.t()]) :: term()
  def report(before, source, audience) do
    cond do
      not valid?(before) or not Scope.id?(source) or not ids?(audience, 256) ->
        {:error, :invalid_standing}

      source in before["sources"] ->
        {:ok, before}

      length(before["sources"]) >= 200 ->
        {:error, :capacity_limit}

      true ->
        users =
          if before["sources"] == [],
            do: audience,
            else: Enum.filter(before["audience_users"], &(&1 in audience))

        next = %{
          before
          | "standing" => before["standing"] + 1,
            "relief_supported" => true,
            "sources" => before["sources"] ++ [source],
            "audience_users" => Enum.sort(Enum.uniq(users))
        }

        if valid?(next), do: {:ok, next}, else: {:error, :invalid_standing}
    end
  end
end
