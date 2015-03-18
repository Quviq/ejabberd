# ----------------------------------------------------------------------
#
# ejabberd, Copyright (C) 2002-2015   ProcessOne
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License as
# published by the Free Software Foundation; either version 2 of the
# License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# General Public License for more details.
#
# You should have received a copy of the GNU General Public License along
# with this program; if not, write to the Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
#
# ----------------------------------------------------------------------

defmodule EjabberdHooksTest do
  use ExUnit.Case, async: true
  
  @author "mremond@process-one.net"
  @host <<"domain.net">>
  @self __MODULE__
  
  setup_all do
    {:ok, _Pid} = :ejabberd_hooks.start_link
    :ok
  end
  
  setup do
    :meck.unload
    :true = :ejabberd_hooks.delete_all_hooks
    :ok
  end  
  
  test "An anonymous function can be added as a hook" do
    hookname = :test_fun_hook
    :ok = :ejabberd_hooks.add(hookname, @host, fn _ -> :ok end, 50)
    [{50, :undefined, _}] = :ejabberd_hooks.get_handlers(hookname, @host)
  end
  
  test "A module function can be added as a hook" do
    hookname = :test_mod_hook
    modulename = :hook_module
    callback = :hook_callback
    mock(modulename, callback, fn -> :ok end)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, callback, 40)
    [{40, ^modulename, ^callback}] = :ejabberd_hooks.get_handlers(hookname, @host)
  end

  test "An anonymous function can be removed from hook handlers" do
    hookname = :test_fun_hook
    anon_fun = fn _ -> :ok end                                              
    :ok = :ejabberd_hooks.add(hookname, @host, anon_fun, 50)
    :ok = :ejabberd_hooks.delete(hookname, @host, anon_fun, 50)
    [] = :ejabberd_hooks.get_handlers(hookname, @host)
  end

  test "A module function can be removed from hook handlers" do
    hookname = :test_mod_hook
    modulename = :hook_module
    callback = :hook_callback
    mock(modulename, callback, fn -> :ok end)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, callback, 40)
    :ok = :ejabberd_hooks.delete(hookname, @host, modulename, callback, 40)
    [] = :ejabberd_hooks.get_handlers(hookname, @host)
    # TODO: Check that removed function is not called anymore
  end

  test "'Run hook' call registered handler once" do
    test_result = :hook_result
    run_hook([], fn -> test_result end, test_result)
  end

  test "'Run hook' can call registered handler with parameters" do
    test_result = :hook_result_with_params
    run_hook([:hook_params], fn _ -> test_result end, test_result)
  end

  # TODO test "Several handlers are run in order by hook"
  
  test "Hook run chain is stopped when handler return 'stop'" do
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    mock(modulename, :hook_callback1, fn _ -> :stop end)
    mock(modulename, :hook_callback2, fn _ -> :end_result end)
    
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 40)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 50)

    :ok = :ejabberd_hooks.run(hookname, @host, [:hook_params])
    # callback2 is never run:
    [{_pid, {^modulename, _callback, [:hook_params]}, :stop}] = :meck.history(modulename)   
  end

  test "Run fold hooks accumulate state in correct order through handlers" do
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    mock(modulename, :hook_callback1, fn(list, user) -> [user|list] end)
    mock(modulename, :hook_callback2, fn(list, _user) -> ["jid2"|list] end)
    
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 40)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback2, 50)
    
    ["jid2", "jid1"] = :ejabberd_hooks.run_fold(hookname, @host, [], ["jid1"])
  end

  test "Hook run_fold are executed based on priority order, not registration order" do
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    mock(modulename, :hook_callback1, fn(_acc) -> :first end)
    mock(modulename, :hook_callback2, fn(_acc) -> :second end)

    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback2, 50)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 40)
    
    :second = :ejabberd_hooks.run_fold(hookname, @host, :started, [])
    # Both module have been called:
    2 = length(:meck.history(modulename))
  end
  
  # TODO: Test with ability to stop and return a value
  test "Hook run_fold chain is stopped when handler return 'stop'" do
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    mock(modulename, :hook_callback1, fn(_acc) -> :stop end)
    mock(modulename, :hook_callback2, fn(_acc) -> :executed end)

    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 40)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback2, 50)

    :stopped = :ejabberd_hooks.run_fold(hookname, @host, :started, [])
    # Only one module has been called
    [{_pid, {^modulename, :hook_callback1, [:started]}, :stop}] = :meck.history(modulename)
  end

  test "Error in run_fold is ignored" do
    run_fold_crash(fn(_acc) -> raise "crashed" end)
  end

  test "Throw in run_fold is ignored" do
    run_fold_crash(fn(_acc) -> throw :crashed end)
  end

  test "Exit in run_fold is ignored" do
    run_fold_crash(fn(_acc) -> exit :crashed end)
  end

  # TODO: Improve test of all hooks list
  test "Parse Transform is used to generate list of hooks" do
    hooks = :ejabberd_hooks_core.all
    # We get a list of hooks records:
    [hook|_]  = hooks
    :hook = elem(hook, 0)
  end

  test "All handlers for a given hook and module can be removed all at once" do
    hookname = :test_mod_hook
    module1_name = :hook_module_1
    module2_name = :hook_module_2
    mock(module1_name, :hook_callback_1, fn _ -> :ok end)
    mock(module1_name, :hook_callback_2, fn _ -> :ok end)
    mock(module2_name, :hook_callback, fn _ -> :ok end)
    
    :ok = :ejabberd_hooks.add(hookname, @host, module1_name, :hook_callback_1, 40)
    :ok = :ejabberd_hooks.add(hookname, @host, module1_name, :hook_callback_2, 50)
    :ok = :ejabberd_hooks.add(hookname, @host, module2_name, :hook_callback, 50)

    :ok = :ejabberd_hooks.remove_module_handlers(hookname, @host, module1_name)
    [{50, ^module2_name, :hook_callback}] = :ejabberd_hooks.get_handlers(hookname, @host)
  end

  test "We can retrieve the list of hooks that have handlers defined" do
    hookname1 = :test_mod_hook_1
    hookname2 = :test_mod_hook_2
    module1_name = :hook_module_1
    module2_name = :hook_module_2
    mock(module1_name, :hook_callback_1, fn _ -> :ok end)
    mock(module1_name, :hook_callback_2, fn _ -> :ok end)
    mock(module2_name, :hook_callback, fn _ -> :ok end)
    
    :ok = :ejabberd_hooks.add(hookname1, @host, module1_name, :hook_callback_1, 40)
    :ok = :ejabberd_hooks.add(hookname2, @host, module1_name, :hook_callback_2, 50)
    :ok = :ejabberd_hooks.add(hookname1, @host, module2_name, :hook_callback, 50)

    [:test_mod_hook_1, :test_mod_hook_2] = :ejabberd_hooks.get_hooks_with_handlers
  end
  
  test "We cannot set hook handler for non-existing module or function for any hook" do
    hookname = :custom_hook
    module_name = :hook_module

    {:error, :module_not_found} = :ejabberd_hooks.add(hookname, @host, module_name, :hook_callback, 40)
    [] = :ejabberd_hooks.get_handlers(hookname, @host)

    corehook = :filter_packet
    {:error, :module_not_found} = :ejabberd_hooks.add(corehook, @host, module_name, :hook_callback, 40)
    [] = :ejabberd_hooks.get_handlers(corehook, @host)

    mock_module(module_name) # Module now exist, without function
    {:error, :undefined_function} = :ejabberd_hooks.add(hookname, @host, module_name, :hook_callback_undef, 40)
    [] = :ejabberd_hooks.get_handlers(hookname, @host)
  end

  # Core hooks are hooks defined in core module
  test "We cannot set hook handler with wrong arity for core hooks" do
    module_name = :hook_module
    mock(module_name, :hook_callback, fn -> :ok end)    

    corehook = :filter_packet
    {:error, :incorrect_arity} = :ejabberd_hooks.add(corehook, @host, module_name, :hook_callback, 40)
    [] = :ejabberd_hooks.get_handlers(corehook, @host)
  end
  
  # Test helpers
  # ============
  
  # test for run hook with various number of params
  def run_hook(params, fun, result) do 
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    callback = :hook_callback
    mock(modulename, callback, fun)
    
    # Then check
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, callback, 40)
    :ok = :ejabberd_hooks.run(hookname, @host, params)
    [{_pid, {^modulename, ^callback, ^params}, ^result}] = :meck.history(modulename)   
  end

  def run_fold_crash(crash_fun) do
    # setup test
    hookname = :test_mod_hook
    modulename = :hook_module
    mock(modulename, :hook_callback1, crash_fun)
    mock(modulename, :hook_callback2, fn(_acc) -> :final end)

    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback1, 40)
    :ok = :ejabberd_hooks.add(hookname, @host, modulename, :hook_callback2, 50)

    :final = :ejabberd_hooks.run_fold(hookname, @host, :started, [])
    # Both handlers were called
    2 = length(:meck.history(modulename))    
  end

  # TODO refactor: Move to ejabberd_test_mock
  defp mock(module, function, fun) do
    mock_module(module)
    :meck.expect(module, function, fun)
  end

  defp mock_module(module) do
    try do
      :meck.new(module, [:non_strict])
    catch
      :error, {:already_started, _pid} -> :ok
    end
  end
  
end
