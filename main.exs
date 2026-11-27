# Citlalpol: `elixir main.exs <command>` (bin/citl). Not a Mix project, like tezcatl and Xipe Totec:
# the files under lib/ are required in order, and nothing but Elixir/OTP is needed.
:persistent_term.put(:citlalpol_dir, __DIR__)

for f <- ~w(paths json net redact records access fake dns door citld swallow cli) do
  Code.require_file("lib/citlalpol/#{f}.ex", __DIR__)
end

Citlalpol.CLI.main(System.argv())
