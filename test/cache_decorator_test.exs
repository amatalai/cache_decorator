defmodule CacheDecoratorTest do
  use ExUnit.Case, async: false
  import Mockery.Assertions

  cache_name = :cache_decorator_test
  @cache_name cache_name

  setup_all do
    Mockery.History.enable_history()

    start_supervised!({Cachex, name: @cache_name})

    :ok
  end

  defmodule TestCache do
    use Mockery.Macro

    defmacrop cachex do
      quote do: mockable(Cachex)
    end

    @behaviour CacheDecorator
    @cache_name cache_name

    def get(_decorator_opts, key) do
      case cachex().get(@cache_name, key) do
        {:ok, nil} -> {:ok, nil}
        {:ok, value} -> {:ok, value}
        {:error, _reason} -> :error
      end
    end

    def put(_decorator_opts, key, value, opts) do
      opts = Keyword.take(opts, [:ttl])
      _ = cachex().put(@cache_name, key, value, opts)

      :ok
    end

    def del(_decorator_opts, key) do
      _ = cachex().del(@cache_name, key)

      :ok
    end
  end

  defmodule Example do
    use CacheDecorator, cache_module: TestCache

    @cache key: "test_{value}"
    def cache_without_ttl(value), do: value

    @cache key: "test_{value}", ttl: :timer.minutes(5)
    def cache_with_ttl(value), do: value

    @cache key: "test_{value1}_{value2}"
    def cache_with_multiple_args(value1, value2), do: {value1, value2}

    @cache key: "test_{value}", on: quote(do: {:ok, _result})
    def cache_with_single_on_pattern(value, return) do
      _ = value

      return
    end

    @cache key: "test_{value}", on: [{:ok, 1}, {:ok, 2}]
    def cache_with_multiple_on_patterns(value, return) do
      _ = value

      return
    end

    @invalidate key: "test_{value}"
    def invalidate_without_on_pattern(value), do: value

    @invalidate key: "test_{value}", on: :ok
    def invalidate_with_single_on_pattern(value), do: value

    @invalidate key: "test_{value}", on: [:ok, quote(do: {:ok, _result})]
    def invalidate_with_multiple_on_patterns(value, result_fun), do: result_fun.(value)

    @invalidate key: "test_{value1}_{value2}"
    def invalidate_with_multiple_args(value1, value2), do: {value1, value2}
  end

  describe "cache_without_ttl/1" do
    test "caches value" do
      value = random()
      cache_key = "test_#{value}"

      assert ^value = Example.cache_without_ttl(value)
      assert ^value = Example.cache_without_ttl(value)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^value, []], times: 1
    end
  end

  describe "cache_with_ttl/1" do
    test "caches value" do
      value = random()
      cache_key = "test_#{value}"
      ttl = :timer.minutes(5)

      assert ^value = Example.cache_with_ttl(value)
      assert ^value = Example.cache_with_ttl(value)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^value, [ttl: ^ttl]], times: 1
    end
  end

  describe "cache_with_multiple_args/1" do
    test "caches value" do
      value1 = random()
      value2 = random()
      cache_key = "test_#{value1}_#{value2}"

      result = {value1, value2}

      assert ^result = Example.cache_with_multiple_args(value1, value2)
      assert ^result = Example.cache_with_multiple_args(value1, value2)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^result, []], times: 1
    end
  end

  describe "cache_with_single_on_pattern/1" do
    test "caches value when on: pattern matches" do
      value = random()
      return = {:ok, value}
      cache_key = "test_#{value}"

      assert ^return = Example.cache_with_single_on_pattern(value, return)
      assert ^return = Example.cache_with_single_on_pattern(value, return)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^return, []], times: 1
    end

    test "doesn't cache when on: pattern doesn't match" do
      value = random()
      return = {:error, "reason"}
      cache_key = "test_#{value}"

      assert ^return = Example.cache_with_single_on_pattern(value, return)
      assert ^return = Example.cache_with_single_on_pattern(value, return)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      refute_called! Cachex, :put, args: [@cache_name, ^cache_key, ^return, []]
    end
  end

  describe "cache_with_multiple_on_pattern/1" do
    test "caches value when first on: pattern matches" do
      value = random()
      return = {:ok, 1}
      cache_key = "test_#{value}"

      assert ^return = Example.cache_with_multiple_on_patterns(value, return)
      assert ^return = Example.cache_with_multiple_on_patterns(value, return)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^return, []], times: 1
    end

    test "caches value when second on: pattern matches" do
      value = random()
      return = {:ok, 2}
      cache_key = "test_#{value}"

      assert ^return = Example.cache_with_multiple_on_patterns(value, return)
      assert ^return = Example.cache_with_multiple_on_patterns(value, return)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      assert_called! Cachex, :put, args: [@cache_name, ^cache_key, ^return, []], times: 1
    end

    test "doesn't cache when on: pattern doesn't match" do
      value = random()
      return = {:ok, 3}
      cache_key = "test_#{value}"

      assert ^return = Example.cache_with_multiple_on_patterns(value, return)
      assert ^return = Example.cache_with_multiple_on_patterns(value, return)

      assert_called! Cachex, :get, args: [@cache_name, ^cache_key], times: 2
      refute_called! Cachex, :put, args: [@cache_name, ^cache_key, ^return, []]
    end
  end

  describe "invalidate_without_on_pattern/1" do
    test "invalidates cache" do
      value = random()
      cache_key = "test_#{value}"

      assert ^value = Example.invalidate_without_on_pattern(value)

      assert_called! Cachex, :del, args: [@cache_name, ^cache_key], times: 1
    end
  end

  describe "invalidate_with_single_on_pattern/1" do
    test "invalidates cache when :on pattern matches" do
      value = :ok
      cache_key = "test_#{value}"

      assert ^value = Example.invalidate_with_single_on_pattern(value)

      assert_called! Cachex, :del, args: [@cache_name, ^cache_key], times: 1
    end

    test "doesn't invalidate cache when :on pattern don't match" do
      value = random()

      assert ^value = Example.invalidate_with_single_on_pattern(value)

      refute_called! Cachex, :del
    end
  end

  describe "invalidate_with_multiple_on_patterns/1" do
    test "invalidates cache when first pattern matches" do
      value = random()
      cache_key = "test_#{value}"

      assert :ok = Example.invalidate_with_multiple_on_patterns(value, fn _ -> :ok end)

      assert_called! Cachex, :del, args: [@cache_name, ^cache_key], times: 1
    end

    test "invalidates cache when second :on pattern matches" do
      value = random()
      cache_key = "test_#{value}"

      assert {:ok, ^value} =
               Example.invalidate_with_multiple_on_patterns(value, fn v -> {:ok, v} end)

      assert_called! Cachex, :del, args: [@cache_name, ^cache_key], times: 1
    end

    test "doesn't invalidate cache when :on pattern don't matches" do
      value = random()

      assert {:error, :reason} =
               Example.invalidate_with_multiple_on_patterns(value, fn _ -> {:error, :reason} end)

      refute_called! Cachex, :del
    end
  end

  describe "invalidate_with_multiple_args/2" do
    test "invalidates cache" do
      value1 = random()
      value2 = random()
      cache_key = "test_#{value1}_#{value2}"

      result = {value1, value2}

      assert ^result = Example.invalidate_with_multiple_args(value1, value2)

      assert_called! Cachex, :del, args: [@cache_name, ^cache_key], times: 1
    end
  end

  describe "@cache compilation errors" do
    test "raises when key contains unknown variable" do
      error_msg =
        "CacheDecorator: unknown variable {asdf} in :key " <>
          "for @cache CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @cache key: "{asdf}"
          def foo(bar), do: bar
        end
      end)
    end

    test "raises when key is empty" do
      error_msg =
        "CacheDecorator: invalid value \"\" in :key " <>
          "for @cache CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @cache key: ""
          def foo(bar), do: bar
        end
      end)
    end

    test "raises when key isn't string" do
      error_msg =
        "CacheDecorator: invalid value :invalid in :key " <>
          "for @cache CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @cache key: :invalid
          def foo(bar), do: bar
        end
      end)
    end
  end

  describe "@invalidate compilation errors" do
    test "raises when key contains unknown variable" do
      error_msg =
        "CacheDecorator: unknown variable {asdf} in :key " <>
          "for @invalidate CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @invalidate key: "{asdf}"
          def foo(bar), do: bar
        end
      end)
    end

    test "raises when key is empty" do
      error_msg =
        "CacheDecorator: invalid value \"\" in :key " <>
          "for @invalidate CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @invalidate key: ""
          def foo(bar), do: bar
        end
      end)
    end

    test "raises when key isn't string" do
      error_msg =
        "CacheDecorator: invalid value :invalid in :key " <>
          "for @invalidate CacheDecoratorTest.Crash.foo/1"

      assert_raise(ArgumentError, error_msg, fn ->
        defmodule Crash do
          use CacheDecorator, cache_module: TestCache

          @invalidate key: :invalid
          def foo(bar), do: bar
        end
      end)
    end
  end

  defp random, do: "#{System.unique_integer([:positive])}"
end
