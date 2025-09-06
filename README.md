# CacheDecorator

[![Elixir CI](https://github.com/amatalai/cache_decorator/workflows/Elixir%20CI/badge.svg)](https://github.com/amatalai/cache_decorator/actions?query=workflow%3A%22Elixir+CI%22) [![Hex.pm](https://img.shields.io/hexpm/v/cache_decorator.svg)](https://hex.pm/packages/cache_decorator)

`CacheDecorator` is an Elixir library that provides an easy way to add caching behavior to your module functions through compile-time decorators. By using `@cache` and `@invalidate` attributes, you can automatically cache function results and invalidate cache entries with minimal boilerplate.

## Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:cache_decorator, "~> 0.1.0"}
  ]
end
```

Then run:

```bash
mix deps.get
```

## Usage

Define a cache backend module implementing the `CacheDecorator` behaviour:

```elixir
defmodule MyCache do
  @behaviour CacheDecorator

  def get(_opts, key), do: # your cache get implementation
  def put(_opts, key, value, _opts), do: # your cache put implementation
  def del(_opts, key), do: # your cache delete implementation
end
```

Use `CacheDecorator` in your module, specifying your cache module:

```elixir
defmodule MyModule do
  use CacheDecorator, cache_module: MyCache

  @cache key: "cache_key_{arg}"
  def fetch_data(arg) do
    # expensive computation
  end

  @invalidate key: "cache_key_{arg}", on: :ok
  def update_data(arg) do
    # update that invalidates cache on successful result :ok
  end
end
```

## License

This project is licensed under the [MIT License](LICENSE).
