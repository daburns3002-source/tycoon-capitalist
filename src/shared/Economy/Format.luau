--!strict
--[[
	Format -- turning BigNumbers into text a player can read.

	Two modes, because the source game and the target UI style disagree:

	* `short` gives "1.23K", "4.56M", "7.89B", and past the named magnitudes falls back to the
	  standard idle-game letter pairs (aa, ab, ac...). Compact, unambiguous, and extends
	  forever, which matters because this economy runs to 1e306.
	* `long` gives "1.23 million", "4.56 quadrillion" -- what AdVenture Capitalist itself
	  prints. Named up to 1e63; beyond that it defers to `short`, since nobody can read
	  "quattuorvigintillion" at a glance anyway.

	Phase 4 picks which one the HUD uses. Both are tested.

	Pure module: no services, no clock, no RNG.
]]

local BigNumber = require(script.Parent.BigNumber)
local Types = require(script.Parent.Parent.Types)

type BigNumber = Types.BigNumber

local Format = {}

-- Index is the power of ten divided by three, so SHORT_SUFFIXES[2] covers 1e6.
local SHORT_SUFFIXES = table.freeze({
	"",
	"K",
	"M",
	"B",
	"T",
	"Qa",
	"Qi",
	"Sx",
	"Sp",
	"Oc",
	"No",
	"Dc",
	"UDc",
	"DDc",
	"TDc",
	"QaDc",
	"QiDc",
	"SxDc",
	"SpDc",
	"ODc",
	"NDc",
	"Vg",
})

local LONG_NAMES = table.freeze({
	"",
	"thousand",
	"million",
	"billion",
	"trillion",
	"quadrillion",
	"quintillion",
	"sextillion",
	"septillion",
	"octillion",
	"nonillion",
	"decillion",
	"undecillion",
	"duodecillion",
	"tredecillion",
	"quattuordecillion",
	"quindecillion",
	"sexdecillion",
	"septendecillion",
	"octodecillion",
	"novemdecillion",
	"vigintillion",
})

local LETTERS = "abcdefghijklmnopqrstuvwxyz"

--[[
	Letter-pair suffix for magnitudes past the named table: aa, ab, ... az, ba, ...

	`group` is the power of ten divided by three. The named table covers groups 0..21, so group
	22 is the first to land here and becomes "aa".
]]
local function letterSuffix(group: number): string
	local offset = group - #SHORT_SUFFIXES
	local first = offset // 26
	local second = offset % 26

	if first < 26 then
		return LETTERS:sub(first + 1, first + 1) .. LETTERS:sub(second + 1, second + 1)
	end

	-- Past 'zz' go to three letters rather than wrapping and colliding.
	local third = first // 26
	first %= 26
	return LETTERS:sub(third + 1, third + 1)
		.. LETTERS:sub(first + 1, first + 1)
		.. LETTERS:sub(second + 1, second + 1)
end

--[[
	Trim trailing zeros from a fixed-point string so 1.00 reads as 1 and 1.50 as 1.5.

	Players read these numbers constantly; "$1.00M" everywhere is visual noise.
]]
local function trimZeros(text: string): string
	if not text:find("%.") then
		return text
	end
	local trimmed = text:gsub("0+$", "")
	return (trimmed:gsub("%.$", ""))
end

--[[
	Split a BigNumber into the leading digits and the thousands-group index.

	The mantissa is in [1, 10) by the BigNumber invariant, so this only needs to redistribute
	the exponent's remainder into the digits: 1.5e7 becomes 15 at group 2 (millions).
]]
local function parts(value: BigNumber): (number, number, boolean)
	local negative = value.mantissa < 0
	local magnitude = math.abs(value.mantissa)
	local exponent = value.exponent

	local group = exponent // 3
	local remainder = exponent - group * 3
	return magnitude * 10 ^ remainder, group, negative
end

--[[
	Compact form: "1.23K", "45.6M", "7.89aa".

	Values under 1000 print whole, because "$847" is how the early game reads and "$847.00"
	is not. Above that, two decimals -- enough to see progress tick without churn.
]]
function Format.short(value: BigNumber): string
	if BigNumber.isZero(value) then
		return "0"
	end

	local digits, group, negative = parts(value)
	local sign = if negative then "-" else ""

	if group <= 0 then
		local plain = BigNumber.toNumber(BigNumber.abs(value))
		if plain < 1 then
			return sign .. trimZeros(string.format("%.2f", plain))
		end
		return sign .. string.format("%d", math.floor(plain))
	end

	local suffix = SHORT_SUFFIXES[group + 1]
	if suffix == nil then
		suffix = letterSuffix(group)
	end

	return sign .. trimZeros(string.format("%.2f", digits)) .. suffix
end

--[[
	Worded form: "1.23 million". What the source game prints.

	Past 1e63 there is no name worth reading, so it defers to `short`.
]]
function Format.long(value: BigNumber): string
	if BigNumber.isZero(value) then
		return "0"
	end

	local digits, group, negative = parts(value)
	local sign = if negative then "-" else ""

	if group <= 0 then
		return Format.short(value)
	end

	local name = LONG_NAMES[group + 1]
	if name == nil then
		return Format.short(value)
	end

	return sign .. trimZeros(string.format("%.2f", digits)) .. " " .. name
end

--[[ Money. The currency symbol lives here so it is changed in one place. ]]
function Format.money(value: BigNumber): string
	return "$" .. Format.short(value)
end

function Format.moneyLong(value: BigNumber): string
	return "$" .. Format.long(value)
end

--[[
	A production cycle duration.

	Cycle times span 0.6 seconds to just over ten hours and get halved up to twelve times, so
	this has to read sensibly across four orders of magnitude.
]]
function Format.duration(seconds: number): string
	if seconds < 1 then
		return string.format("%.1fs", seconds)
	end
	if seconds < 60 then
		return string.format("%ds", math.floor(seconds))
	end

	local totalMinutes = math.floor(seconds / 60)
	if totalMinutes < 60 then
		return string.format("%d:%02d", totalMinutes, math.floor(seconds % 60))
	end

	local hours = totalMinutes // 60
	return string.format("%d:%02d:%02d", hours, totalMinutes % 60, math.floor(seconds % 60))
end

--[[ A whole count with thousands separators: unit counts, angel counts. ]]
function Format.integer(count: number): string
	local text = string.format("%d", math.floor(count))
	local sign = ""
	if text:sub(1, 1) == "-" then
		sign = "-"
		text = text:sub(2)
	end

	local grouped = text:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	grouped = grouped:gsub("^,", "")
	return sign .. grouped
end

return table.freeze(Format)
