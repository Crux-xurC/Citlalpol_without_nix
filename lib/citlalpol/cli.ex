defmodule Citlalpol.CLI do
  @moduledoc """
  citl's commands but `run` (bin/citl hands the terminal to forbidden itself, after `run-prepare`).
  """
  alias Citlalpol.{Access, Citld, Json, Paths, Records, Swallow}

  @usage """
      citl start | stop | status          citld in the background (citl serve: in the foreground)
      citl setup [--no-catch-all]         forbidden's door "citlalpol" (127.0.0.1:4600 inside the wall -> citld); it also
                                          catches what ignores the proxy, and the wall's DNS (needs nftables)
      citl read <access.json> [<name>]    check an access.json and take a copy of it under a name: the copy is what
                                          applies, until it is read again (from outside the wall)
      citl use <name> | --none            what applies to a wall without a run of citl (forbidden on --door citlalpol)
      citl run [<name>] [forbidden options] -- <command> [args...]
                                          forbidden run --door citlalpol, with <name>'s access.json
      citl label <run> <label> | --clear  name what a run is doing now (e.g. the row being evaluated); outside the wall only
      citl log [--run <id>] [--label <l>] [--since 10m] [--decision refuse|pass] [--json]
      citl swallow [--run <id>] [--label <l>] [--since 10m]
                                          the refused attempts, one row a destination, as a small table (default:
                                          the last run); temporary, read it again with cat (printed where)
      citl digest <id | name:id | host[:port]> pass | to <host>:<port> | refuse [--why "…"] [--name <access>]
                                          write that destination into the project's access.json (first); citl read
                                          applies it
      citl residual <name>                keep the last small table (<name>:<id> in digest); replaced without asking

  Scope (what is promised, what is not): docs/scope.md
  """
  # citl log: the process's command line shown up to this many characters (… when cut; --json has it all)
  @cmd_shown 48

  def main(["serve"]), do: Citld.serve()

  # a reader that stops early (citl status | grep -q, citl log | head) ends the command quietly
  def main(args) do
    :logger.set_primary_config(:level, :none)

    try do
      run(args)
    rescue
      e in ErlangError -> if e.original == :terminated, do: System.halt(0), else: reraise(e, __STACKTRACE__)
    end
  end

  defp run(["start"]), do: start()
  defp run(["stop"]), do: stop()
  defp run(["status"]), do: status()
  defp run(["setup"]), do: setup(true)
  defp run(["setup", "--no-catch-all"]), do: setup(false)
  defp run(["label" | rest]), do: label(rest)
  defp run(["read" | rest]), do: read(rest)
  defp run(["use" | rest]), do: use_access(rest)
  defp run(["run-prepare" | rest]), do: run_prepare(rest)
  defp run(["log" | rest]), do: log(rest)
  defp run(["swallow" | rest]), do: Swallow.swallow(rest)
  defp run(["digest" | rest]), do: Swallow.digest(rest)
  defp run(["residual" | rest]), do: Swallow.residual(rest)
  defp run([h]) when h in ["help", "-h", "--help"], do: IO.write(@usage)
  defp run([]), do: IO.write(@usage)
  defp run([c | _]), do: die("unknown command #{c} (citl help)")

  defp die(msg) do
    IO.puts(:stderr, "citl: #{msg}")
    System.halt(1)
  end

  # -- citld --------------------------------------------------------------------------------
  def running do
    with {:ok, s} <- File.read(Paths.pidfile()),
         {pid, _} <- Integer.parse(String.trim(s)),
         {_, 0} <- System.cmd("kill", ["-0", "#{pid}"], stderr_to_stdout: true) do
      pid
    else
      _ -> nil
    end
  end

  defp start do
    if pid = running() do
      IO.puts("citld: running already (pid #{pid})")
    else
      File.mkdir_p!(Paths.state())
      log = Path.join(Paths.state(), "citld.log")
      citl = Path.join(Paths.dir(), "bin/citl")
      System.cmd("sh", ["-c", ~s(exec setsid -f "$0" serve >>"$1" 2>&1 </dev/null), citl, log])

      if wait(150, fn -> File.exists?(Paths.door()) end),
        do: IO.puts("citld: started (door #{Paths.door()})"),
        else: die("citld did not start (see #{log})")
    end
  end

  defp stop do
    case running() do
      nil ->
        IO.puts("citld: not running")

      pid ->
        System.cmd("kill", ["-TERM", "#{pid}"])
        wait(50, fn -> running() == nil end)
        IO.puts("citld: stopped")
    end
  end

  defp wait(0, _), do: false

  defp wait(n, f) do
    if f.() do
      true
    else
      Process.sleep(100)
      wait(n - 1, f)
    end
  end

  defp status do
    IO.puts("citld: " <> if(pid = running(), do: "running (pid #{pid}), door #{Paths.door()}", else: "not running"))
    reg = Access.registered()
    u = case File.read(Paths.use_file()) do
      {:ok, s} -> String.trim(s)
      _ -> ""
    end

    for {n, e} <- Enum.sort(reg) do
      src = if is_map(e), do: e["source"], else: e

      note =
        cond do
          not is_map(e) -> "  (read before copies were taken: citl read it again)"
          Access.changed?(e) -> "  (changed since it was read #{e["read_at"]}: not in force until citl read)"
          true -> ""
        end

      IO.puts("  #{if n == u, do: "*", else: " "}#{String.pad_trailing(n, 12)} #{src}#{note}")
    end
    if reg == %{}, do: IO.puts("  (no access.json registered: citl read <access.json>)")
  end

  # -- forbidden ----------------------------------------------------------------------------
  defp forbidden do
    sibling = Path.join([Path.dirname(Paths.dir()), "forbidden", "bin", "forbidden"])

    System.get_env("CITLALPOL_FORBIDDEN") || System.find_executable("forbidden") ||
      if(File.exists?(sibling), do: sibling) ||
      die("forbidden is not found (put it on PATH, or CITLALPOL_FORBIDDEN=<path>)")
  end

  defp setup(catch_all) do
    # what a program inside must neither read nor change: the copies of access.json, labels' and runs'
    # names, the records
    for dir <- [Paths.config(), Paths.state()] do
      File.mkdir_p!(dir)
      {_, c} = System.cmd(forbidden(), ["hide", "add", dir], into: IO.stream(), stderr_to_stdout: true)
      if c != 0, do: System.halt(c)
    end

    # zoozve's gates answer Citlalpol's challenge with this key (`to` reaches only a gate)
    if not File.exists?(Paths.zoozve_key()) do
      File.write!(Paths.zoozve_key(), "")
      File.chmod!(Paths.zoozve_key(), 0o600)
      File.write!(Paths.zoozve_key(), Base.encode16(:crypto.strong_rand_bytes(32), case: :lower) <> "\n")
      IO.puts("citl: the key for zoozve's gates is #{Paths.zoozve_key()}")
    end

    {_, code} =
      System.cmd(
        forbidden(),
        ["door", "add", "citlalpol", "--port", "#{Paths.port()}", "--socket", Paths.door(), "--proxy-protocol", "v2"] ++
          if(catch_all, do: ["--catch-all"], else: []),
        into: IO.stream(), stderr_to_stdout: true
      )

    if code != 0, do: System.halt(code)
  end

  # -- labels -------------------------------------------------------------------------------
  # Set only from outside the wall: the labels' directory is in the runtime directory, which the wall
  # hides; inside, a program cannot name its own attempts.
  defp label([run | rest]) when rest != [] do
    if System.get_env("FORBIDDEN_ACTIVE"), do: die("labels are set only from outside the wall")
    if not (run =~ ~r/^[A-Za-z0-9._-]{1,128}$/), do: die("label: a run id (citl run says it; forbidden status inside)")
    file = Path.join(Paths.labels(), run)

    case rest do
      ["--clear"] ->
        File.rm(file)
        IO.puts("citl: run #{run} has no label")

      words ->
        l = words |> Enum.join(" ") |> String.replace(~r/[\x00-\x1f\x7f]/u, " ") |> String.trim()
        if l == "" or byte_size(l) > 200, do: die("label: 1-200 bytes")
        File.mkdir_p!(Paths.labels())
        File.chmod!(Paths.labels(), 0o700)
        File.write!(file <> ".tmp", l <> "\n")
        File.rename!(file <> ".tmp", file)
        IO.puts("citl: run #{run} is now #{inspect(l)}")
    end
  end

  defp label(_), do: die("usage: citl label <run> <label> | --clear")

  # -- access.json --------------------------------------------------------------------------
  defp read([file | rest]) when length(rest) <= 1 do
    path = Path.expand(file)

    if System.get_env("FORBIDDEN_ACTIVE"), do: die("access.json is read only from outside the wall")

    case Access.check(path) do
      {a, []} ->
        name = List.first(rest) || a["name"] || Path.basename(Path.dirname(path))
        if not Access.valid_name?(name), do: die("read: a name of letters, digits, . _ - (not #{inspect(name)})")
        bytes = File.read!(path)
        copy = Path.join(Paths.copies(), name <> ".json")
        File.mkdir_p!(Paths.copies())
        File.write!(copy <> ".tmp", bytes)
        File.rename!(copy <> ".tmp", copy)

        entry = %{"source" => path, "copy" => copy, "sha256" => Access.sha256(bytes), "read_at" => Records.now_iso()}
        Json.write(Paths.registered(), Map.put(Access.registered(), name, entry))
        IO.puts("citl: #{path} read as #{inspect(name)} (in force: this copy, until it is read again)")

        for d <- a["destinations"] do
          what =
            case d do
              %{"do" => "refuse"} -> "refused"
              %{"to" => to} -> "to #{to} (local: only a zoozve gate answers)"
              _ -> "pass to the real one"
            end

          IO.puts("  #{String.pad_trailing(Access.rule(d), 28)} #{what}")
        end

        IO.puts("  #{String.pad_trailing("anything else", 28)} refused (not in access.json)")

      {_, bad} ->
        die(Enum.join(["#{path} is not used:" | bad], "\n  "))
    end
  end

  defp read(_), do: die("usage: citl read <access.json> [<name>]")

  defp use_access(["--none"]) do
    File.rm(Paths.use_file())
    IO.puts("citl: no access.json for walls without a run of citl (everything refused)")
  end

  defp use_access([name]) do
    if not Map.has_key?(Access.registered(), name), do: die("#{inspect(name)} is not registered (citl read <access.json> #{name})")
    File.mkdir_p!(Paths.config())
    File.write!(Paths.use_file(), name <> "\n")
    IO.puts("citl: walls without a run of citl use #{inspect(name)}")
  end

  defp use_access(_), do: die("usage: citl use <a registered name> | --none")

  # -> "<run id>\t<forbidden>" on stdout, for bin/citl to exec forbidden with
  defp run_prepare(args) do
    name = List.first(args, "")

    if name != "" and not Map.has_key?(Access.registered(), name),
      do: die("#{inspect(name)} is not registered (citl read <access.json> #{name})")

    if running() == nil, do: die("citld is not running (citl start)")
    f = forbidden()
    {{y, mo, d}, {h, mi, s}} = :calendar.local_time()
    stamp = :io_lib.format(~c"~4..0B~2..0B~2..0B-~2..0B~2..0B~2..0B", [y, mo, d, h, mi, s]) |> IO.iodata_to_binary()
    id = "c-#{stamp}-#{System.pid()}"
    File.mkdir_p!(Paths.runs())
    File.write!(Path.join(Paths.runs(), id), name <> "\n")
    IO.puts(:stderr, "citl: run #{id}" <> if(name != "", do: " with #{inspect(name)}", else: ""))
    IO.puts("#{id}\t#{f}")
  end

  # -- the records --------------------------------------------------------------------------
  defp log(args) do
    o = log_opts(args, %{})

    Records.all()
    |> Stream.filter(fn r ->
      (o[:run] == nil or r["run"] == o[:run]) and (o[:decision] == nil or r["decision"] == o[:decision]) and
        (o[:label] == nil or r["label"] == o[:label]) and
        (o[:since] == nil or at(r) >= o[:since])
    end)
    |> Enum.each(fn r -> IO.puts(if o[:json], do: Records.encode(r), else: line(r)) end)
  end

  defp log_opts([], o), do: o
  defp log_opts(["--run", v | t], o), do: log_opts(t, Map.put(o, :run, v))
  defp log_opts(["--decision", v | t], o), do: log_opts(t, Map.put(o, :decision, v))
  defp log_opts(["--label", v | t], o), do: log_opts(t, Map.put(o, :label, v))
  defp log_opts(["--json" | t], o), do: log_opts(t, Map.put(o, :json, true))

  defp log_opts(["--since", v | t], o) do
    case Regex.run(~r/^(\d+)([smhd])$/, v) do
      [_, n, u] -> log_opts(t, Map.put(o, :since, System.os_time(:second) - String.to_integer(n) * %{"s" => 1, "m" => 60, "h" => 3600, "d" => 86400}[u]))
      nil -> die("log: --since 10s | 10m | 2h | 1d")
    end
  end

  defp log_opts([a | _], _), do: die("log: unknown option #{a}")

  defp at(r) do
    case DateTime.from_iso8601(r["at"] || "") do
      {:ok, dt, _} -> DateTime.to_unix(dt)
      _ -> 0
    end
  end

  defp line(r) do
    t = String.slice(r["at"] || "", 11, 8)
    head = "#{t} #{String.pad_trailing(to_string(r["decision"] || "?"), 8)} #{String.pad_trailing(to_string(r["proto"] || "?"), 7)} #{r["host"] || "?"}:#{r["port"] || "?"}"
    req = [r["method"], r["path"]] |> Enum.reject(&is_nil/1) |> Enum.join(" ")
    cmd = to_string(r["cmd"] || "")
    cmd = if String.length(cmd) > @cmd_shown, do: String.slice(cmd, 0, @cmd_shown - 1) <> "…", else: cmd
    extra = r["why"] || if(r["sent_to"], do: "-> #{r["sent_to"]}", else: if(r["answer"], do: "= #{r["answer"]}", else: ""))

    [head, req, if(r["label"], do: "{#{r["label"]}}", else: ""), if(cmd != "", do: "[#{cmd}]", else: ""), extra]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("  ")
  end
end
