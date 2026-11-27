defmodule Citlalpol.Swallow do
  @moduledoc """
  From the records to access.json (docs/design.md, "From the records to access.json"):

  - `citl swallow [--run <id>] [--label <l>] [--since 10m]`: the refused attempts, one row a destination,
    as a small table -- printed, and written to `<runtime>/swallow/last.tsv`, replacing the one before
    (temporary: gone with the next swallow, a logout or a reboot). Tab-separated, read with `cat`.
  - `citl digest <ref> pass | to <host>:<port> | refuse [--why "…"]`: a destination written into the
    project's access.json (first, as the first that matches decides). Never the copy in force:
    `citl read` applies it, as any change.
  - `citl residual <name>`: the last table kept as `<state>/swallow/<name>.tsv` (replaced without asking).

  All three only outside the wall: what was refused must not be learned from inside, and the records are
  hidden there anyway.
  """
  alias Citlalpol.{Access, Json, Paths, Records}

  # command: what the process said of itself (can be anything); exe: what the kernel ran
  @cols ~w(id host port proto stopped count access command exe last why)
  @cmd_shown 48

  defp die(msg) do
    IO.puts(:stderr, "citl: #{msg}")
    System.halt(1)
  end

  defp outside!(what) do
    if System.get_env("FORBIDDEN_ACTIVE"), do: die("#{what} works only from outside the wall")
  end

  def last_file, do: Path.join([Paths.runtime(), "swallow", "last.tsv"])
  def kept_dir, do: Path.join(Paths.state(), "swallow")
  # what digest wrote last, per name: the project's file may differ from the copy by that much only
  defp digested_file, do: Path.join(kept_dir(), "digested.json")

  # -- swallow ------------------------------------------------------------------------------
  def swallow(args) do
    outside!("citl swallow")
    o = opts(args, %{})
    refused = Records.all() |> Enum.filter(&(&1["decision"] == "refuse" and is_binary(&1["host"])))

    {o, range} =
      if o[:run] || o[:label] || o[:since] do
        {o, range_text(o)}
      else
        case refused |> Enum.filter(& &1["run"]) |> List.last() do
          nil -> {o, "the last run"}
          r -> {Map.put(o, :run, r["run"]), "run=#{r["run"]}"}
        end
      end

    rows =
      refused
      |> Enum.filter(fn r ->
        (o[:run] == nil or r["run"] == o[:run]) and (o[:label] == nil or r["label"] == o[:label]) and
          (o[:since] == nil or at(r) >= o[:since])
      end)
      |> Enum.group_by(fn r -> {r["host"], port_of(r), r["proto"], r["access"]} end)
      |> Enum.map(fn {{host, port, proto, access}, rs} ->
        last = List.last(rs)

        most = fn k -> rs |> Enum.map(&(&1[k] || "")) |> Enum.frequencies() |> Enum.max_by(fn {_, n} -> n end) |> elem(0) end
        cmd = most.("cmd")

        %{
          "host" => host,
          "port" => port,
          "proto" => to_string(proto || "?"),
          "stopped" => if(proto == "dns", do: "dns", else: "connect"),
          "count" => "#{length(rs)}",
          "access" => to_string(access || "-"),
          "command" => shorten(cmd),
          "exe" => shorten(most.("exe")),
          "last" => String.slice(last["at"] || "", 5, 14) |> String.replace("T", " "),
          "why" => to_string(last["why"] || ""),
          "_at" => last["at"] || ""
        }
      end)
      |> Enum.sort_by(& &1["_at"])
      |> Enum.with_index(1)
      |> Enum.map(fn {r, i} -> Map.put(r, "id", "#{i}") end)

    text =
      "# citl swallow #{range} #{Records.now_iso()} (refused attempts; citl digest <id> pass | to <host>:<port> | refuse)\n" <>
        Enum.join(@cols, "\t") <> "\n" <>
        Enum.map_join(rows, "", fn r -> Enum.map_join(@cols, "\t", &clean(r[&1])) <> "\n" end)

    File.mkdir_p!(Path.dirname(last_file()))
    File.chmod!(Path.dirname(last_file()), 0o700)
    File.write!(last_file() <> ".tmp", text)
    File.rename!(last_file() <> ".tmp", last_file())
    IO.write(text)
    if rows == [], do: IO.puts(:stderr, "citl: nothing was refused in #{range}")
  end

  defp opts([], o), do: o
  defp opts(["--run", v | t], o), do: opts(t, Map.put(o, :run, v))
  defp opts(["--label", v | t], o), do: opts(t, Map.put(o, :label, v))

  defp opts(["--since", v | t], o) do
    case Regex.run(~r/^(\d+)([smhd])$/, v) do
      [_, n, u] -> opts(t, Map.put(o, :since, System.os_time(:second) - String.to_integer(n) * %{"s" => 1, "m" => 60, "h" => 3600, "d" => 86400}[u]))
      nil -> die("swallow: --since 10s | 10m | 2h | 1d")
    end
  end

  defp opts([a | _], _), do: die("usage: citl swallow [--run <id>] [--label <l>] [--since 10m] (not #{a})")

  defp range_text(o) do
    [o[:run] && "run=#{o[:run]}", o[:label] && "label=#{o[:label]}", o[:since] && "since=#{o[:since]}"]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
  end

  # a DNS question names no port of the destination (53 is the question's own)
  defp port_of(%{"proto" => "dns"}), do: "-"
  defp port_of(r), do: if(r["port"], do: "#{r["port"]}", else: "-")

  defp shorten(cmd), do: if(String.length(cmd) > @cmd_shown, do: String.slice(cmd, 0, @cmd_shown - 1) <> "…", else: cmd)

  # a cell is one line without tabs
  defp clean(v), do: v |> to_string() |> String.replace(~r/[\t\r\n\x00-\x1f\x7f]/u, " ")

  defp at(r) do
    case DateTime.from_iso8601(r["at"] || "") do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  # -- residual -----------------------------------------------------------------------------
  def residual([name]) do
    outside!("citl residual")
    if not (name =~ ~r/^[A-Za-z0-9_-]{1,64}$/), do: die("residual: a name of letters, digits, _ - (no dot: <name>:<id> must not look like a host)")
    if not File.exists?(last_file()), do: die("residual: no small table (citl swallow first; it is gone after a logout or a reboot)")
    File.mkdir_p!(kept_dir())
    dest = Path.join(kept_dir(), name <> ".tsv")
    File.cp!(last_file(), dest <> ".tmp")
    File.rename!(dest <> ".tmp", dest)
    IO.puts("citl: kept as #{dest} (citl digest #{name}:<id> …)")
  end

  def residual(_), do: die("usage: citl residual <name>")

  # -- digest -------------------------------------------------------------------------------
  def digest(args) do
    outside!("citl digest")
    {ref, act, o} = digest_args(args)
    {host, port, name} = resolve(ref, o[:name])

    entry =
      [{"host", host}] ++
        if(port, do: [{"port", port}], else: []) ++
        case act do
          :pass -> [{"do", "pass"}]
          :refuse -> [{"do", "refuse"}]
          {:to, to} -> [{"do", "pass"}, {"to", to}]
        end ++ if(o[:why], do: [{"why", o[:why]}], else: [])

    if String.starts_with?(host, "*") and act != :refuse,
      do: die("digest: *. only with refuse -- with pass every name under it is resolved for real (docs/scope.md); declare each host by its own name")

    reg = Access.registered()

    src =
      case reg[name] do
        %{"source" => s} -> s
        nil -> die("#{inspect(name)} is not registered (citl read <access.json> #{name})")
        _ -> die("#{inspect(name)} was read before copies were taken: citl read it again first")
      end

    bytes =
      case File.read(src) do
        {:ok, b} -> b
        _ -> die("cannot read #{src}")
      end

    digested = Json.read(digested_file(), %{})
    digested = if is_map(digested), do: digested, else: %{}
    h = Access.sha256(bytes)

    if h != reg[name]["sha256"] and h != digested[name],
      do: die("#{src} differs from the copy in force (citl status): only what digest wrote may come in with the next citl read -- look at it, then citl read it")

    {a, bad} = Access.check(src)
    if bad != [], do: die(Enum.join(["#{src} is not usable:" | bad], "\n  "))

    hit =
      if port,
        do: Access.lookup(a, host, port),
        else: Enum.find(a["destinations"], &Access.matches?(&1["host"], host))

    case hit do
      nil -> :ok
      %{"do" => "refuse"} = d -> die("#{Access.rule(d)} is refused on purpose in #{src}#{if d["why"], do: " (#{d["why"]})"}: change it by hand")
      d -> die("#{Access.rule(d)} is declared already in #{src} (do: #{d["do"]}#{if d["to"], do: ", to #{d["to"]}"}): its refusal had another reason -- see the table's why")
    end

    new = insert(bytes, entry, a)

    case check_text(new, src) do
      {a2, []} ->
        if a2["destinations"] != [Map.new(entry) | a["destinations"]], do: die("digest: could not place the destination in #{src}; add it by hand")

      {_, bad} ->
        die(Enum.join(["digest: the result would not be usable:" | bad], "\n  "))
    end

    File.write!(src <> ".tmp", new)
    File.rename!(src <> ".tmp", src)
    Json.write(digested_file(), Map.put(digested, name, Access.sha256(new)))
    IO.puts("citl: added to #{src}:")
    IO.puts("  " <> encode(entry))
    IO.puts("not in force until: citl read #{src} #{name}")
  end

  defp digest_args([ref | rest]) do
    {act, rest} =
      case rest do
        ["pass" | t] -> {:pass, t}
        ["refuse" | t] -> {:refuse, t}
        ["to", to | t] -> {{:to, to}, t}
        _ -> die(~s(digest: what to do is written: pass | to <host>:<port> | refuse))
      end

    o = digest_opts(rest, %{})

    case act do
      {:to, to} ->
        case Access.parse_to(to) do
          {:ok, _} -> :ok
          {:error, why} -> die("digest: to #{inspect(to)}: #{why}")
        end

      _ ->
        :ok
    end

    {ref, act, o}
  end

  defp digest_args(_), do: die(~s(usage: citl digest <id | name:id | host[:port]> pass | to <host>:<port> | refuse [--why "…"] [--name <access>]))

  defp digest_opts([], o), do: o
  defp digest_opts(["--why", v | t], o), do: digest_opts(t, Map.put(o, :why, v))
  defp digest_opts(["--name", v | t], o), do: digest_opts(t, Map.put(o, :name, v))
  defp digest_opts([a | _], _), do: die("digest: unknown option #{a}")

  # -> {host, port | nil, access name}
  defp resolve(ref, name) do
    cond do
      ref =~ ~r/^\d+$/ ->
        from_table(last_file(), ref, name, "the last small table (citl swallow first)")

      (m = Regex.run(~r/^([A-Za-z0-9_-]{1,64}):(\d+)$/, ref)) && File.exists?(Path.join(kept_dir(), Enum.at(m, 1) <> ".tsv")) ->
        [_, n, id] = m
        from_table(Path.join(kept_dir(), n <> ".tsv"), id, name, "the kept table #{n}")

      m = Regex.run(~r/^([A-Za-z0-9*._-]+)(?::(\d{1,5}))?$/, ref) ->
        port = case m do
          [_, _, p] -> String.to_integer(p)
          _ -> nil
        end

        {Enum.at(m, 1), port, name || only_name()}

      true ->
        die("digest: #{inspect(ref)} is neither a row (3, <name>:3) nor a destination (host, host:port, an IPv4 address)")
    end
  end

  defp only_name do
    case Map.keys(Access.registered()) do
      [n] -> n
      _ -> die("digest: which access.json? --name <name> (citl status lists them)")
    end
  end

  defp from_table(file, id, name, what) do
    rows =
      case File.read(file) do
        {:ok, s} -> s |> String.split("\n", trim: true) |> Enum.reject(&String.starts_with?(&1, "#"))
        _ -> die("digest: no #{what}")
      end

    [head | body] = if rows == [], do: die("digest: #{what} is empty"), else: rows
    cols = String.split(head, "\t")

    row =
      Enum.find_value(body, fn l ->
        r = Enum.zip(cols, String.split(l, "\t")) |> Map.new()
        if r["id"] == id, do: r
      end) || die("digest: no row #{id} in #{what}")

    port = if row["port"] in [nil, "-", ""], do: nil, else: String.to_integer(row["port"])
    n = name || if(row["access"] in [nil, "-", ""], do: die("digest: row #{id} has no access.json (none applied): --name <name>"), else: row["access"])
    {row["host"], port, n}
  end

  defp check_text(text, src) do
    tmp = Path.join(Path.dirname(src), ".citl-digest-#{System.unique_integer([:positive])}.json")
    File.write!(tmp, text)

    try do
      Access.check(tmp)
    after
      File.rm(tmp)
    end
  end

  # the entry put first in "destinations", the rest of the file as the person wrote it
  defp insert(bytes, entry, a) do
    case Regex.run(~r/"destinations"\s*:\s*\[/, bytes, return: :index) do
      [{i, l}] ->
        {head, tail} = String.split_at(bytes, i + l)
        indent = case Regex.run(~r/\A\s*\n([ \t]*)\S/, tail) do
          [_, ind] -> ind
          _ -> "    "
        end

        sep = if a["destinations"] == [], do: "", else: ","
        head <> "\n" <> indent <> encode(entry) <> sep <> if(String.starts_with?(tail, "\n"), do: "", else: " ") <> tail

      _ ->
        JSON.encode!(Map.put(a, "destinations", [Map.new(entry)])) <> "\n"
    end
  end

  defp encode(entry), do: "{ " <> Enum.map_join(entry, ", ", fn {k, v} -> JSON.encode!(k) <> ": " <> JSON.encode!(v) end) <> " }"
end
