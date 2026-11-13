defmodule Taamol.CitySearch do
  @moduledoc "City lookup using Open-Meteo's geocoding API."

  @endpoint "https://geocoding-api.open-meteo.com/v1/search"

  def search(query, language) do
    options =
      Application.get_env(:taamol, :city_search_req_options, [])
      |> Keyword.merge(
        params: [name: query, count: 10, language: language, format: "json"],
        receive_timeout: 5_000,
        retry: false
      )

    case Req.get(@endpoint, options) do
      {:ok, %Req.Response{status: 200, body: body}} when is_map(body) ->
        case body do
          %{"error" => true} ->
            {:error, :invalid_response}

          _ ->
            case Map.get(body, "results", []) do
              results when is_list(results) -> {:ok, Enum.flat_map(results, &city/1)}
              _ -> {:error, :invalid_response}
            end
        end

      {:ok, %Req.Response{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp city(
         %{
           "id" => id,
           "name" => name,
           "latitude" => lat,
           "longitude" => lng,
           "timezone" => timezone
         } = result
       )
       when is_integer(id) and is_binary(name) and is_number(lat) and is_number(lng) and
              is_binary(timezone) and lat > -90 and lat < 90 and lng >= -180 and lng <= 180 do
    parts =
      [name, result["admin1"], result["country"]]
      |> Enum.filter(&(is_binary(&1) and &1 != ""))
      |> Enum.uniq()

    label = Enum.join(parts, ", ")

    if String.length(label) <= 300 and String.length(timezone) <= 100 and
         Regex.match?(~r/^[A-Za-z0-9_+\/-]+$/, timezone) do
      [%{id: id, name: label, latitude: lat, longitude: lng, timezone: timezone}]
    else
      []
    end
  end

  defp city(_), do: []
end
