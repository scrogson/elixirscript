defmodule ElixirScript.State do
  @moduledoc false

  def start_link(root, env \\ __ENV__) do
    Agent.start_link(fn -> %ElixirScript.Env{ root: root, env: env } end, name: __MODULE__)
  end

  def update_env(env) do
    Agent.update(__MODULE__, fn(state) ->
      %{state | env: env }
    end)
  end

  def add_module(module) do
    Agent.update(__MODULE__, fn(state) ->
      %{ state | modules: Set.put(state.modules, module) }
    end)
  end

  def delete_module(module) do
    Agent.update(__MODULE__, fn(state) ->
      %{ state | modules: Set.delete(state.modules, module) }
    end)
  end

  def module_listed?(module_name) do
    Agent.get(__MODULE__, fn(state) ->
      Enum.any?(state.modules, fn(x) -> x.name == module_name end) ||
      Enum.any?(state.protocols, fn({key, _}) -> key == module_name end)
    end)
  end

  def protocol_listed?(module_name) do
    Agent.get(__MODULE__, fn(state) ->
      Enum.any?(state.protocols, fn({key, _}) -> key == module_name end)
    end)
  end

  def add_protocol(name, spec) do
    Agent.update(__MODULE__, fn(state) ->
      proto = Dict.get(state.protocols, name)

      if proto == nil do
        proto = %{name: name, spec: spec, impls: HashDict.new }
      else
        proto = %{ proto | spec: spec }
      end

      %{ state | protocols: Dict.put(state.protocols, name, proto) }
    end)
  end

  def add_protocol_impl(protocol, type, impl) when is_list(type) do
    Enum.each(type, fn(x) ->
      add_protocol_impl(protocol, x, impl)
    end)
  end

  def add_protocol_impl(protocol, type, impl) do
    Agent.update(__MODULE__, fn(state) ->
      proto = Dict.get(state.protocols, protocol)

      if proto == nil do
        proto = %{name: protocol, spec: nil, impls: HashDict.new }
      end

      proto = %{ proto | impls: Dict.put(proto.impls, type, impl) }

      %{ state | protocols: Dict.put(state.protocols, protocol, proto) }
    end)
  end

  def get() do
    Agent.get(__MODULE__, fn(state) ->
      state
    end)
  end

  def get_module(module) when is_atom(module) do
    module_name_list = Atom.to_string(module)
    |> String.split(".")
    |> tl
    |> Enum.map(fn(x) -> String.to_atom(x) end)

    get_module(module_name_list)
  end


  def get_module(module_name_list) do
    state = Agent.get(__MODULE__, fn(state) ->
      state
    end)

    do_get_module(state, module_name_list)
  end

  defp do_get_module(state, module) when is_atom(module) do
    module_name_list = Atom.to_string(module)
    |> String.split(".")
    |> tl
    |> Enum.map(fn(x) -> String.to_atom(x) end)

    do_get_module(state, module_name_list)
  end

  defp do_get_module(state, module_name_list) do
    Enum.find(Set.to_list(state.modules), fn(x) ->
      x.name == module_name_list
    end)
  end


  def add_alias(module_name_list, name) do
    module = get_module(module_name_list)

    if module do
      {main, _} = Code.eval_quoted(name)
      {:__aliases__, _, aliases } = name
      {the_alias, _} = Code.eval_quoted({:__aliases__, [alias: false], List.last(aliases) |> List.wrap })

      delete_module(module)

      module = %{module | aliases: Set.put(module.aliases, {the_alias, main}) }
      add_module(module)
    end
  end

  def process_imports() do
    Agent.update(__MODULE__, fn(state) ->
      modules = state.modules
      |> Enum.map(fn(x) ->
        %{x | imports: Enum.map(x.imports, fn({y, options}) -> {y, get_imported_functions(state, y, options)}  end)}
      end)

      %{ state | modules: Enum.into(modules, HashSet.new) }
    end)
  end

  defp get_imported_functions(state, module_name, []) do
    module = do_get_module(state, module_name)
    ElixirScript.Module.functions(module) ++ ElixirScript.Module.macros(module)
  end

  defp get_imported_functions(_, _, [only: list]) do
    Keyword.keys(list)
  end

  defp get_imported_functions(state, module_name, [only: :functions]) do
    module = do_get_module(state, module_name)
    ElixirScript.Module.functions(module)
  end

  defp get_imported_functions(state, module_name, [only: :macros]) do
    module = do_get_module(state, module_name)
    ElixirScript.Module.macros(module)
  end

  defp get_imported_functions(state, module_name, [except: list]) do
    module = do_get_module(state, module_name)
    ElixirScript.Module.functions(module) ++ ElixirScript.Module.macros(module) -- Keyword.keys(list)
  end

  def stop() do
    Agent.stop(__MODULE__)
  end

end
