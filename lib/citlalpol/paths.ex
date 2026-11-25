defmodule Citlalpol.Paths do
  @moduledoc "Where citld and citl keep things: the runtime (door, pid, runs), the config, the records."

  def dir, do: :persistent_term.get(:citlalpol_dir)

  def runtime, do: env("CITLALPOL_RUNTIME") || Path.join(xdg_runtime(), "citlalpol")
  def state, do: env("CITLALPOL_STATE") || Path.join(env("XDG_DATA_HOME") || Path.expand("~/.local/share"), "citlalpol")
  def config, do: env("CITLALPOL_CONFIG") || Path.join(env("XDG_CONFIG_HOME") || Path.expand("~/.config"), "citlalpol")

  def door, do: Path.join(runtime(), "door.sock")
  def pidfile, do: Path.join(runtime(), "citld.pid")
  def runs, do: Path.join(runtime(), "runs")
  # labels set from outside the wall (citl label): the runtime directory is hidden inside the wall
  def labels, do: Path.join(runtime(), "labels")
  def registered, do: Path.join(config(), "registered.json")
  # what citl read took: the access.json in force is this copy, not the project's file
  def copies, do: Path.join(config(), "access")
  # the key zoozve's gates answer the challenge with (citl setup makes it; hidden inside the wall)
  def zoozve_key, do: Path.join(config(), "zoozve.key")
  def use_file, do: Path.join(config(), "use")
  def never, do: Path.join(config(), "never.json")
  def records, do: Path.join(state(), "records")

  # the port inside forbidden's wall that leads to citld
  def port, do: 4600

  defp xdg_runtime, do: env("XDG_RUNTIME_DIR") || "/run/user/#{File.stat!("/proc/self").uid}"

  defp env(k) do
    case System.get_env(k) do
      nil -> nil
      "" -> nil
      v -> v
    end
  end
end
