defmodule Citlalpol.Json do
  @moduledoc "Reading and writing this machine's small JSON files (Elixir's own JSON module)."

  @doc "the decoded file, `default` when it does not exist; {:error, why} when it cannot be read"
  def read(path, default) do
    case File.read(path) do
      {:ok, s} ->
        case JSON.decode(s) do
          {:ok, v} -> v
          {:error, e} -> {:error, "#{path}: not JSON (#{inspect(e)})"}
        end

      {:error, :enoent} ->
        default

      {:error, e} ->
        {:error, "cannot read #{path}: #{:file.format_error(e)}"}
    end
  end

  def write(path, value) do
    File.mkdir_p!(Path.dirname(path))
    tmp = path <> ".tmp"
    File.write!(tmp, JSON.encode!(value) <> "\n")
    File.rename!(tmp, path)
  end
end
