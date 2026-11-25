defmodule Citlalpol.Dns do
  @moduledoc """
  citld's answer to the wall's DNS (questions come through forbidden's catch-all door). A name the
  access.json that applies does not declare -- or declares as refuse -- gets NXDOMAIN, and its own
  record: refused at the question, before any resolver outside hears the name. A declared name gets a
  fake address (Citlalpol.Fake) for A; other types get no data, so the program uses IPv4 and its
  connection comes back to citld. Nothing is ever asked of a real resolver here.
  """
  import Bitwise
  alias Citlalpol.{Access, Fake}

  @types %{1 => "A", 2 => "NS", 5 => "CNAME", 6 => "SOA", 12 => "PTR", 15 => "MX", 16 => "TXT", 28 => "AAAA", 33 => "SRV", 65 => "HTTPS"}
  @ttl 60

  @doc "-> {answer bytes, fields for the record}"
  def answer(query, run) do
    case parse(query) do
      {:ok, q} ->
        {name, _path, access} = Access.for_run(run)
        type = @types[q.qtype] || "TYPE#{q.qtype}"
        base = %{"proto" => "dns", "host" => q.name, "port" => 53, "method" => type, "access" => name}
        entry = access && Enum.find(access["destinations"], &Access.matches?(&1["host"], q.name))

        cond do
          access == nil ->
            {reply(q, 3, []), Map.merge(base, %{"decision" => "refuse", "why" => "no access.json applies"})}

          entry == nil ->
            {reply(q, 3, []), Map.merge(base, %{"decision" => "refuse", "why" => "#{q.name} is not in access.json #{inspect(name)}"})}

          entry["do"] != "pass" ->
            {reply(q, 3, []), Map.merge(base, %{"decision" => "refuse", "rule" => Access.rule(entry), "why" => "refused by access.json #{inspect(name)}"})}

          q.qtype == 1 ->
            ip = Fake.ip(q.name)
            {reply(q, 0, [ip]), Map.merge(base, %{"decision" => "pass", "rule" => Access.rule(entry), "answer" => to_string(:inet.ntoa(ip))})}

          true ->
            {reply(q, 0, []), Map.merge(base, %{"decision" => "pass", "rule" => Access.rule(entry), "answer" => "(none: only A)"})}
        end

      :error ->
        {<<>>, %{"proto" => "dns", "decision" => "refuse", "why" => "not a DNS question"}}
    end
  end

  def parse(<<id::16, flags::16, qd::16, _an::16, _ns::16, _ar::16, rest::binary>>) when qd >= 1 do
    with {:ok, labels, <<qtype::16, qclass::16, _::binary>> = after_name} <- labels(rest, []) do
      qlen = byte_size(rest) - byte_size(after_name) + 4
      {:ok, %{id: id, flags: flags, name: Enum.join(labels, "."), qtype: qtype, qclass: qclass, question: binary_part(rest, 0, qlen)}}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  defp labels(<<0, rest::binary>>, acc), do: {:ok, Enum.reverse(acc), rest}

  defp labels(<<l, label::binary-size(l), rest::binary>>, acc) when l in 1..63,
    do: labels(rest, [String.replace_invalid(label, "?") | acc])

  defp labels(_, _), do: :error

  defp reply(q, rcode, ips) do
    # QR, the question's opcode and RD, RA, the rcode
    flags = 0x8000 ||| (q.flags &&& 0x7900) ||| 0x0080 ||| rcode
    answers = for {a, b, c, d} <- ips, into: <<>>, do: <<0xC00C::16, 1::16, 1::16, @ttl::32, 4::16, a, b, c, d>>
    <<q.id::16, flags::16, 1::16, length(ips)::16, 0::16, 0::16, q.question::binary, answers::binary>>
  end
end
