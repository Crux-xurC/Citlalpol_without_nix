defmodule Citlalpol.Citld do
  @moduledoc """
  citld: listens on the door's unix socket (forbidden's relay connects to it from inside the wall) and
  gives each connection its own process under a Task.Supervisor; the records are written by one
  process. SIGTERM (citl stop) removes the socket and the pid file.
  """
  alias Citlalpol.{Door, Paths, Records}

  def serve do
    rt = Paths.runtime()
    File.mkdir_p!(Paths.runs())
    File.chmod!(rt, 0o700)
    File.chmod!(Paths.runs(), 0o700)
    door = Paths.door()

    if File.exists?(door) do
      case :gen_tcp.connect({:local, door}, 0, [], 1000) do
        {:ok, s} ->
          :gen_tcp.close(s)
          IO.puts(:stderr, "citl: citld is running already (#{door})")
          System.halt(1)

        _ ->
          File.rm(door)
      end
    end

    {:ok, l} = :gen_tcp.listen(0, [:binary, ifaddr: {:local, door}, active: false, backlog: 64])
    File.chmod!(door, 0o600)
    File.write!(Paths.pidfile(), System.pid())

    {:ok, _} =
      Supervisor.start_link([Records, Citlalpol.Fake, {Task.Supervisor, name: Citlalpol.Conns}], strategy: :one_for_one)

    System.trap_signal(:sigterm, fn ->
      File.rm(door)
      File.rm(Paths.pidfile())
      System.halt(0)
    end)

    IO.puts(:stderr, "citld: the door is #{door} (records: #{Paths.records()})")
    accept(l)
  end

  defp accept(l) do
    {:ok, c} = :gen_tcp.accept(l)

    {:ok, pid} =
      Task.Supervisor.start_child(Citlalpol.Conns, fn ->
        receive do
          :go -> Door.handle(c)
        end
      end)

    :ok = :gen_tcp.controlling_process(c, pid)
    send(pid, :go)
    accept(l)
  end
end
