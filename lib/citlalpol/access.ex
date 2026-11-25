defmodule Citlalpol.Access do
  @moduledoc """
  access.json, the project's declared destinations: `{"destinations": [{"host", "port"?, "do", "to"?,
  "why"?}]}`. `do` is pass or refuse; whatever is not declared is refused. `to` sends a pass
  to a local address the person runs instead of the real destination. A program to start is never written
  here: the file is committed with the project (docs/scope.md).

  What is in force is the copy `citl read` took (`<config>/access/<name>.json`), never the project's
  file: a program inside the wall can write the project, so a change counts only when a person reads
  it again from outside (the wall hides citl's config and records).
  """
  alias Citlalpol.{Json, Net, Paths}

  @dos ~w(pass refuse)

  @doc "-> {access | nil, problems}"
  def check(path) do
    case Json.read(path, nil) do
      nil ->
        {nil, ["cannot read #{path}: no such file"]}

      {:error, why} ->
        {nil, [why]}

      %{} = a ->
        case Map.get(a, "destinations", []) do
          ds when is_list(ds) ->
            {Map.put(a, "destinations", ds), ds |> Enum.with_index() |> Enum.flat_map(fn {d, i} -> problems(d, i) end)}

          _ ->
            {nil, [~s(#{path}: {"destinations": [...]} expected)]}
        end

      _ ->
        {nil, [~s(#{path}: {"destinations": [...]} expected)]}
    end
  end

  defp problems(%{"host" => h} = d, i) when is_binary(h) and h != "" do
    w = "destinations[#{i}] (#{h})"

    [
      unless d["do"] in @dos do
        "#{w}: do is pass or refuse" <>
          if(d["do"] == "stand_in",
            do: " -- what answers is not Citlalpol's (docs/scope.md): run it yourself and name its address with to",
            else: ""
          )
      end,
      if(Map.has_key?(d, "port") and not port?(d["port"]), do: "#{w}: port 1-65535"),
      if(Map.has_key?(d, "exec") or Map.has_key?(d, "command"),
        do: "#{w}: a program to start is never written here -- run it yourself and name its address with to"
      ),
      if(Map.has_key?(d, "as") or Map.has_key?(d, "stages"),
        do: "#{w}: as / stages are not Citlalpol's (docs/scope.md) -- name a local address with to"
      ),
      if(Map.has_key?(d, "allow_local"),
        do: "#{w}: allow_local is gone (docs/scope.md) -- a local server is reached only with to"
      ),
      to_problem(d, w)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp problems(_, i), do: ["destinations[#{i}]: a host is needed"]

  defp to_problem(%{"to" => to} = d, w) do
    cond do
      d["do"] != "pass" ->
        "#{w}: to goes with do: pass"

      true ->
        case parse_to(to) do
          {:ok, {_, p}} ->
            if p in Net.never_ports(),
              do: "#{w}: to #{to} is a local program that can act outside the wall (tezcatl, Emacs, Xipe Totec ...): never"

          {:error, why} ->
            "#{w}: to #{inspect(to)}: #{why}"
        end
    end
  end

  defp to_problem(_, _), do: nil

  defp port?(p), do: is_integer(p) and p > 0 and p < 65536

  @doc "\"127.0.0.1:55432\", \"localhost:3306\", \"[::1]:8080\" -> {:ok, {host, port}}; only loopback"
  def parse_to(to) when is_binary(to) do
    hp =
      case Regex.run(~r/^\[([^\]]+)\]:(\d{1,5})$/, to) || Regex.run(~r/^([^:\[\]]+):(\d{1,5})$/, to) do
        [_, h, p] -> {h, String.to_integer(p)}
        nil -> nil
      end

    case hp do
      nil -> {:error, ~s("<host>:<port>" expected)}
      {_, p} when p < 1 or p > 65535 -> {:error, "port 1-65535"}
      {h, p} -> if Net.loopback_name?(h), do: {:ok, {h, p}}, else: {:error, "only a local address (127.0.0.1, ::1, localhost): a to elsewhere would be an undeclared exit"}
    end
  end

  def parse_to(_), do: {:error, ~s("<host>:<port>" expected)}

  def matches?(pattern, host) do
    p = pattern |> String.downcase() |> String.trim_trailing(".")
    h = host |> String.downcase() |> String.trim_trailing(".")

    case p do
      "*." <> rest -> String.ends_with?(h, "." <> rest) and h != rest
      _ -> p == h
    end
  end

  def lookup(access, host, port) do
    Enum.find(access["destinations"], fn d -> matches?(d["host"], host) and Map.get(d, "port", port) == port end)
  end

  def rule(d), do: d["host"] <> if(Map.has_key?(d, "port"), do: ":#{d["port"]}", else: "")

  @doc "name -> %{\"source\", \"copy\", \"sha256\", \"read_at\"} (an older plain path means: read it again)"
  def registered do
    case Json.read(Paths.registered(), %{}) do
      %{} = m -> m
      _ -> %{}
    end
  end

  def valid_name?(name), do: is_binary(name) and name =~ ~r/^[A-Za-z0-9._-]{1,64}$/ and name not in [".", ".."]

  def sha256(bytes), do: :crypto.hash(:sha256, bytes) |> Base.encode16(case: :lower)

  @doc "true when the project's file is no longer what was read"
  def changed?(%{"source" => src, "sha256" => h}) do
    case File.read(src) do
      {:ok, b} -> sha256(b) != h
      _ -> true
    end
  end

  def changed?(_), do: true

  @doc "{name, path, access} that applies to a run (or to walls without a run: citl use); nils when none"
  def for_run(run) do
    name = (run && read_trim(Path.join(Paths.runs(), Path.basename(to_string(run))))) || read_trim(Paths.use_file())

    case name && Map.get(registered(), name) do
      %{"copy" => copy} ->
        {a, bad} = check(copy)
        {name, copy, if(bad == [], do: a)}

      _ ->
        {name, nil, nil}
    end
  end

  defp read_trim(path) do
    case File.read(path) do
      {:ok, s} -> if String.trim(s) == "", do: nil, else: String.trim(s)
      _ -> nil
    end
  end
end
