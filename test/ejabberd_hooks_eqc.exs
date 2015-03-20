defmodule Hooks_eqc do
	use ExUnit.Case
	use EQC.ExUnit
	use EQC.Component

	@host <<"domain.net">>

	## generators
	def hookname do elements([:hook1, :hook2, :hook3]) end

	## use maps Elixir has maps anyway and testing is done on R17
	def initial_state do %{} end
	
	## add a handler
	def add_anonymous_args(_state) do [hookname, function1(:ok), choose(0,100)] end

	def add_anonymous(hookname, fun, seq) do
		:ejabberd_hooks.add(hookname, @host, fun, seq)
	end

	def add_anonymous_next(hooks, _, [hookname, _, seq]) do
		Map.put(hooks, hookname, seq)
	end 

	
	## get info on a handler
	def get_args(_hooks) do [ hookname ] end

	def get(hookname) do
		:ejabberd_hooks.get_handlers(hookname, @host)
	end

	def get_post(hooks, [hookname], res) do
		case res do
		  [{seq, :undefined, fun}] when is_function(fun) -> 
				eq(seq, hooks[hookname])
		    # conj fun: is_function(fun), seq: eq(seq, hooks[:hook])
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


