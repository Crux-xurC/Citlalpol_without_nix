defmodule Citlalpol.Records do
  @moduledoc """
  The records: one JSON line per attempt, in a file per local day (`<state>/records/YYYY-MM-DD.jsonl`).
  One process writes them, so lines never interleave. The keys come in a fixed order for people reading
  the files; tezcatl's Citlalpol panels and `citl log` read them as JSON.
  """
  use GenServer
  alias Citlalpol.Paths

  @order ~w(at run label pid cmd exe mode door via proto host address port method path access rule decision sent_to to_auth answer bytes_up bytes_down ms why)

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: {:ok, nil}

  def write(rec), do: GenServer.call(__MODULE__, {:write, rec})

  @impl true
  def handle_call({:write, rec}, _from, s) do
    File.mkdir_p!(Paths.records())
    File.write!(Path.join(Paths.records(), today() <> ".jsonl"), encode(rec) <> "\n", [:append])
    {:reply, :ok, s}
  end

  def encode(rec) do
    known = for k <- @order, Map.has_key?(rec, k), do: {k, rec[k]}
    rest = rec |> Map.drop(@order) |> Enum.sort()
    "{" <> Enum.map_join(known ++ rest, ", ", fn {k, v} -> JSON.encode!(k) <> ": " <> JSON.encode!(v) end) <> "}"
  end

  @doc "local time with milliseconds and the offset: 2026-11-25T07:42:00.123+09:00"
  def now_iso do
    ms = System.os_time(:millisecond)
    s = div(ms, 1000)
    local = :calendar.system_time_to_local_time(s, :second)
    utc = :calendar.system_time_to_universal_time(s, :second)
    off = :calendar.datetime_to_gregorian_seconds(local) - :calendar.datetime_to_gregorian_seconds(utc)
    {{y, mo, d}, {h, mi, se}} = local
    a = abs(off)

    :io_lib.format(~c"~4..0B-~2..0B-~2..0BT~2..0B:~2..0B:~2..0B.~3..0B~s~2..0B:~2..0B", [
      y, mo, d, h, mi, se, rem(ms, 1000), if(off < 0, do: "-", else: "+"), div(a, 3600), div(rem(a, 3600), 60)
    ])
    |> IO.iodata_to_binary()
  end

  defp today do
    {{y, m, d}, _} = :calendar.local_time()
    :io_lib.format(~c"~4..0B-~2..0B-~2..0B", [y, m, d]) |> IO.iodata_to_binary()
  end

  @doc "every record, oldest first (lines that are not JSON are skipped)"
  def all do
    case File.ls(Paths.records()) do
      {:ok, days} ->
        days
        |> Enum.filter(&String.ends_with?(&1, ".jsonl"))
        |> Enum.sort()
        |> Stream.flat_map(fn day -> File.stream!(Path.join(Paths.records(), day)) end)
        |> Stream.flat_map(fn line ->
          case JSON.decode(line) do
            {:ok, %{} = r} -> [r]
            _ -> []
          end
        end)

      {:error, _} ->
        []
    end
  end
end
