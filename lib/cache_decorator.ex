defmodule CacheDecorator do
  @moduledoc """
  Provides a caching decorator mechanism for Elixir functions.

  This module allows you to easily add caching behavior to functions by using
  the `@cache` and `@invalidate` module attributes. It decorates functions to
  automatically cache their results and invalidate cache entries.

  ## Usage

  Use `CacheDecorator` in your module and specify a `:cache_module` that
  implements the caching backend behaviour.

      use CacheDecorator, cache_module: YourCacheModule

  Then decorate your functions with:

  - `@cache key: "cache_key_template", on: <pattern or list_of_patterns>`
    - Caches the result of the function under the given key.
    - The `:key` can contain placeholders like `{arg_name}` that will be replaced
      by the string representation of the corresponding function argument.
    - The `:on` option allows specifying one or multiple patterns to match
      against the result of the function call; result will be cached only
      if it matches one of these patterns.
    - If `:on` is omitted, cache happens for any function call result.
    - You can provide additional options like `ttl` which
      will be passed to `cache_module.put/4` as `opts`

  - `@invalidate key: "cache_key_template", on: <pattern or list_of_patterns>`
    - Invalidates the cache entry for the given key.
    - The `:key` can contain placeholders like `{arg_name}` that will be replaced
      by the string representation of the corresponding function argument.
    - The `:on` option allows specifying one or multiple patterns to match
      against the result of the function call; cache invalidation only occurs
      if the result matches one of these patterns.
    - If `:on` is omitted, cache invalidation happens after every call.

  ## Behaviour callbacks you need to implement in your cache module

  Your cache module (provided via `:cache_module` option) must implement the
    following callbacks:

        @callback get(decorator_opts :: Keyword.t(), key :: String.t()) ::
          {:ok, nil} | {:ok, term()} | :error

        @callback put(decorator_opts :: Keyword.t(), key :: String.t(), value :: term(), opts :: Keyword.t()) ::
          :ok

        @callback del(decorator_opts :: Keyword.t(), key :: String.t()) ::
          :ok

    Here:

    - `decorator_opts` are the options passed to `use CacheDecorator` in your
      module, such as the cache module and any other opts.

    - In the `put/4` callback, the `opts` argument is the keyword list of options
      provided in the `@cache` decorator, for example the `ttl` option.

    This allows plugging any caching backend you want, by implementing these
    functions.

  ## Example

      defmodule MyCache do
        @behaviour CacheDecorator

        def get(decorator_opts, key), do: ...
        def put(decorator_opts, key, value, opts), do: ...
        def del(decorator_opts, key), do: ...
      end

      defmodule MyModule do
        use CacheDecorator, cache_module: MyCache

        @cache key: "my_key_{arg1}"
        def my_function(arg1), do: ... # automatically cached

        @invalidate key: "my_key_{arg1}", on: :ok
        def invalidate_my_key(arg1), do: ... # invalidates cache on :ok
      end

  Cache keys can reference function argument names wrapped in `{}` that will
  be dynamically interpolated from the actual arguments on call.

  If the cache is unavailable (e.g., backend error), the original function
  will be called without caching as fallback.

  This decorator uses Elixir's `@on_definition` and `@before_compile`
  hooks, and generates override functions that implement caching and
  invalidation transparently.

  ## Examples of decorator translation

  Here are examples showing how functions decorated with caching decorators
  would look like without using the decorators.

  ### Using `@cache`

  Decorated function:

      use CacheDecorator, cache_module: MyCache

      @cache key: "prefix_{arg}"
      def get(arg), do: expensive_computation(arg)

  Equivalent function without decorator:

      def get(arg) do
        key = "prefix_\#{arg}"

        case MyCache.get([], key) do
          {:ok, nil} ->
            value = expensive_computation(arg)
            :ok = MyCache.put([], key, value, key: "prefix_{arg}")
            value

          {:ok, value} ->
            value

          :error ->
            expensive_computation(arg)
        end
      end

  ### Using `@invalidate`

  Decorated function:

      use CacheDecorator, cache_module: MyCache

      @invalidate key: "prefix_{arg}", on: :ok
      def update(arg), do: do_something(arg)

  Equivalent function without decorator:

      def update(arg) do
        result = do_something(arg)

        case result do
          :ok ->
            :ok = MyCache.del([], "prefix_\#{arg}")
            result

          _ ->
            result
        end
      end

  If the `:on` option is omitted, invalidation occurs unconditionally:

      @invalidate key: "prefix_{arg}"
      def update(arg), do: do_something(arg)

  Equivalent without decorator:

      def update(arg) do
        result = do_something(arg)
        :ok = MyCache.del([], "prefix_\#{arg}")
        result
      end
  """
  @type decorator_opts :: Keyword.t()
  @type key :: String.t()
  @type value :: term()
  @type opts :: Keyword.t()

  @callback get(decorator_opts, key) :: {:ok, nil} | {:ok, value} | :error
  @callback put(decorator_opts, key, value, opts) :: :ok
  @callback del(decorator_opts, key) :: :ok

  defmacro __using__(opts) do
    quote do
      use Mockery.Macro
      Module.register_attribute(__MODULE__, :cache_specs, accumulate: true)
      Module.register_attribute(__MODULE__, :invalidations, accumulate: true)

      @cache_module unquote(Keyword.fetch!(opts, :cache_module))
      @cache_opts unquote(opts)

      @before_compile unquote(__MODULE__)
      @on_definition unquote(__MODULE__)
    end
  end

  def __on_definition__(env, _kind, name, args, _guards, _body) do
    if opts = Module.get_attribute(env.module, :cache) do
      if is_binary(opts[:key]) do
        Module.put_attribute(env.module, :cache_specs, {name, args, opts})
        Module.delete_attribute(env.module, :cache)
      else
        invalid_key!(env.module, name, args, opts[:key], :cache)
      end
    end

    if opts = Module.get_attribute(env.module, :invalidate) do
      if is_binary(opts[:key]) do
        Module.put_attribute(env.module, :invalidations, {name, args, opts})
        Module.delete_attribute(env.module, :invalidate)
      else
        invalid_key!(env.module, name, args, opts[:key], :invalidate)
      end
    end
  end

  defmacro __before_compile__(env) do
    wrappers_ast = handle_cache_specs(env) ++ handle_invalidations(env)

    quote do
      (unquote_splicing(wrappers_ast))
    end
  end

  defp handle_cache_specs(env) do
    specs = Module.get_attribute(env.module, :cache_specs) || []

    for {name, args_ast, opts} <- specs do
      Module.make_overridable(env.module, [{name, length(args_ast)}])

      {internal_opts, opts} = Keyword.split(opts, [:key, :on])

      key_template = Keyword.fetch!(internal_opts, :key)
      key_ast = compile_key_ast!({key_template, args_ast, env.module, name, :cache})

      on_pattern = Keyword.get(internal_opts, :on, :no_on_pattern)

      quote do
        def unquote(name)(unquote_splicing(args_ast)) do
          key = unquote(key_ast)

          case @cache_module.get(@cache_opts, key) do
            {:ok, nil} ->
              value = super(unquote_splicing(args_ast))

              unquote(put_cache(opts, on_pattern))

            {:ok, value} ->
              value

            # If cache is unavailable, fall back to the original function.
            :error ->
              super(unquote_splicing(args_ast))
          end
        end
      end
    end
  end

  defp put_cache(opts, :no_on_pattern) do
    quote do
      :ok = @cache_module.put(@cache_opts, key, value, unquote(opts))

      value
    end
  end

  defp put_cache(opts, on_pattern) do
    cache_ast = put_cache(opts, :no_on_pattern)

    quote do
      case value do
        unquote(compile_on_patterns_ast(on_pattern, cache_ast))
      end
    end
  end

  defp handle_invalidations(env) do
    invalidations = Module.get_attribute(env.module, :invalidations) || []

    for {name, args_ast, opts} <- invalidations do
      Module.make_overridable(env.module, [{name, length(args_ast)}])

      {internal_opts, opts} = Keyword.split(opts, [:key, :on])

      raw_key = Keyword.fetch!(internal_opts, :key)
      key_ast = compile_key_ast!({raw_key, args_ast, env.module, name, :invalidate})

      on_pattern = Keyword.get(internal_opts, :on, :no_on_pattern)

      quote do
        def unquote(name)(unquote_splicing(args_ast)) do
          key = unquote(key_ast)

          value = super(unquote_splicing(args_ast))

          unquote(put_invalidation(opts, on_pattern))
        end
      end
    end
  end

  defp put_invalidation(_opts, :no_on_pattern) do
    quote do
      :ok = @cache_module.del(@cache_opts, key)

      value
    end
  end

  defp put_invalidation(opts, on_pattern) do
    invalidation_ast = put_invalidation(opts, :no_on_pattern)

    quote do
      case value do
        unquote(compile_on_patterns_ast(on_pattern, invalidation_ast))
      end
    end
  end

  defp compile_on_patterns_ast(on, action_ast) do
    on = List.wrap(on)

    unmatched_pattern_ast =
      quote do
        other -> other
      end

    patterns_ast =
      for pattern <- on do
        quote do
          unquote(pattern) -> unquote(action_ast)
        end
      end

    List.flatten(patterns_ast ++ [unmatched_pattern_ast])
  end

  defp compile_key_ast!({template, _, _, _, _} = args) when is_binary(template) do
    {template, args_ast, env_module, fun_name, decorator_type} = args

    # Collect *all* bound var names from the function head (deep walk)
    {^args_ast, arg_ast_by_name} =
      Macro.prewalk(args_ast, %{}, fn
        {name, _, _ctx} = ast, acc when is_atom(name) and name != :_ ->
          {ast, Map.put(acc, to_string(name), ast)}

        ast, acc ->
          {ast, acc}
      end)

    # We'll split but also keep captures so we can alternate literal/var safely
    re = ~r/\{([A-Za-z_][A-Za-z0-9_]*)\}/u

    segments =
      Regex.split(re, template, include_captures: true, trim: true)
      |> Enum.map(fn seg ->
        # If seg is exactly "{name}", treat it as a variable; otherwise literal.
        case Regex.run(~r/^\{([A-Za-z_][A-Za-z0-9_]*)\}$/u, seg) do
          [_, var] ->
            handle_var(var, arg_ast_by_name, args)

          nil ->
            quote(do: unquote(seg))
        end
      end)

    # Build concatenation AST: seg1 <> seg2 <> ...
    case segments do
      [] ->
        invalid_key!(env_module, fun_name, args_ast, template, decorator_type)

      [single] ->
        single

      [first | rest] ->
        Enum.reduce(rest, first, fn seg, acc ->
          quote(do: unquote(acc) <> unquote(seg))
        end)
    end
  end

  defp handle_var(var, arg_ast_by_name, args) do
    {_template, args_ast, env_module, fun_name, decorator_type} = args

    case Map.fetch(arg_ast_by_name, var) do
      {:ok, v_ast} ->
        quote(do: to_string(unquote(v_ast)))

      :error ->
        raise ArgumentError,
              "#{inspect(__MODULE__)}: unknown variable {#{var}} in :key for " <>
                "@#{decorator_type} #{inspect(env_module)}.#{fun_name}/#{length(args_ast)}"
    end
  end

  defp invalid_key!(env_module, name, args, key, decorator_type) do
    raise ArgumentError,
          "#{inspect(__MODULE__)}: invalid value #{inspect(key)} in :key " <>
            "for @#{decorator_type} #{inspect(env_module)}.#{name}/#{length(args)}"
  end
end
