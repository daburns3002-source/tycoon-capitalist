--!strict
--[[
	A minimal assertion harness.

	Deliberately not a dependency. The economy layer is pure, so testing it needs nothing more
	than "call a function, compare the answer" -- and a test framework that needs Wally, a
	runner and a config file is a thing to maintain rather than a thing that helps.

	Usage:

		local t = TestRunner.new("Cost")
		t:equalsApprox("2nd Car Wash", actual, 820.80)
		local passed, failed = t:finish()
]]

local TestRunner = {}
TestRunner.__index = TestRunner

export type Case = {
	name: string,
	passed: boolean,
	detail: string?,
}

export type Runner = typeof(setmetatable(
	{} :: {
		suite: string,
		cases: { Case },
	},
	TestRunner
))

function TestRunner.new(suite: string): Runner
	return setmetatable({
		suite = suite,
		cases = {},
	}, TestRunner)
end

function TestRunner.record(self: Runner, name: string, passed: boolean, detail: string?): ()
	table.insert(self.cases, { name = name, passed = passed, detail = detail })
end

function TestRunner.isTrue(self: Runner, name: string, condition: boolean): ()
	self:record(name, condition, if condition then nil else "expected true, got false")
end

function TestRunner.equals(self: Runner, name: string, actual: any, expected: any): ()
	local passed = actual == expected
	local detail = if passed
		then nil
		else string.format("expected %s, got %s", tostring(expected), tostring(actual))
	self:record(name, passed, detail)
end

--[[
	Compare two plain numbers within a relative tolerance.

	Relative rather than absolute because these values span 1e0 to 1e306; an absolute epsilon
	is meaningless at both ends.
]]
function TestRunner.equalsApprox(
	self: Runner,
	name: string,
	actual: number,
	expected: number,
	tolerance: number?
): ()
	local allowed = tolerance or 1e-9
	local scale = math.max(math.abs(expected), 1e-12)
	local drift = math.abs(actual - expected) / scale
	local passed = drift <= allowed

	local detail = if passed
		then nil
		else string.format(
			"expected %.10g, got %.10g (relative drift %.3g, allowed %.3g)",
			expected,
			actual,
			drift,
			allowed
		)
	self:record(name, passed, detail)
end

--[[
	Compare a BigNumber against an expected mantissa and exponent.

	Checking the parts rather than collapsing to a plain number is the point: a value at 1e306
	cannot be compared any other way, and a drifting exponent is exactly the bug class this
	whole type exists to prevent.
]]
function TestRunner.bigEquals(
	self: Runner,
	name: string,
	actual: { mantissa: number, exponent: number },
	expectedMantissa: number,
	expectedExponent: number,
	tolerance: number?
): ()
	local allowed = tolerance or 1e-9
	local drift = math.abs(actual.mantissa - expectedMantissa)
		/ math.max(math.abs(expectedMantissa), 1e-12)
	local passed = actual.exponent == expectedExponent and drift <= allowed

	local detail = if passed
		then nil
		else string.format(
			"expected %.12ge%d, got %.12ge%d",
			expectedMantissa,
			expectedExponent,
			actual.mantissa,
			actual.exponent
		)
	self:record(name, passed, detail)
end

--[[ Print a report and return pass and fail counts. ]]
function TestRunner.finish(self: Runner): (number, number)
	local passed, failed = 0, 0

	for _, case in self.cases do
		if case.passed then
			passed += 1
		else
			failed += 1
			warn(string.format("  FAIL  %s / %s -- %s", self.suite, case.name, case.detail or "?"))
		end
	end

	if failed == 0 then
		print(string.format("  ok    %s (%d assertions)", self.suite, passed))
	else
		warn(string.format("  FAILED %s (%d/%d)", self.suite, failed, passed + failed))
	end

	return passed, failed
end

return TestRunner
