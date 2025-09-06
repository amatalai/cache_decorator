defmodule CacheDecorator.MixProject do
  use Mix.Project

  def project do
    [
      app: :cache_decorator,
      deps: deps(),
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      version: "0.1.0"
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:cachex, "~> 4.1", only: :test},
      {:mockery, "~> 2.3", only: :test}
    ]
  end
end
