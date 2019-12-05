defmodule Siegfried.Umbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      releases: [
        siegfried: [
          version: auto_version(),
          applications: [
            siegfried: :permanent,
            siegfried_web: :permanent,
            trend_tracker: :permanent,
          ]
        ]
      ]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options.
  #
  # Dependencies listed here are available only for this project
  # and cannot be accessed from applications inside the apps folder
  defp deps do
    []
  end

  defp auto_version do
    time = Regex.named_captures(~r/^(?<year>[\d]+)-(?<day>[\d|-]+)\s(?<sec>[\d|:]+)\./, to_string(DateTime.utc_now()))
    major = time["year"] |> String.slice(2..3)
    minor = time["day"] |> String.replace("-", "")
    patch = time["sec"] |> String.replace(":", "")
    "1" <> major <> ".2" <> minor <> ".3" <> patch
  end
end
