# TrueRoll
Lua implementation of the True Roll(tm) algorithm

  Implentation of True Roll for games using Nakama server
  -----------------------------------------
  Author: Huge Workshop
  Created: 2025

  Description:
    TrueRoll(c) is a stateless, auditable die rolling engine in which all server-side randomness is 
    generated at the beginning of the game. After this server state (the trueTable) is fixed, 
    only playerInput (the trueThrow) is allowed as new data into the 
    die rolling generator during the course of the game.

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

