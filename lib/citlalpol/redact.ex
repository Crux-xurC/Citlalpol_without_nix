defmodule Citlalpol.Redact do
  @moduledoc """
  What the records never keep: a query's values, and the usual places of secrets in a command line
  (best effort: a secret written some other way stays -- the records are this machine's own, outside git).
  """

  @doc "a path for the records: the query's names kept, their values never (a token can ride in a URL)"
  def path(target) do
    case String.split(target, "?", parts: 2) do
      [p] ->
        nonempty(p)

      [p, ""] ->
        nonempty(p)

      [p, q] ->
        names = q |> String.split("&", trim: true) |> Enum.map(&(&1 |> String.split("=", parts: 2) |> hd()))
        nonempty(p) <> "?" <> Enum.map_join(names, "&", &(&1 <> "=…"))
    end
  end

  defp nonempty(""), do: "/"
  defp nonempty(p), do: p

  @secrets [
    # a URL's query values
    {~r/([?&][^=&\s'"]+)=[^&\s'"]*/, "\\1=…"},
    # user:password@ in a URL
    {~r/(:\/\/[^\/@\s:'"]+):[^@\s\/'"]+@/, "\\1:…@"},
    {~r/((?:proxy-)?authorization|cookie|x-api-key|api-key)(\s*:\s*)[^'"]*?(?=\s+-|['"]|$)/i, "\\1\\2…"},
    {~r/(--?(?:password|passwd|pass|token|secret|api-key|apikey|access-key)(?:=|\s+))\S+/i, "\\1…"},
    # curl -u user:password
    {~r/((?:^|\s)-u\s*[^:\s]+):\S+/, "\\1:…"}
  ]

  def cmd(cmd), do: Enum.reduce(@secrets, cmd, fn {re, rep}, acc -> Regex.replace(re, acc, rep) end)

  @doc "bytes from the wire as text for the records (never invalid UTF-8)"
  def text(bin), do: String.replace_invalid(bin, "�")

  def latin1(bin), do: :unicode.characters_to_binary(bin, :latin1)
end
