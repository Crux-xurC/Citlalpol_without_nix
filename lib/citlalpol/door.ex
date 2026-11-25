defmodule Citlalpol.Door do
  @moduledoc """
  One connection through forbidden's door: the PROXY protocol v2 header (forbidden's relay puts it in
  front; it is read and removed, never sent on), then SOCKS5 or an HTTP proxy request (an http:// URL, or
  CONNECT) -- or, from a door that catches all, a TCP connection that did not use the proxy (`via`
  "redirect": its destination is the header's) or DNS questions (`via` "dns", or TCP to port 53;
  Citlalpol.Dns). An address citld gave out for a name (Citlalpol.Fake) is judged as that name. The destination is looked up in the access.json that applies: refused, or passed to the real
  destination, or to the local address of `to`. Every attempt is one record, written before the refusal
  is answered (so a client that has its answer finds the record there).

  The record being built lives in the process dictionary: one process per connection, and a broken
  request at any step still leaves what was read so far.
  """
  alias Citlalpol.{Access, Dns, Fake, Net, Paths, Records, Redact}

  @sig <<"\r\n\r\n", 0, "\r\nQUIT\n">>
  @tlv %{0xE0 => "run", 0xE1 => "pid", 0xE2 => "cmd", 0xE3 => "mode", 0xE4 => "via"}
  @head_max 65_536
  @read_timeout 30_000
  @pass_timeout 15_000
  @to_timeout 5_000
  @gate_timeout 3_000

  def handle(client) do
    Process.put(:t0, System.monotonic_time(:millisecond))
    Process.put(:rec, %{"at" => Records.now_iso()})

    try do
      serve(client)
    rescue
      e -> broken(Exception.message(e))
    catch
      :throw, :empty -> :ok
      :throw, {:broken, why} -> broken(why)
    end

    rec = Process.get(:rec)

    if not Process.get(:written, false) and (Map.has_key?(rec, "proto") or Map.has_key?(rec, "why")) do
      Records.write(Map.put(rec, "ms", ms()))
    end

    :gen_tcp.close(client)
  end

  defp broken(why) do
    rec = Process.get(:rec)
    Process.put(:rec, rec |> Map.put_new("decision", "refuse") |> Map.put_new("why", "broken request: #{why}"))
  end

  defp ms, do: System.monotonic_time(:millisecond) - Process.get(:t0)

  defp put(m), do: Process.put(:rec, Map.merge(Process.get(:rec), m))
  defp get(k), do: Process.get(:rec)[k]

  # -- reading with a buffer ---------------------------------------------------------------
  defp fill(%{buf: buf} = st, n) when byte_size(buf) >= n, do: st

  defp fill(%{sock: s, buf: buf} = st, n) do
    case :gen_tcp.recv(s, 0, @read_timeout) do
      {:ok, d} -> fill(%{st | buf: buf <> d}, n)
      {:error, :closed} when buf == "" -> throw(:empty)
      {:error, :timeout} -> throw({:broken, "nothing more within #{div(@read_timeout, 1000)} s"})
      {:error, e} -> throw({:broken, to_string(:inet.format_error(e))})
    end
  end

  defp take(st, n) do
    %{buf: buf} = st = fill(st, n)
    {binary_part(buf, 0, n), %{st | buf: binary_part(buf, n, byte_size(buf) - n)}}
  end

  # -- the PROXY v2 header ------------------------------------------------------------------
  defp proxy_v2(st) do
    st = fill(st, 1) |> fill_while_signature()

    case st.buf do
      <<@sig, _vc, fam, len::16, _::binary>> ->
        {<<_::binary-16, body::binary>>, st} = take(st, 16 + len)
        skip = %{0x11 => 12, 0x21 => 36, 0x31 => 216}[fam] || 0
        tlvs = if byte_size(body) >= skip, do: binary_part(body, skip, byte_size(body) - skip), else: ""

        dst =
          case {fam, body} do
            {0x11, <<_src::32, a, b, c, d, _sp::16, dp::16, _::binary>>} -> {{a, b, c, d}, dp}
            _ -> nil
          end

        {Map.put(parse_tlvs(tlvs, %{}), "door", "proxy_v2"), dst, st}

      _ ->
        {%{"door" => "none"}, nil, st}
    end
  end

  # read on while what came is the start of the signature (a SOCKS5 or HTTP client sends less than 16
  # bytes and waits, so never read past a mismatch)
  defp fill_while_signature(%{buf: buf} = st) do
    n = min(byte_size(buf), 12)

    if byte_size(buf) < 16 and binary_part(buf, 0, n) == binary_part(@sig, 0, n),
      do: st |> fill(byte_size(buf) + 1) |> fill_while_signature(),
      else: st
  end

  defp parse_tlvs(<<t, len::16, v::binary-size(len), rest::binary>>, acc) do
    acc =
      case @tlv[t] do
        nil -> acc
        "pid" -> Map.put(acc, "pid", if(v =~ ~r/^\d+$/, do: String.to_integer(v), else: Redact.text(v)))
        k -> Map.put(acc, k, Redact.text(v))
      end

    parse_tlvs(rest, acc)
  end

  defp parse_tlvs(_, acc), do: acc

  # -- SOCKS5 or an HTTP proxy request -------------------------------------------------------
  defp serve(c) do
    {info, dst, st} = proxy_v2(%{sock: c, buf: ""})
    put(info)
    if get("cmd"), do: put(%{"cmd" => Redact.cmd(get("cmd"))})
    if label = label_of(get("run")), do: put(%{"label" => label})

    case {get("via"), dst} do
      {"dns", _} ->
        dns(st)

      {"redirect", {_ip, 53}} ->
        dns(st)

      {"redirect", {ip, port}} ->
        addr = to_string(:inet.ntoa(ip))
        host = Fake.name(ip) || addr
        put(%{"proto" => "tcp", "host" => host, "port" => port})
        if host != addr, do: put(%{"address" => addr})
        decide(st, :raw, host, port, st.buf)

      _ ->
        # what follows the header may not have come yet: its first byte tells SOCKS5 from HTTP
        st = fill(st, 1)

        case st.buf do
          <<5, _::binary>> -> socks5(st)
          _ -> http(st)
        end
    end
  end

  # the label set from outside the wall for this run (citl label), if any
  defp label_of(nil), do: nil

  defp label_of(run) do
    case File.read(Path.join(Paths.labels(), Path.basename(to_string(run)))) do
      {:ok, l} -> if String.trim(l) == "", do: nil, else: String.trim(l)
      _ -> nil
    end
  end

  # DNS over a stream: a 2-byte length, the message; one record per question
  defp dns(st) do
    {<<len::16>>, st} = take(st, 2)
    {q, st} = take(st, len)
    {a, fields} = Dns.answer(q, get("run"))
    Records.write(Process.get(:rec) |> Map.merge(fields) |> Map.put("ms", ms()))
    Process.put(:written, true)
    if a != "", do: :gen_tcp.send(st.sock, <<byte_size(a)::16, a::binary>>)

    if a != "" do
      Process.put(:rec, Map.take(Process.get(:rec), ~w(run pid cmd mode door via label)) |> Map.put("at", Records.now_iso()))
      Process.put(:t0, System.monotonic_time(:millisecond))
      dns(st)
    end
  end

  defp socks5(%{sock: c} = st) do
    {<<5, n>>, st} = take(st, 2)
    {_methods, st} = take(st, n)
    :gen_tcp.send(c, <<5, 0>>)
    {<<_v, cmd, _rsv, atyp>>, st} = take(st, 4)

    {host, st} =
      case atyp do
        1 -> with {<<a, b, x, y>>, st} <- take(st, 4), do: {to_string(:inet.ntoa({a, b, x, y})), st}
        3 -> with {<<l>>, st} <- take(st, 1), {h, st} <- take(st, l), do: {Redact.text(h), st}
        4 -> with {<<a::16, b::16, x::16, y::16, e::16, f::16, g::16, h::16>>, st} <- take(st, 16), do: {to_string(:inet.ntoa({a, b, x, y, e, f, g, h})), st}
        _ -> throw({:broken, "SOCKS5 address type #{atyp}"})
      end

    {<<port::16>>, st} = take(st, 2)

    if cmd != 1 do
      :gen_tcp.send(c, <<5, 7, 0, 1, 0::48>>)
      throw({:broken, "SOCKS5 command #{cmd} (only CONNECT)"})
    end

    put(%{"proto" => "socks5", "host" => host, "port" => port})
    decide(st, :socks5, host, port, st.buf)
  end

  defp http(st) do
    {head, rest} = read_head(st)
    [line | headers] = String.split(head, "\r\n")
    [method, target, version] = Enum.take(String.split(line, " ") ++ ["", "", ""], 3)

    if method == "CONNECT" do
      {host, port} = split_host_port(target, 443)
      put(%{"method" => "CONNECT", "proto" => "connect", "host" => Redact.text(host), "port" => port})
      decide(%{st | buf: rest}, :connect, host, port, rest)
    else
      u = URI.parse(target)

      if u.scheme != "http" or u.host in [nil, ""] do
        put(%{"proto" => "http"})
        refuse(st.sock, :http, "not a proxy request: #{Redact.text(Redact.latin1(binary_part(line, 0, min(200, byte_size(line)))))}", 400)
      else
        port = u.port || 80
        path = (u.path || "/") <> if(u.query, do: "?" <> u.query, else: "")
        put(%{"method" => Redact.text(Redact.latin1(method)), "path" => Redact.path(Redact.text(Redact.latin1(path))), "proto" => "http", "host" => u.host, "port" => port})

        kept =
          Enum.reject(headers, fn h ->
            h == "" or String.starts_with?(String.downcase(h), ["proxy-", "connection:", "keep-alive:"])
          end)

        first = "#{method} #{path} #{version}\r\n" <> Enum.map_join(kept, &(&1 <> "\r\n")) <> "Connection: close\r\n\r\n" <> rest
        decide(%{st | buf: ""}, :http, u.host, port, first)
      end
    end
  end

  defp read_head(%{buf: buf} = st) do
    case :binary.split(buf, "\r\n\r\n") do
      [head, rest] ->
        {head, rest}

      [_] ->
        if byte_size(buf) > @head_max, do: throw({:broken, "a request head over #{@head_max} bytes"})
        read_head(fill(st, byte_size(buf) + 1))
    end
  end

  defp split_host_port(target, default) do
    case Regex.run(~r/^\[([^\]]*)\](?::(\d+))?$/, target) || Regex.run(~r/^([^:]*)(?::(\d+))?$/, target) do
      [_, h] -> {h, default}
      [_, h, ""] -> {h, default}
      [_, h, p] -> {h, String.to_integer(p)}
      nil -> throw({:broken, "CONNECT to #{inspect(target)}"})
    end
  end

  # -- the decision -------------------------------------------------------------------------
  defp decide(st, kind, host, port, first) do
    c = st.sock

    # an address citld gave out for a name is that name
    host =
      with {:ok, ip} <- Net.parse_ip(host), name when is_binary(name) <- Fake.name(ip) do
        put(%{"host" => name, "address" => host})
        name
      else
        _ -> host
      end

    {name, _path, access} = Access.for_run(get("run"))
    put(%{"access" => name})
    entry = access && Access.lookup(access, host, port)

    cond do
      access == nil and name == nil ->
        refuse(c, kind, "no access.json applies (citl read, then citl run <name> or citl use <name>)")

      access == nil ->
        refuse(c, kind, "the access.json #{inspect(name)} cannot be read: citl read it again")

      entry == nil ->
        # refused before the name is resolved: a name can carry data out by itself
        refuse(c, kind, "#{host}:#{port} is not in access.json #{inspect(name)}")

      true ->
        put(%{"rule" => Access.rule(entry)})

        case entry["do"] do
          "refuse" -> refuse(c, kind, "refused by access.json #{inspect(name)}" <> if(entry["why"], do: ": #{entry["why"]}", else: ""))
          "pass" -> pass(c, kind, host, port, entry, first)
        end
    end
  end

  defp pass(c, kind, host, port, entry, first) do
    never = Net.never_ports()

    case entry["to"] do
      nil ->
        case Net.resolve(host) do
          {:error, why} ->
            refuse(c, kind, "#{host} #{why}")

          {:ok, ips} ->
            local = Enum.any?(ips, &Net.local?/1)

            cond do
              local and port in never ->
                refuse(c, kind, "#{host}:#{port} is a local program that can act outside the wall (tezcatl, Emacs, Xipe Totec ...): never")

              local ->
                refuse(c, kind, "#{host} resolves to a local address: a local server is reached only with to")

              true ->
                connect(c, kind, ips, port, @pass_timeout, "#{host}:#{port} does not answer", first)
            end
        end

      to ->
        with {:ok, {th, tp}} <- Access.parse_to(to),
             {:ok, ips} <- Net.resolve(th),
             [_ | _] = loop <- Enum.filter(ips, &Net.loopback?/1) do
          if tp in never,
            do: refuse(c, kind, "to #{to} is a local program that can act outside the wall (tezcatl, Emacs, Xipe Totec ...): never"),
            else: connect(c, kind, loop, tp, @to_timeout, "to #{to} does not answer (is its zoozve gate running?)", first, :gate)
        else
          _ -> refuse(c, kind, "to #{to} is not a local address")
        end
    end
  end

  defp connect(c, kind, ips, port, timeout, fail, first, gate \\ nil) do
    with {:ok, up, ip} <- Net.connect_any(ips, port, timeout),
         {:ok, early} <- if(gate, do: zoozve(up, port), else: {:ok, ""}) do
      relay(c, kind, up, ip, port, first, early)
    else
      {:error, why} -> refuse(c, kind, "#{fail} (#{why})")
      {:gate, why} -> refuse(c, kind, "the server at to port #{port} is not a zoozve gate of this machine (#{why})")
    end
  end

  # zoozve/1: a challenge at the head of the connection, answered with the machine's key (never sent);
  # -> {:ok, bytes that came after the answer} | {:gate, why}
  defp zoozve(up, port) do
    with {:ok, key} <- zoozve_key() do
      nonce = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
      want = :crypto.mac(:hmac, :sha256, key, "zoozve/1 #{nonce} #{port}") |> Base.encode16(case: :lower)
      :gen_tcp.send(up, "ZOOZVE/1 #{nonce}\r\n")

      case gate_line(up, "", System.monotonic_time(:millisecond) + @gate_timeout) do
        {:ok, "ZOOZVE/1 OK " <> got, rest} ->
          if byte_size(got) == 64 and :crypto.hash_equals(got, want) do
            put(%{"to_auth" => "zoozve"})
            {:ok, rest}
          else
            :gen_tcp.close(up)
            {:gate, "a wrong answer to the challenge: another key"}
          end

        {:ok, _, _} ->
          :gen_tcp.close(up)
          {:gate, "it does not speak zoozve/1"}

        {:error, why} ->
          :gen_tcp.close(up)
          {:gate, why}
      end
    else
      {:error, why} -> {:gate, why}
    end
  end

  defp gate_line(up, buf, deadline) do
    case :binary.split(buf, "\n") do
      [line, rest] ->
        {:ok, String.trim_trailing(line, "\r"), rest}

      [_] ->
        left = deadline - System.monotonic_time(:millisecond)

        cond do
          byte_size(buf) > 128 -> {:ok, "", ""}
          left <= 0 -> {:error, "no answer to the challenge within #{div(@gate_timeout, 1000)} s"}
          true ->
            case :gen_tcp.recv(up, 0, left) do
              {:ok, d} -> gate_line(up, buf <> d, deadline)
              {:error, :timeout} -> {:error, "no answer to the challenge within #{div(@gate_timeout, 1000)} s"}
              {:error, _} -> {:error, "it closed without answering the challenge"}
            end
        end
    end
  end

  defp zoozve_key do
    case File.read(Paths.zoozve_key()) do
      {:ok, s} ->
        case Base.decode16(String.trim(s), case: :lower) do
          {:ok, <<_::binary-32>> = k} -> {:ok, k}
          _ -> {:error, "#{Paths.zoozve_key()} is not a key"}
        end

      _ ->
        {:error, "no key at #{Paths.zoozve_key()} (citl setup makes it)"}
    end
  end

  defp relay(c, kind, up, ip, port, first, early) do
    put(%{"decision" => "pass", "sent_to" => Net.addr(ip, port)})

    case kind do
      :socks5 -> :gen_tcp.send(c, <<5, 0, 0, 1, 0::48>>)
      :connect -> :gen_tcp.send(c, "HTTP/1.1 200 Connection established\r\n\r\n")
      _ -> :ok
    end

    # what the server behind a gate sent right after the gate's answer (a database's greeting)
    if early != "", do: :gen_tcp.send(c, early)
    {u, d} = splice(c, up, first)
    :gen_tcp.close(up)
    put(%{"bytes_up" => u, "bytes_down" => d + byte_size(early)})
  end

  defp refuse(c, kind, why, status \\ 403) do
    put(%{"decision" => "refuse", "why" => why})
    Records.write(Map.put(Process.get(:rec), "ms", ms()))
    Process.put(:written, true)

    case kind do
      :socks5 ->
        :gen_tcp.send(c, <<5, 2, 0, 1, 0::48>>)

      :raw ->
        # a program that did not use the proxy has no way to be told why: the connection is reset
        :inet.setopts(c, linger: {true, 0})

      _ ->
        body = why <> "\n"
        reason = if status == 400, do: "Bad Request", else: "Forbidden"

        :gen_tcp.send(
          c,
          "HTTP/1.1 #{status} #{reason}\r\nContent-Type: text/plain; charset=utf-8\r\nX-Citlalpol: refused\r\n" <>
            "Connection: close\r\nContent-Length: #{byte_size(body)}\r\n\r\n" <> body
        )
    end
  end

  # -- relaying -----------------------------------------------------------------------------
  defp splice(c, up, first) do
    if first != "", do: :gen_tcp.send(up, first)
    down = Task.async(fn -> pump(up, c, 0) end)
    u = pump(c, up, byte_size(first))
    {u, Task.await(down, :infinity)}
  end

  defp pump(src, dst, n) do
    with {:ok, d} <- :gen_tcp.recv(src, 0),
         :ok <- :gen_tcp.send(dst, d) do
      pump(src, dst, n + byte_size(d))
    else
      _ ->
        :gen_tcp.shutdown(dst, :write)
        n
    end
  end
end
