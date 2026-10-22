--!strict
--[[
	An in-memory stand-in for a DataStore, and a clock you can move.

	Exists so the session-lock protocol can be tested without publishing the place. The lock is
	the most consequential code in the project -- two servers writing one profile means the loser
	silently discards weeks of progress -- and requiring a published universe to exercise it is
	not a reasonable precondition for testing it.

	`UpdateAsync` reproduces the one behaviour the protocol actually depends on: the transform
	receives the current value, and **returning nil aborts the write**, leaving what was there
	untouched. That abort is how a server declines to steal a lock it does not own, so a fake
	that ignored it would make every lock test pass vacuously.
]]

local FakeStore = {}

export type Fake = {
	store: {
		UpdateAsync: (self: any, key: string, transform: (any) -> any) -> any,
	},
	data: { [string]: any },
	writes: number,
	aborts: number,
}

function FakeStore.new(): Fake
	local fake: Fake = {
		store = nil :: any,
		data = {},
		writes = 0,
		aborts = 0,
	}

	local store = {}

	function store.UpdateAsync(_self: any, key: string, transform: (any) -> any): any
		local result = transform(fake.data[key])
		if result == nil then
			-- Aborted: the stored value is left exactly as it was.
			fake.aborts += 1
			return nil
		end

		fake.data[key] = result
		fake.writes += 1
		return result
	end

	fake.store = store
	return fake
end

--[[ A clock whose value the test sets, so a 120-second rule does not cost 120 seconds. ]]
export type Clock = {
	now: () -> number,
	advance: (seconds: number) -> (),
	set: (seconds: number) -> (),
}

function FakeStore.clock(start: number?): Clock
	local current = start or 1000

	local clock: Clock
	clock = {
		now = function(): number
			return current
		end,
		advance = function(seconds: number): ()
			current += seconds
		end,
		set = function(seconds: number): ()
			current = seconds
		end,
	}
	return clock
end

return table.freeze(FakeStore)
