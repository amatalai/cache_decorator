defmodule CacheDecorator do
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

      key_template = Keyword.fetch!(opts, :key)
      key_ast = compile_key_ast!(key_template, args_ast, env.module, name, :cache)

      quote do
        def unquote(name)(unquote_splicing(args_ast)) do
          key = unquote(key_ast)

          case @cache_module.get(@cache_opts, key) do
            {:ok, nil} ->
              value = super(unquote_splicing(args_ast))

              :ok = @cache_module.put(@cache_opts, key, value, unquote(opts))

              value

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

  defp handle_invalidations(env) do
    invalidations = Module.get_attribute(env.module, :invalidations) || []

    for {name, args, opts} <- invalidations do
      Module.make_overridable(env.module, [{name, length(args)}])

      raw_key = Keyword.fetch!(opts, :key)
      key_ast = compile_key_ast!(raw_key, args, env.module, name, :invalidate)

      invalidate_ast =
        quote do
          :ok = @cache_module.del(@cache_opts, unquote(key_ast))
        end

      function_body_ast =
        if on = Keyword.get(opts, :on) do
          quote do
            case super(unquote_splicing(args)) do
              unquote(compile_on_patterns_ast(on, invalidate_ast))
            end
          end
        else
          quote do
            result = super(unquote_splicing(args))

            unquote(invalidate_ast)

            result
          end
        end

      quote do
        def unquote(name)(unquote_splicing(args)) do
          unquote(function_body_ast)
        end
      end
    end
  end

  defp compile_on_patterns_ast(on, invalidate_ast) do
    on = List.wrap(on)

    unmatched_pattern_ast =
      quote do
        other -> other
      end

    patterns_ast =
      for pattern <- on do
        quote do
          unquote(pattern) = result ->
            unquote(invalidate_ast)

            result
        end
      end

    List.flatten(patterns_ast ++ [unmatched_pattern_ast])
  end

  defp compile_key_ast!(template, args_ast, env_module, fun_name, decorator_type)
       when is_binary(template) do
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
            case Map.fetch(arg_ast_by_name, var) do
              {:ok, v_ast} ->
                quote(do: to_string(unquote(v_ast)))

              :error ->
                raise ArgumentError,
                      "#{inspect(__MODULE__)}: unknown variable {#{var}} in :key for " <>
                        "@#{decorator_type} #{inspect(env_module)}.#{fun_name}/#{length(args_ast)}"
            end

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

  defp invalid_key!(env_module, name, args, key, decorator_type) do
    raise ArgumentError,
          "#{inspect(__MODULE__)}: invalid value #{inspect(key)} in :key " <>
            "for @#{decorator_type} #{inspect(env_module)}.#{name}/#{length(args)}"
  end
end
