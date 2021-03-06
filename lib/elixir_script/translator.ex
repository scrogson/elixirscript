defmodule ElixirScript.Translator do
  @moduledoc """
  Translates the given Elixir AST into JavaScript AST
  """
  alias ElixirScript.Translator.Primitive
  alias ElixirScript.Translator.Assignment
  alias ElixirScript.Translator.Map
  alias ElixirScript.Translator.Function
  alias ElixirScript.Translator.Capture
  alias ElixirScript.Translator.Import
  alias ElixirScript.Translator.Cond
  alias ElixirScript.Translator.Case
  alias ElixirScript.Translator.For
  alias ElixirScript.Translator.Try
  alias ElixirScript.Translator.Block
  alias ElixirScript.Translator.Struct
  alias ElixirScript.Translator.Module
  alias ElixirScript.Translator.Utils
  alias ElixirScript.Translator.Bitstring
  alias ElixirScript.Translator.Receive
  alias ElixirScript.Translator.Quote
  alias ElixirScript.Translator.Utils
  alias ElixirScript.Translator.Protocol
  alias ElixirScript.Translator.Kernel, as: KernelLib
  alias ElixirScript.Translator.Logger
  alias ElixirScript.Translator.JS, as: JSLib
  alias ESTree.Tools.Builder, as: JS

  @standard_lib_protocols [
    [:Enumerable],
    [:Inspect],
    [:String, :Chars],
    [:List, :Chars],
    [:Collectable]
  ]


  @doc """
  Translates Elixir AST to JavaScript AST
  """
  def translate(ast, env) do
    do_translate(ast, env)
  end

  defp do_translate(ast, _) when is_number(ast) or is_binary(ast) or is_boolean(ast) or is_nil(ast) do
    Primitive.make_literal(ast)
  end

  defp do_translate(ast, _) when is_atom(ast) do
    Primitive.make_atom(ast)
  end

  defp do_translate(ast, env) when is_list(ast) do
    Primitive.make_list(ast, env)
  end

  defp do_translate({ one, two }, env) do
    Primitive.make_tuple({one, two}, env)
  end

  defp do_translate({:&, [], [number]}, _) when is_number(number) do
    Primitive.make_identifier(String.to_atom("__#{number}"))
  end

  defp do_translate({:&, _, [{:/, _, [{{:., _, [{:__aliases__, _, module_name}, function_name]}, _, []}, arity]}]}, env) do
    function_name = Utils.filter_name(function_name)
    Capture.make_capture(List.last(module_name), function_name, arity, env)
  end

  defp do_translate({:&, _, [{:/, _, [{function_name, _, _}, arity]}]}, env) do
    function_name = Utils.filter_name(function_name)
    Capture.make_capture(function_name, arity, env)
  end

  defp do_translate({:&, _, body}, env) do
    params = Capture.find_value_placeholders(body) |> List.flatten
    Function.make_anonymous_function([{:->, [], [params, body]}], env)
  end

  defp do_translate({:@, _, [{name, _, _}]}, _)
  when name in [:doc, :moduledoc, :type, :typep, :spec, :opaque, :callback, :macrocallback] do
    %ElixirScript.Translator.Group{}
  end

  defp do_translate({:@, _, [{name, _, [value]}]}, env) do
    name = Utils.filter_name(name)
    Module.make_attribute(name, value, env)
  end

  defp do_translate({:@, _, [{name, _, _}]}, _) do
    name = Utils.filter_name(name)
    Primitive.make_identifier(name)
  end

  defp do_translate({:%, _, [alias_info, data]}, env) do
    {_, _, name} = alias_info
    Struct.make_struct(name, data, env)
  end

  defp do_translate({:%{}, _, [{:|, _, [map, data]}]}, env) do
    Map.make_map_update(map, data, env);
  end

  defp do_translate({:%{}, _, properties}, env) do
    Map.make_object(properties, env)
  end

  defp do_translate({:<<>>, _, elements}, env) do
    is_interpolated_string = Enum.all?(elements, fn(x) ->
      case x do
        b when is_binary(b) ->
          true
        {:::, _, [_target, {:binary, _, _}]} ->
          true
        _ ->
          false
      end
    end)

    case is_interpolated_string do
      true ->
        Bitstring.make_interpolated_string(elements, env)
      _ ->
        Bitstring.make_bitstring(elements, env)
    end
  end

  defp do_translate({{:., _, [{:__aliases__, _, [:Logger]}, function_name]}, _, params }, env) do
    Logger.make_logger(function_name, params, env)
  end

  defp do_translate({{:., _, [Access, :get]}, _, [target, property]}, env) do
    Map.make_get_property(target, property, env)
  end

  defp do_translate({{:., _, [function_name]}, _, params}, env) do
    Function.make_function_call(function_name, params, env)
  end

  defp do_translate({:., _, [module_name, function_name]} = ast, env) do
    expanded_ast = Macro.expand(ast, env)

    if expanded_ast == ast do
      Function.make_function_or_property_call(module_name, function_name, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [module_name, function_name]}, _, [] } = ast, env) do
    expanded_ast = Macro.expand(ast, env)

    if expanded_ast == ast do
      Function.make_function_or_property_call(module_name, function_name, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [{:__aliases__, _, module_name}]}, _, params} = ast, env) do
    expanded_ast = Macro.expand(ast, env)
    if expanded_ast == ast do
      Function.make_function_call(hd(module_name), params, env)
    else
      translate(expanded_ast, env)
    end
  end

  defp do_translate({{:., _, [module_name, function_name]}, _, params } = ast, env) do
    case module_name do
      Kernel ->
        KernelLib.translate_kernel_function(function_name, params, env)
      {:__aliases__, _, [:JS]} ->
        JSLib.translate_js_function(function_name, params, env)
      _ ->
        expanded_ast = Macro.expand(ast, env)
        if expanded_ast == ast do
          Function.make_function_call(module_name, function_name, params, env)
        else
          translate(expanded_ast, env)
        end
    end
  end

  defp do_translate({:_, _, _}, _env) do
    Primitive.make_identifier(:undefined)
  end

  defp do_translate({:__aliases__, _, aliases}, _) do
    Primitive.make_identifier({:__aliases__, [], aliases})
  end

  defp do_translate({:__block__, _, expressions }, env) do
    Block.make_block(expressions, env)
  end

  defp do_translate({:__DIR__, _, _}, _) do
    JS.call_expression(
      JS.member_expression(
        Primitive.special_forms(),
        JS.identifier(:__DIR__)
      ),
      []
    )
  end

  defp do_translate({:try, _, [ blocks ]}, env) do
    Try.make_try(blocks, env)
  end

  defp do_translate({:receive, _, [expressions] }, env) do
    Receive.make_receive(expressions, env);
  end

  defp do_translate({:super, _, _expressions }, _) do
    raise ElixirScript.UnsupportedError, "super"
  end

  defp do_translate({:__CALLER__, _, _expressions }, _) do
    raise ElixirScript.UnsupportedError, "__CALLER__"
  end

  defp do_translate({:__ENV__, _, _expressions }, _) do
    raise ElixirScript.UnsupportedError, "__ENV__"
  end

  defp do_translate({:quote, _, [[do: expr]]}, env) do
    Quote.make_quote([], expr, env)
  end

  defp do_translate({:quote, _, [opts, [do: expr]]}, env) do
    Quote.make_quote(opts, expr, env)
  end

  defp do_translate({:import, _, _}, _) do
    %ElixirScript.Translator.Group{}
  end

  defp do_translate({:alias, _, [alias_info, options]}, _) when is_tuple(alias_info) do
    Import.make_alias_import(alias_info, options)
  end

  defp do_translate({:alias, _, [alias_info]}, _) when is_tuple(alias_info) do
    Import.make_alias_import(alias_info, [])
  end

  defp do_translate({:require, _, [alias_info, options]}, _) do
    Import.make_alias_import(alias_info, options)
  end

  defp do_translate({:require, _, [alias_info]}, _) do
    Import.make_alias_import(alias_info, [])
  end

  defp do_translate({:case, _, [condition, [do: clauses]]}, env) do
    Case.make_case(condition, clauses, env)
  end

  defp do_translate({:cond, _, [[do: clauses]]}, env) do
    Cond.make_cond(clauses, env)
  end

  defp do_translate({:for, _, generators}, env) do
    For.make_for(generators, env)
  end

  defp do_translate({:fn, _, clauses}, env) do
    Function.make_anonymous_function(clauses, env)
  end

  defp do_translate({:{}, _, elements}, env) do
    Primitive.make_tuple(elements, env)
  end

  defp do_translate({:=, _, [left, right]}, env) do
    Assignment.make_assignment(left, right, env)
  end

  defp do_translate({function, _, [{:when, _, [{name, _, _params} | _guards] }, [do: _body]] } = ast, env) when function in [:def, :defp] do
    Function.process_function(Utils.filter_name(name), [ast], env)
  end

  defp do_translate({function, _, [{name, _, _params}, [do: _body]]} = ast, env) when function in [:def, :defp] do
    Function.process_function(Utils.filter_name(name), [ast], env)
  end

  defp do_translate({:defstruct, _, attributes}, env) do
    Struct.make_defstruct(attributes, env)
  end

  defp do_translate({:defexception, _, attributes}, env) do
    Struct.make_defexception(attributes, env)
  end

  defp do_translate({:defmodule, _, [{:__aliases__, _, module_name_list}, [do: body]]}, env) do
    Module.make_module(module_name_list, body, env)
  end

  defp do_translate({:defprotocol, _, _}, _) do
    %ElixirScript.Translator.Group{}
  end

  defp do_translate({:defimpl, _, [ {:__aliases__, _, protocol}, [for: type],  [do: {:__block__, context, spec}] ]}, env) when protocol in @standard_lib_protocols do
    Protocol.make_standard_lib_impl({:__aliases__, [], [:Elixir] ++ protocol}, type, {:__block__, context, spec}, env)
  end

  defp do_translate({:defimpl, _, [ {:__aliases__, _, protocol}, [for: type],  [do: spec] ]}, env) when protocol in @standard_lib_protocols do
    Protocol.make_standard_lib_impl({:__aliases__, [], [:Elixir] ++ protocol}, type, {:__block__, [], [spec]}, env)
  end

  defp do_translate({:defimpl, _, _}, _) do
    %ElixirScript.Translator.Group{}
  end

  defp do_translate({:|, _, [elem, list]}, env) do
    quoted = quote do
      List.prepend(unquote(list), unquote(elem))
    end

    translate(quoted, env)
  end

  defp do_translate({name, _, params} = ast, env) when is_list(params) do
    if KernelLib.is_defined_in_kernel(name, length(params)) do
      KernelLib.translate_kernel_function(name, params, env)
    else
      expanded_ast = Macro.expand(ast, env)
      if expanded_ast == ast do
        module = ElixirScript.State.get_module(Process.get(:current_module))
        imported_module = ElixirScript.Module.imported?(module, name)

        if imported_module do
          imported_module = ElixirScript.State.get_module(imported_module)
          Function.make_function_call({:__aliases__, [], List.last(imported_module.name) |> List.wrap }, name, params, env)
        else
          Function.make_function_call(name, params, env)
        end
      else
        translate(expanded_ast, env)
      end
    end
  end

  defp do_translate({ name, _, _ }, _) do
    name = Utils.filter_name(name)
    Primitive.make_identifier(name)
  end

end
