defmodule Hooks_eqc do
	use ExUnit.Case
	use EQC.ExUnit
	use EQC.Component

	@host <<"domain.net">>

	## generators
	def hookname do elements([:test_hook1, :test_hook2]) end

	## use maps Elixir has maps anyway and testing is done on R17
	def initial_state do %{} end
	
	## add a handler
	def add_args(_state) do [hookname, choose(0,100)] end

	def add(hookname, seq) do
		:ejabberd_hooks.add(hookname, @host, fn _ -> :ok end, seq)
	end

	def add_next(hooks, _, [hookname, seq]) do
		Map.put(hooks, hookname, seq)
	end 

	
	## get info on a handler
	def get_args(_hooks) do [ hookname ] end

	def get(hookname) do
		:ejabberd_hooks.get_handlers(hookname, @host)
	end

	def get_post(hooks, [hookname], res) do
		case res do
		  [{seq, mod, name}] ->
				eq({seq, mod, name}, {0, :undefined, hookname})
		    # conj mod: :undefined, name: hookname, seq: 0
			[] ->
				not Map.has_key?(hooks,hookname)	 
			_other ->
					false
	  end
	end

	weight _hooks,
	   add: 1
  	
	property "Ejabberd Hooks" do
		:eqc_statem.show_states(
		forall cmds <- commands(__MODULE__) do
			{:ok, pid} = :ejabberd_hooks.start_link
			:erlang.unlink(pid)
			:true = :ejabberd_hooks.delete_all_hooks
			res =
				run_commands(__MODULE__, cmds)
			:erlang.exit(pid, :kill)
			pretty_commands(__MODULE__, cmds, res,
				:eqc.aggregate(command_names(cmds),	res[:result] == :ok))
		end)
	end
	
end


