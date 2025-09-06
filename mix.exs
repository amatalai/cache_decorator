defmodule CacheDecorator.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/amatalai/cache_decorator"

  def project do
    [
      app: :cache_decorator,
      description: "Caching decorator macros for Elixir functions",
      deps: deps(),
      docs: docs(),
      elixir: "~> 1.15",
      package: package(),
      start_permanent: Mix.env() == :prod,
      version: @version
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp docs do
    [
      extras: [
        "CHANGELOG.md",
        "LICENSE",
        "README.md"
      ],
      main: "readme",
      source_url: @source_url,
      source_ref: @version,
      formatters: ["html"]
    ]
  end

  defp package do
    [
      maintainers: ["Tobiasz Małecki <amatalai@icloud.com>"],
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib mix.exs README.md LICENSE CHANGELOG.md)
    ]
  end

  defp deps do
    [
      {:cachex, "~> 4.1", only: :test},
      {:ex_doc, "~> 0.38", only: :dev, runtime: false},
      {:mockery, "~> 2.3", only: :test}
    ]
  end
end
