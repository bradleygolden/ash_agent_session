defmodule AshAgentSession.LLMStub do
  @moduledoc false

  @spec object_response(map()) :: (Plug.Conn.t() -> Plug.Conn.t())
  def object_response(object_data) when is_map(object_data) do
    fn conn ->
      string_key_data = atomize_keys_to_strings(object_data)

      Req.Test.json(conn, %{
        "id" => "msg_#{:rand.uniform(1000)}",
        "type" => "message",
        "role" => "assistant",
        "content" => [
          %{
            "type" => "tool_use",
            "id" => "toolu_#{:rand.uniform(1000)}",
            "name" => "structured_output",
            "input" => string_key_data
          }
        ],
        "model" => "claude-3-5-sonnet-20241022",
        "stop_reason" => "tool_use",
        "usage" => %{
          "input_tokens" => 10,
          "output_tokens" => 20
        }
      })
    end
  end

  defp atomize_keys_to_strings(map) when is_map(map) do
    Map.new(map, fn {k, v} ->
      key = if is_atom(k), do: Atom.to_string(k), else: k
      {key, atomize_keys_to_strings(v)}
    end)
  end

  defp atomize_keys_to_strings(value), do: value

  @spec error_response(integer(), String.t()) :: (Plug.Conn.t() -> Plug.Conn.t())
  def error_response(status \\ 500, message \\ "Internal server error") do
    fn conn ->
      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{
        "error" => %{
          "type" => "api_error",
          "message" => message
        }
      })
    end
  end
end
