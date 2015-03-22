defmodule Hooks_eqc do
	use ExUnit.Case
	use EQC.ExUnit
	use EQC.Component
	require EQC.Mocking

	@host <<"domain.net">>

	## generators
	def hookname do elements([:hook1, :hook2, :hook3]) end

	def run_params do [] end

	## use maps Elixir has maps anyway and testing is done on R17
	def initial_state do %{} end
	
	## add a handler
	def add_anonymous_args(_hooks) do [hookname, function1(elements([:ok, :error])), choose(0,100)] end

	## May we add the same hook twice, if so we need to change datatype
	def add_anonymous_pre(hooks, [hookname, _, _]) do
		not Map.has_key?(hooks,hookname)
	end
		
	def add_anonymous(hookname, fun, seq) do
		:ejabberd_hooks.add(hookname, @host, fun, seq)
	end

	def add_anonymous_next(hooks, _, [hookname, _, seq]) do
		Map.put(hooks, hookname, seq)
	end 

	## running a handler
	def run_args(_hooks) do [hookname, run_params] end

	def run(hookname, params) do
		:ejabberd_hooks.run(hookname, @host, params)
	end

	def run_post(_hooks, [_hookname, _params], res) do
		eq(res, :ok)
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
	  add_anonymous: 1,
	  get: 1
		
	property "Ejabberd Hooks" do
		:eqc_statem.show_states(
		  EQC.setup :eqc_mocking.start_mocking(api_spec)  do
			forall cmds <- commands(__MODULE__) do
				{:ok, pid} = :ejabberd_hooks.start_link
				:erlang.unlink(pid)
				:true = :ejabberd_hooks.delete_all_hooks
				res =
					run_commands(__MODULE__, cmds)
				:erlang.exit(pid, :kill)
				pretty_commands(__MODULE__, cmds, res,
												:eqc.aggregate(command_names(cmds),	res[:result] == :ok))
				end
		  end)
	end

	def api_spec do
		EQC.Mocking.api_spec [
			modules: [
				EQC.Mocking.api_module name: :mock
			]
		]
	end

		
end


