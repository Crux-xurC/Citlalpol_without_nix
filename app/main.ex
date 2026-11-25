defmodule Citlalpol.Main do
  @moduledoc """
  The release's entry (this repository's own): what upstream's main.exs does, for
  `bin/citlalpol eval "Citlalpol.Main.main()" <command> ...` -- the repository's
  directory comes from CITLALPOL_DIR (bin/citl sets it), the commands' arguments
  from the eval's own.
  """
  def main do
    :persistent_term.put(:citlalpol_dir, System.get_env("CITLALPOL_DIR") || File.cwd!())
    Citlalpol.CLI.main(System.argv())
  end
end
