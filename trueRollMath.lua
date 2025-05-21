--[[
  trueRollMath
  Implentation of TrueRoll(c) A Stateless, auditable, player-influenced die roller
  for games using Nakama server
  -----------------------------------------
  Author: Huge Workshop
  Created: 2025


  Description:
    TrueRoll(c) is a auditable die rolling engine in which all server-side randomness is 
    generated at the beginning of the game. After this server state (the trueTable) is fixed, 
    only playerInput (the trueThrow) is allowed as new data into the 
    random number generator during the course of the game.

    - Uses a pre-generated random seed table (trueTable) at game start
    - Player input (trueThrow) adds physical entropy with each die roll
    - Player touch input influences rolls but cannot bias the system
    - Stateless between rolls
    - Results verifiable by any observer with the seed table + inputs
    - Built for Lua 5.1 (Nakama server scripting)
    - Every number depends only on the initial public seed table and user inputs
    - Hash of seed table (trueTable) can be generated to send to players at the beginning of the game

  Testing Note:
    - When running outside Nakama, substitute nk.rand_bytes and nk.sha256_hash
    - See local test block at the bottom for mass testing roll distribution

  Usage:
    local trueTable, seed = trueRollMath.initialize_true_roll(64)  <- Generate these at the start of the game. Save in DB 
    local roll, newSeed = trueRollMath.throw_true_die(player_input, 6, trueTable, seed)  <- Do this for every roll. Save newSeed in DB after each use
    local hash = hash_true_table(trueTable) <- Send this to the player at the beginning of the game

]]


-- Nakama library is for nk.rand_bytes and nk.hash256

local nk = require("nakama")
local bit = bit32 --Nakama just includes this, do 
--[[ -- TO TEST IN VSCODE replace nk and bit require above with THIS STUB (space between brackets)---------
-- true_roll_mass_test is at the bottom
-- Minimal local nk stub for trueRollMath.lua testing
local nk = {}
local bit = require("bit32") --Nakama auto-includes

-- Local nk_xorshift seed for fake random when nk.rand_bytes isn't available
local nk_xorshift_seed = math.random(1, 2147483647) + os.time() -- Get this going 

local function nk_xorshift32()
    local x = nk_xorshift_seed
    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    x = x % 4294967296
    if x == 0 then
        x = 1
    end
    nk_xorshift_seed = x
    return x
end

-- Substitute for nk.rand_bytes
function nk.rand_bytes(bytes_needed)
    local bytes = {}
    for i = 1, bytes_needed do
        local rand_byte = math.floor((nk_xorshift32() / 4294967296) * 256)
        table.insert(bytes, string.char(rand_byte))
    end
    return table.concat(bytes)
end

-- Fake substitute for nk.sha256_hash
function nk.sha256_hash(str)
    -- Totally non-crypto fake "hash" for testing
    local sum = 0
    for i = 1, #str do
        sum = (sum + string.byte(str, i) * i) % 4294967296
    end
    return string.format("FAKEHASH_%08X", sum)
end

 --END LOCAL TESTING STUB ---------------------------------------------------------
 --]]

local trueRollMath = {}


-- --- Upgraded Xorshift32
local function xorshift32_strong(seed)
    local x = seed

    x = bit.bxor(x, bit.lshift(x, 13))
    x = bit.bxor(x, bit.rshift(x, 17))
    x = bit.bxor(x, bit.lshift(x, 5))
    x = bit.band(x, 0xFFFFFFFF)

    x = bit.bxor(x, bit.lshift(x, 7))
    x = bit.bxor(x, bit.rshift(x, 11))
    x = bit.band(x, 0xFFFFFFFF)

    -- Force positive result
    if x < 0 then
        x = x + 4294967296
    end

    -- If by some miracle it became zero, fix it
    if x == 0 then
        x = 1
    end

    return x
end


-- --- Initialize a new TrueRoll table from a provided array of random numbers
function trueRollMath.initialize_true_roll(rand_array)
    assert(type(rand_array) == "table", "Expected an array of random numbers.")
    local table_size = #rand_array
    assert(table_size > 0, "Random array must not be empty.")

    local trueTable = {}

    for i = 1, table_size do
        local num = rand_array[i]
        assert(type(num) == "number", "Random array must contain only numbers.")
        num = num % 4294967296
        if num == 0 then
            num = 1
        end
        trueTable[i] = num
    end

    return trueTable, 1 -- Initial seed always starts at 1
end


-- --- Generate a true random roll
function trueRollMath.throw_true_die(trueThrow, dieSize, trueTable, advancingSeed)
    assert(type(trueTable) == "table", "Expected trueTable to be a table.")
    assert(type(advancingSeed) == "number", "Expected advancingSeed to be a number.")

    -- Derive table index from advancingSeed
    local tableIndex = (advancingSeed % #trueTable) + 1

    -- Just to keep low or weird trueThrow values 
    local mix = bit.bxor(trueThrow, 0xA5A5A5A5) % 4294967296

    -- Combine everything into one seed
    local combined_seed = (trueTable[tableIndex] + mix + advancingSeed) % 4294967296
    if combined_seed == 0 then
        combined_seed = 1
    end

    -- Advance
    local advanced_seed = xorshift32_strong(combined_seed)

    -- Generate random float [0,1)
    local r = advanced_seed / 4294967296

    -- Map to die roll [1, dieSize]
    local roll = math.floor(r * dieSize) + 1

    -- Advance advancingSeed for next roll
    local newAdvancingSeed = advanced_seed

    return roll, newAdvancingSeed
end


-- --- Hash the trueTable into a verification string
function trueRollMath.hash_true_table(trueTable)
    assert(type(trueTable) == "table", "Expected trueTable to be a table.")

    local concat = ""
    for i, v in ipairs(trueTable) do
        concat = concat .. tostring(v) .. ","
    end

    -- Remove trailing comma
    if #concat > 0 then
        concat = string.sub(concat, 1, -2)
    end

    -- Hash it
    return nk.sha256_hash(concat)
end

----------------------------------------------------------------------------------
------------ TESTING -------------------------------------------------------------


local function true_roll_mass_test(roll_count, die_size, table_size)
    print("=== TrueRoll Mass Test ===")

    --nk_xorshift_seed = 6

    -- Initialize TrueRoll
    local trueTable, advancingSeed = trueRollMath.initialize_true_roll(table_size)
    local trueTableHash = trueRollMath.hash_true_table(trueTable)

    print("Initial trueTable hash:", trueTableHash)
    print(string.format("Rolling %d times on d%d...", roll_count, die_size))

    -- Roll counter
    local counts = {}
    for i = 1, die_size do
        counts[i] = 0
    end

    -- Simulate rolls
    for _ = 1, roll_count do
        local trueThrow = math.random(1, 2147483647)  -- Fake player input
        local roll, newIndex = trueRollMath.throw_true_die(trueThrow, die_size, trueTable, advancingSeed)
        
        counts[roll] = counts[roll] + 1
        advancingSeed = newIndex
    end

    -- Print results
    print("=== TrueRoll Distribution ===")
    for i = 1, die_size do
        local percent = (counts[i] / roll_count) * 100
        local bar = string.rep("x", math.floor(percent * 2))  -- 2x scale bar
        print(string.format("Face %2d: %6d rolls (%5.2f%%) %s", i, counts[i], percent, bar))
    end

    print("=== End of Test ===")
end

-- local trueRollMath = require("trueRollMath")
--true_roll_mass_test(10000000, 6, 64) -- <-- 3. To test locally comment in 

return trueRollMath
