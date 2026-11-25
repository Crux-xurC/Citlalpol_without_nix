defmodule Citlalpol.Net do
  @moduledoc """
  Addresses: which are local, which are loopback, resolving a name, connecting to the first address
  that answers. Local ports a wall must never reach, not even with `to`: programs that can
  act outside (tezcatl's pages and relay -- the relay starts shells --, Emacs, Xipe Totec). More in never.json.
  """
  import Bitwise
  alias Citlalpol.{Json, Paths}

  @never [4000, 4001, 4100, 4200]

  def never_ports do
    extra =
      case Json.read(Paths.never(), %{}) do
        %{"ports" => l} when is_list(l) -> Enum.filter(l, &is_integer/1)
        _ -> []
      end

    Enum.uniq(@never ++ extra)
  end

  def parse_ip(s) when is_binary(s) do
    case :inet.parse_strict_address(String.to_charlist(s)) do
      {:ok, ip} -> {:ok, ip}
      _ -> :error
    end
  end

  def loopback?({127, _, _, _}), do: true
  def loopback?({0, 0, 0, 0, 0, 0, 0, 1}), do: true
  def loopback?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: loopback?(v4(hi, lo))
  def loopback?(_), do: false

  @doc "names that may stand in `to`: localhost and loopback addresses"
  def loopback_name?("localhost"), do: true

  def loopback_name?(h) do
    case parse_ip(h) do
      {:ok, ip} -> loopback?(ip)
      :error -> false
    end
  end

  @doc "not a public address of the Internet: this machine, the LAN, link-local, reserved, multicast"
  def local?({a, b, c, _}) do
    a == 0 or a == 10 or a == 127 or a >= 224 or
      (a == 100 and b in 64..127) or
      (a == 169 and b == 254) or
      (a == 172 and b in 16..31) or
      (a == 192 and b == 0 and c in [0, 2]) or
      (a == 192 and b == 168) or
      (a == 198 and b in 18..19) or
      (a == 198 and b == 51 and c == 100) or
      (a == 203 and b == 0 and c == 113)
  end

  def local?({0, 0, 0, 0, 0, 0, 0, x}) when x in [0, 1], do: true
  def local?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}), do: local?(v4(hi, lo))
  def local?({a, _, _, _, _, _, _, _}) when a in 0xFC00..0xFDFF, do: true
  def local?({a, _, _, _, _, _, _, _}) when a in 0xFE80..0xFEBF, do: true
  def local?({a, _, _, _, _, _, _, _}) when a >= 0xFF00, do: true
  def local?({0x2001, 0xDB8, _, _, _, _, _, _}), do: true
  def local?(_), do: false

  defp v4(hi, lo), do: {hi >>> 8, hi &&& 255, lo >>> 8, lo &&& 255}

  @doc "every address of a name (IPv4 first), or the address itself"
  def resolve(host) do
    c = String.to_charlist(host)

    case :inet.parse_strict_address(c) do
      {:ok, ip} ->
        {:ok, [ip]}

      _ ->
        v4 = ok_list(:inet.getaddrs(c, :inet))
        v6 = ok_list(:inet.getaddrs(c, :inet6))

        case Enum.uniq(v4 ++ v6) do
          [] -> {:error, "does not resolve"}
          l -> {:ok, l}
        end
    end
  end

  defp ok_list({:ok, l}), do: l
  defp ok_list(_), do: []

  @doc "{:ok, socket, address} for the first address that answers, else {:error, why}"
  def connect_any(ips, port, timeout), do: connect_any(ips, port, timeout, "no address")

  defp connect_any([], _port, _timeout, why), do: {:error, why}

  defp connect_any([ip | rest], port, timeout, _why) do
    opts = [:binary, active: false] ++ if(tuple_size(ip) == 8, do: [:inet6], else: [])

    case :gen_tcp.connect(ip, port, opts, timeout) do
      {:ok, s} -> {:ok, s, ip}
      {:error, e} -> connect_any(rest, port, timeout, to_string(:inet.format_error(e)))
    end
  end

  def addr(ip, port) when tuple_size(ip) == 8, do: "[#{:inet.ntoa(ip)}]:#{port}"
  def addr(ip, port), do: "#{:inet.ntoa(ip)}:#{port}"
end
