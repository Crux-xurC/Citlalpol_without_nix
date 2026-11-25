defmodule Citlalpol.MixProject do
  use Mix.Project

  # Citlalpol as a Mix project, for running without Nix.
  #
  # lib/citlalpol/*.ex, main.exs, test/ and docs/ come from Citlalpol (the upstream,
  # run with Nix as `elixir main.exs`) through sync/sync.sh; mix.exs, app/, bin/citl,
  # bin/release, bin/test, README.md and sync/ are this repository's own. No Hex
  # package: Citlalpol needs Elixir and Erlang/OTP only.
  def project do
    [
      app: :citlalpol,
      version: "0.1.0",
      elixir: "~> 1.18",
      elixirc_paths: ["lib/citlalpol", "app"],
      # test/run.sh is Citlalpol's acceptance (bin/test), not ExUnit
      test_paths: [],
      deps: [],
      releases: [
        # cookie: fixed, so the same source gives the same tarball; unused -- citl is run with
        # `eval`, which starts no distribution
        citlalpol: [include_executables_for: [:unix], cookie: "citlalpol-no-distribution"]
      ]
    ]
  end

  # citl's commands start what they need themselves (citld: its records' writer and its
  # connections' supervisor), as under `elixir main.exs`
  def application, do: [extra_applications: [:logger, :crypto]]
end
