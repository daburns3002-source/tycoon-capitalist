--!strict
--[[
	Shared type definitions.

	Money is never a plain `number`. A Luau number is a float64 and the economy's prices reach
	~2^1024, so everything monetary is a BigNumber: a normalised mantissa/exponent pair.
	See CLAUDE.md, non-negotiable 1.
]]

export type BigNumber = {
	mantissa: number,
	exponent: number,
}

export type BusinessId = string

export type BusinessConfig = {
	id: BusinessId,
	displayName: string,
	initialCost: BigNumber,
	coefficient: number,
	cycleSeconds: number,
	revenuePerCycle: BigNumber,
}

export type DeviceTier = "Low" | "Medium" | "High"

return nil
