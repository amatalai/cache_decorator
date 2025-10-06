# CacheDecorator

[![Elixir CI](https://github.com/amatalai/cache_decorator/workflows/Elixir%20CI/badge.svg)](https://github.com/amatalai/cache_decorator/actions?query=workflow%3A%22Elixir+CI%22) [![Hex.pm](https://img.shields.io/hexpm/v/cache_decorator.svg)](https://hex.pm/packages/cache_decorator)

`CacheDecorator` is an Elixir library that provides an easy way to add caching behavior to your module functions through compile-time decorators. By using `@cache` and `@invalidate` attributes, you can automatically cache function results and invalidate cache entries with minimal boilerplate.

## Installation

Add the dependency to your `mix.exs`:

```elixir
def deps do
  [
    {:cache_decorator, "~> 0.2.0"}
  ]
end
```

## Usage

See [documentation](https://hexdocs.pm/cache_decorator/index.html) for usage examples

## License

This project is licensed under the [MIT License](LICENSE).
