defmodule Citlalpol.Fake do
  @moduledoc """
  The wall's names and their fake addresses. citld answers the wall's DNS for a declared name with an
  address of 198.18.0.0/15 (reserved for benchmarks: no real host has one) and keeps which name it gave
  it, so a connection that comes to that address -- through the catch-all, or a proxy request naming the
  address -- is judged by the name. The table lives in citld only: after a restart an old address is
  just an address (refused unless declared).
  """
  use Agent

  @size 131_072

  def start_link(_), do: Agent.start_link(fn -> %{names: %{}, ips: %{}, next: 2} end, name: __MODULE__)

  def ip(name) do
    name = norm(name)

    Agent.get_and_update(__MODULE__, fn s ->
      case s.names[name] do
        nil ->
          ip = addr(s.next)
          old = s.ips[ip]
          names = if old, do: Map.delete(s.names, old), else: s.names
          next = if s.next + 1 >= @size, do: 2, else: s.next + 1
          {ip, %{s | names: Map.put(names, name, ip), ips: Map.put(s.ips, ip, name), next: next}}

        ip ->
          {ip, s}
      end
    end)
  end

  @doc "the name an address of ours was given to, or nil"
  def name({198, b, _, _} = ip) when b in 18..19 do
    if Process.whereis(__MODULE__), do: Agent.get(__MODULE__, & &1.ips[ip])
  end

  def name(_), do: nil

  defp addr(n), do: {198, 18 + div(n, 65_536), div(rem(n, 65_536), 256), rem(n, 256)}
  defp norm(name), do: name |> String.downcase() |> String.trim_trailing(".")
end
