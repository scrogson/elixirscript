defmodule ElixirScript.Translator.Alias.Test do
  use ShouldI
  import ElixirScript.TestHelper

  should "translate alias without as" do
    ex_ast = quote do
        alias Hello.World
    end

    js_code = """
      import * as World from 'hello/world';
    """

    assert_translation(ex_ast, js_code)
  end

  should "translate alias with as" do
    ex_ast = quote do
      alias Hello.World, as: Test
    end

    js_code = """
    import * as Test from 'hello/world';
    """

    assert_translation(ex_ast, js_code)
  end

  should "translate default alias with as" do
    ex_ast = quote do
      alias Hello.World, [as: Test, default: true]
    end

    js_code = """
    import { default as Test } from 'hello/world';
    """

    assert_translation(ex_ast, js_code)
  end

end
