#version 2
#include "mplib/hud.lua"
#include "mplib/teams.lua"
#include "mplib/spectate.lua"
#include "mplib/util.lua"
#include "mplib/spawn.lua"
#include "script/include/player.lua"
#include "mantle.lua"
#include "monster_rig.lua"
#include "monster_anim.lua"
#include "monster_visual.lua"
#include "eh_combat.lua"
#include "eh_monster.lua"

-- Echo Hunt: the game mode (gamemodes.txt; playable on any map: the map's spawn points or generated ones).
-- Lobby: teams Humans / Monster (mplib), host settings (round time, head start, time of day). A round: the humans
-- get a head start to hide while the monster is frozen and blind; then it hunts by sound (eh_monster.lua: its view,
-- hearing, pulse, stamina, jump, mantle, calls) and catches them (eh_combat.lua: LMB grabs a human in reach, else
-- tears into what it aims at; its HP, hit boxes, the stun when the humans bring it down, the slow heal). Caught
-- humans spectate (and talk only to each other with Proximity Comms). The humans win when the time runs out with one
-- of them standing, the monsters when none is left. Scoreboard (hold the scoreboard key) and results: each human's
-- status / survival time, each monster's catches, the session's wins.
-- Several monsters may play (AgeOfAlgorithms): whoever joins the Monster team (a random one if nobody does; at least one human
-- always stays human). They see and hear each other; each has its own HP, stun, stamina.
-- (Every script below only shares GLOBALS with its includes: an included file's locals are its own.)

TEAM_HUMANS, TEAM_MONSTER = 1, 2
HUD_SCOREBOARD_KEY = "l"     -- (mplib/hud.lua: the scoreboard on L - the game's "scoreboard" is Shift, the monster's run; AgeOfAlgorithms)
HUMAN_LOADOUT = {{"gun", 12}, {"sledge", 0}, {"plank", 5}}   -- (5 planks: AgeOfAlgorithms)
MONSTER_LOADOUT = {}
MAX_MONSTERS = 6             -- (at most; at least one player always stays human)
CAUGHT_SHOW = 4              -- s the "<name> was caught" line stays

ROUND_KEY = "savegame.mod.eh.roundsec"   -- (renamed with the 30 s steps: an old saved choice meant another time)
HEAD_KEY = "savegame.mod.eh.headsec"
-- a list starting at its default and wrapping round (mplib's stepper is cyclic; a setting not chosen yet and its
-- Reset take the first option): the arrows step by one either way
local function steps(first, last, step, default, label)
	local l, n = {}, math.floor((last - first) / step + 0.5) + 1
	local d = math.floor((default - first) / step + 0.5)
	for i = 0, n - 1 do
		local v = first + ((d + i) % n) * step
		l[#l + 1] = {label = label(v), value = v}
	end
	return l
end
ROUND_OPTIONS = steps(60, 1200, 30, 300, function(v) return string.format("%d:%02d", math.floor(v / 60), v % 60) end)
                                                             -- 1-20 min by 30 s (AgeOfAlgorithms), 5:00 first
HEAD_OPTIONS = steps(5, 120, 5, 30, function(v) return v .. " s" end)               -- 5-120 s by 5 (AgeOfAlgorithms), 30 first

SETTINGS = {
	{
		title = "",
		items = {
			{key = ROUND_KEY, label = "Round time", info = "How long the humans must survive",
				options = ROUND_OPTIONS},
			{key = HEAD_KEY, label = "Head start", info = "How long the humans have to hide",
				options = HEAD_OPTIONS},
			{key = "savegame.mod.eh.weather", label = "Time of day", info = "For everyone (the map's own: leave it as it is)",
				options = {{label = "Night", value = "night"}, {label = "Evening", value = "sunset"}, {label = "Day", value = "sunny"},
					{label = "Foggy", value = "foggy"}, {label = "Rainy night", value = "rainynight"}, {label = "The map's own", value = "map"}}},
			{key = "savegame.mod.eh.globalchat", label = "Global chat in round", info = "Off: only nearby talk (and the dead's chat) once the round starts",
				options = {{label = "On", value = "on"}, {label = "Off", value = "off"}}},
		},
	},
}

----- server -----

local G = {phase = "lobby", t = 0, monsters = {}, winner = "", roundTime = 300, headStart = 30, weather = "night",
	huntT0 = 0, out = {}, pubT = -1, humans = 0, roster = {}, late = {}}
local spawnsHumans, spawnsMonster = {}, {}
EH_OUT = G.out                                                   -- (eh_combat.lua: caught humans can't be grabbed)

local function publish(force)
	local now = GetTime()
	if not force and now - G.pubT < 0.2 then return end          -- (the clock: 5 times a second is enough)
	G.pubT = now
	local out, late = {}, {}
	for p, t in pairs(G.out) do out[p] = t end
	for p in pairs(G.late) do late[p] = true end
	local catches, stats = {}, {}
	for p, n in pairs(ehCombatCatches()) do catches[p] = n end
	for p, t in pairs(ehCombatStats()) do stats[p] = {t.downs, t.kills, t.revives, math.floor(t.dmg + 0.5)} end
	local monsters, mspawns = {}, {}
	for i, m in ipairs(G.monsters) do monsters[i] = m end
	for i, v in ipairs(G.mspawns or {}) do mspawns[i] = v end
	shared.eh = {phase = G.phase, t = G.t, monsters = monsters, monster = monsters[1] or 0, winner = G.winner,
		roundTime = G.roundTime, out = out, late = late, catches = catches, stats = stats, mspawns = mspawns, tally = {h = GetInt("echohunt.tally.h"), m = GetInt("echohunt.tally.m")}}
end

function server.init()
	spawnsHumans = utilLoadLevelPlayerSpawns(1)
	spawnsMonster = utilLoadLevelPlayerSpawns(2)
	if #spawnsHumans == 0 then spawnsHumans = utilLoadLevelPlayerSpawns() end   -- (the map's own player spawns)
	if #spawnsHumans == 0 then spawnsHumans = utilGenerateSpawnPoints(32) end
	if #spawnsMonster == 0 then spawnsMonster = utilGenerateSpawnPoints(16, spawnsHumans) end
	hudInit(true)
	teamsInit(2)
	teamsSetNames({"Humans", "Clickers"})
	teamsSetColors({{0.35, 0.65, 1.0}, {0.85, 0.15, 0.12}})
	spawnInit()
	spawnSetRespawnTime(99999)                                   -- (nobody comes back during a round)
	spawnSetDefaultLoadout(HUMAN_LOADOUT)
	ehServerInit()
	publish(true)
end

-- the host's Start (hudDrawGameSetup)
function server.start(settings)
	G.roundTime = tonumber(settings.roundTime) or 300
	G.headStart = tonumber(settings.headStart) or 30
	G.weather = settings.weather or "night"
	G.globalChat = settings.globalChat ~= "off"
	teamsStart(false)
end

local function shuffled(list)
	local l = {}
	for i = 1, #list do l[i] = list[i] end
	for i = #l, 2, -1 do local j = math.random(1, i); l[i], l[j] = l[j], l[i] end
	return l
end

-- A spawn point with room for a player of the given height: no vehicle or loose object within ~1 m up to that height
-- (AgeOfAlgorithms: players spawned inside cars, stuck; the monster floated up through trees), not inside a wall. Otherwise the
-- nearest clear spot on the ground around it (rings of 1.5-7.5 m), else the point as it was.
local function spawnClear(pos, height)
	for _, b in ipairs(QueryAabbBodies(VecAdd(pos, Vec(-1.1, 0.15, -1.1)), VecAdd(pos, Vec(1.1, height, 1.1))) or {}) do
		if GetBodyVehicle(b) ~= 0 or IsBodyDynamic(b) then return false end
	end
	for _, sh in ipairs(QueryAabbShapes(VecAdd(pos, Vec(-0.35, 0.3, -0.35)), VecAdd(pos, Vec(0.35, height, 0.35))) or {}) do
		local b = GetShapeBody(sh)
		if b ~= 0 and not IsBodyDynamic(b) then return false end   -- (a wall, a tree, a roof in the way)
	end
	return true
end

local function clearSpawn(t, height)
	if not t then return t end
	if spawnClear(t.pos, height) then return t end
	for r = 1.5, 7.5, 1.5 do
		for k = 0, 7 do
			local a = k / 8 * 2 * math.pi + r
			local top = VecAdd(t.pos, Vec(math.cos(a) * r, height + 1, math.sin(a) * r))
			local hit, d = QueryRaycast(top, Vec(0, -1, 0), height + 4)
			if hit then
				local ground = VecAdd(top, Vec(0, -d + 0.05, 0))
				if spawnClear(ground, height) then return Transform(ground, t.rot) end
			end
		end
	end
	return t
end

-- n spawns for the monsters, at random among all the spawn points (AgeOfAlgorithms: anywhere - the humans get a head start), not
-- one a human starts on; a spawn is reused (a few metres aside) when there are fewer than monsters
local function monsterSpawns(used, n)
	local taken, all = {}, {}
	for _, t in ipairs(used) do taken[t] = true end
	for _, list in ipairs({spawnsMonster, spawnsHumans}) do
		for _, t in ipairs(list) do if not taken[t] then all[#all + 1] = t end end
	end
	if #all == 0 then for _, t in ipairs(used) do all[#all + 1] = t end end
	all = shuffled(all)
	local out = {}
	for i = 1, n do
		if all[i] then
			out[i] = all[i]
		elseif all[1] then                                         -- (beside the first)
			local a = i * 2.1
			out[i] = Transform(VecAdd(all[1].pos, Vec(math.cos(a) * 3, 0, math.sin(a) * 3)), all[1].rot)
		end
	end
	return out
end

local function isMonster(p)
	for _, m in ipairs(G.monsters) do if m == p then return true end end
	return false
end

-- the teams are set: the monsters (a random one if nobody chose it; one player always stays human), everyone placed,
-- the head start begins
local function beginRound()
	-- (Lua's random is never seeded: every launch drew the same "random" spawns - AgeOfAlgorithms kept starting at the same places
	--  on Cullington. Seeded from the moment Start was pressed and a count of the rounds ever begun)
	SetInt("savegame.mod.eh.rounds", GetInt("savegame.mod.eh.rounds") + 1)
	math.randomseed(math.floor(GetTime() * 1000) % 1000000 + GetInt("savegame.mod.eh.rounds") * 7919)
	for i = 1, 5 do math.random() end
	local humans, monsters = {}, {}
	for p in Players() do
		if teamsGetTeamId(p) == TEAM_MONSTER then monsters[#monsters + 1] = p else humans[#humans + 1] = p end
	end
	if #monsters == 0 and #humans > 0 then
		local k = math.random(1, #humans)
		monsters[1] = table.remove(humans, k)
	end
	while #monsters > MAX_MONSTERS or (#humans == 0 and #monsters > 1) do humans[#humans + 1] = table.remove(monsters) end
	teamsSetTeams({humans, monsters})
	G.monsters = monsters
	G.humans = #humans
	if G.weather ~= "map" then applyWeather(G.weather) end
	local used = {}
	local order = shuffled(spawnsHumans)                       -- (different spawns every game: AgeOfAlgorithms)
	for i, p in ipairs(humans) do
		local t = #order > 0 and order[(i - 1) % #order + 1] or nil
		used[#used + 1] = t
		spawnSpawnPlayer(clearSpawn(t, 1.9), HUMAN_LOADOUT, p)
	end
	G.mspawns = {}
	local ts = monsterSpawns(used, #monsters)
	for i, m in ipairs(monsters) do
		local t = clearSpawn(ts[i] or spawnsMonster[1], 3.8)    -- (its 3.6 m body)
		spawnSpawnPlayer(t, MONSTER_LOADOUT, m)
		if t then G.mspawns[#G.mspawns + 1] = VecCopy(t.pos) end     -- (the humans see where they wake, in the head start)
	end
	for p in pairs(G.out) do G.out[p] = nil end
	G.roster, G.late = {}, {}                                      -- (who plays this round; anyone else joined late)
	for p in Players() do G.roster[p] = true end
	G.winner = ""
	ehCombatReset()
	G.phase, G.t = "hide", G.headStart
	publish(true)
end

local function endRound(winner)
	G.phase, G.winner, G.t = "over", winner, 0
	local k = winner == "humans" and "echohunt.tally.h" or "echohunt.tally.m"   -- (the session's: survives Play Again)
	SetInt(k, GetInt(k) + 1)
	publish(true)
end

-- Proximity Comms (if the host runs it): everyone hears everyone in the lobby and the results; the caught and the
-- late joiners talk only to each other (and hear everyone) during the round: its dead channel
-- (proxchat.channel.<p> = "dead", set every tick)
-- (also: pings only to the pinger's team - proxchat.team.<p>; how far one reaches is the pinger's talk mode, the chat's
-- own since its API 15 (Whisper / Speak / Yell distances); Global chat off for the round when the host chose so -
-- proxchat.noglobal, the dead's channel unaffected: the chat's API)
local function chatKeys()
	local open = G.phase == "lobby" or G.phase == "over"
	SetBool("proxchat.lobby", open)
	SetBool("proxchat.noglobal", not open and G.globalChat == false)
	for p in Players() do
		SetString("proxchat.channel." .. p, (not open and (G.out[p] or G.late[p])) and "dead" or "")
		local clicker = open and teamsGetTeamId(p) == TEAM_MONSTER or (not open and isMonster(p))
		SetString("proxchat.team." .. p, clicker and "clickers" or "humans")
	end
end

-- a player arriving in the lobby joins the humans at once (AgeOfAlgorithms: unassigned players weren't listed - he couldn't see
-- who was in the lobby); once only, so whoever picks the clickers or leaves a team stays that way
local autoJoined = {}
local function lobbyAutoJoin()
	if teamsIsSetup() then return end
	for p in Players() do
		if not autoJoined[p] then
			autoJoined[p] = true
			if teamsGetTeamId(p) == 0 then server._teamsJoinTeam(p, TEAM_HUMANS) end
		end
	end
end

function server.tick(dt)
	SetFloat("echohunt.probe.globals", GetTime())               -- (on the Echo Hunt test level its TEST copy steps aside)
	lobbyAutoJoin()
	if teamsTick(dt) then beginRound() end
	chatKeys()
	if not teamsIsSetup() then
		for p in Players() do DisablePlayer(p) end
		ehServerTick(dt, {}, false)
		return
	end
	if G.phase == "hide" or G.phase == "hunt" then              -- joined mid-round: a spectator until the next round
		for p in Players() do                                    -- (AgeOfAlgorithms; not in the round's roster - PlayersAdded also
			if not G.roster[p] then                              -- reported players who joined in the lobby)
				if not G.late[p] then
					G.late[p] = true
					SetPlayerHealth(0, p)                            -- (dead: mplib's spectating takes over on their machine)
					publish(true)
				end
				DisablePlayer(p)                                     -- (no body, no physics, no interaction)
			end
		end
	end
	if G.phase == "hide" then
		G.t = G.t - dt
		for _, m in ipairs(G.monsters) do if IsPlayerValid(m) then DisablePlayerInput(m) end end   -- (frozen and blind while they hide)
		if G.t <= 0 then G.phase, G.t, G.huntT0 = "hunt", G.roundTime, GetTime(); publish(true) end
		ehServerTick(dt, G.monsters, false)
	elseif G.phase == "hunt" then
		G.t = G.t - dt
		ehServerTick(dt, G.monsters, true)
		local left, any, mons = 0, false, 0
		for _, m in ipairs(G.monsters) do if IsPlayerValid(m) then mons = mons + 1 end end
		for p in Players() do
			if not isMonster(p) and not G.late[p] then
				any = true
				if GetPlayerHealth(p) <= 0 and not ehIsDown(p) then   -- (downed by a human: respawned this frame - not out)
					if not G.out[p] then G.out[p] = GetTime() - G.huntT0; publish(true) end
				elseif not G.out[p] and not ehIsDown(p) then    -- (the downed don't count: nobody left to help them up
					left = left + 1                              --  - every human down, the monsters win)
				end
			end
		end
		if mons == 0 then endRound("humans")                     -- (every monster left the game)
		elseif any and left == 0 then endRound("monster")
		elseif G.t <= 0 then endRound("humans") end
	else
		ehServerTick(dt, {}, false)
		for p in Players() do DisablePlayerInput(p) end
	end
	publish(false)
end

function server.update(dt)
	if teamsIsSetup() then ehServerUpdate(dt) end
end

----- client -----

local C = {caughtN = nil, caughtT = -100, caughtName = ""}

function client.init()
	ehClientInit()
end

function client.destroy()
	SetBool("level.hidenameplates", false)
	ehClientDestroy()
end

-- the round's monsters (shared.eh.monsters) as a plain list; is p one of them
local function monstersOf(e)
	local l = {}
	if e and type(e.monsters) == "table" then for i = 1, #e.monsters do l[i] = e.monsters[i] end end
	return l
end

local function isMonsterOf(e, p)
	if not e or type(e.monsters) ~= "table" then return false end
	for i = 1, #e.monsters do if e.monsters[i] == p then return true end end
	return false
end

local function huntingMonsters()
	local e = shared.eh
	if e and (e.phase == "hide" or e.phase == "hunt") then return monstersOf(e) end
	return {}
end

-- the caught watch the ones still in it (and the monsters)
local function spectateList(e)
	local list = {}
	for p in Players() do
		if isMonsterOf(e, p) or (GetPlayerHealth(p) > 0 and not (e.out and e.out[p]) and not (e.late and e.late[p])) then list[#list + 1] = p end
	end
	return list
end

function client.tick(dt)
	SetFloat("echohunt.probe.globalc", GetTime())               -- (on the Echo Hunt test level its TEST copy steps aside)
	hudTick(dt)
	teamsSetTags()
	local e = shared.eh
	local round = e and (e.phase == "hide" or e.phase == "hunt") or false
	if GetBool("level.hidenameplates") ~= round then SetBool("level.hidenameplates", round) end   -- (ours: drawNames)
	if e and (e.phase == "hunt" or (e.phase == "hide" and e.late and e.late[GetLocalPlayer()])) then spectateTick(spectateList(e)) end
	if e and e.phase == "hide" and type(e.mspawns) == "table" and not isMonsterOf(e, GetLocalPlayer()) then
		for i = 1, #e.mspawns do                                     -- where the monsters wake: red beams
			local sp = e.mspawns[i]
			local base = Vec(sp[1], sp[2], sp[3])
			for k = 0, 2 do
				local o = Vec((k - 1) * 0.15, 0, 0)
				DrawLine(VecAdd(base, o), VecAdd(base, VecAdd(o, Vec(0, 60, 0))), 1, 0.12, 0.08, 0.9)
			end
		end
	end
	if e and e.phase == "hide" and isMonsterOf(e, GetLocalPlayer()) then SetBool("game.disablemap", true) end   -- (no
	ehClientTick(dt, huntingMonsters())                                                     -- scouting while they hide)
	local c = shared.ehCaught                                    -- ("<name> was caught", for everyone)
	if c and c.n ~= C.caughtN then
		if C.caughtN ~= nil then C.caughtT, C.caughtName = GetTime(), GetPlayerName(c.p) end
		C.caughtN = c.n
	end
end

local function clock(t)
	t = math.max(0, math.ceil(t))
	return string.format("%d:%02d", math.floor(t / 60), t % 60)
end

local function bigText(y, size, text, r, g, b, a)
	UiPush()
	UiTranslate(UiCenter(), y)
	UiAlign("center middle")
	UiFont("bold.ttf", size)
	UiColor(r, g, b, a or 1)
	UiText(text)
	UiPop()
end

-- the head start: where the monsters wake, on the humans' screens (a marker with its distance; at the screen's edge
-- when it is off screen or behind)
function drawMonsterSpawn(sp, me)
	local pos = Vec(sp[1], sp[2] + 2.5, sp[3])
	local d = VecLength(VecSub(pos, GetPlayerTransform(me).pos))
	local x, y, dist = UiWorldToPixel(pos)
	local w, h, m = UiWidth(), UiHeight(), 60
	local off = dist < 0 or x < m or x > w - m or y < m or y > h - m
	if off then                                                     -- (pushed to the edge, on its side of the view)
		local cx, cy = w / 2, h / 2
		local dx, dy = x - cx, y - cy
		if dist < 0 then dx, dy = -dx, -dy end
		if math.abs(dx) < 1 and math.abs(dy) < 1 then dy = 1 end
		local k = math.min((w / 2 - m) / math.max(math.abs(dx), 1e-3), (h / 2 - m) / math.max(math.abs(dy), 1e-3))
		x, y = cx + dx * k, cy + dy * k
	end
	UiPush()
	UiTranslate(x, y)
	UiAlign("center middle")
	UiColor(1, 0.15, 0.1, 0.9)
	UiRotate(45)
	UiRect(18, 18)
	UiRotate(-45)
	UiColor(0, 0, 0, 0.9)
	UiRect(8, 8)
	UiTranslate(0, -26)
	UiFont("bold.ttf", 20)
	UiColor(1, 0.25, 0.2, 1)
	UiText("CLICKER")
	UiTranslate(0, 52)
	UiFont("bold.ttf", 16)
	UiColor(1, 1, 1, 0.85)
	UiText(string.format("%d m", math.floor(d + 0.5)))
	UiPop()
end

-- joined mid-round: watching until the next round, talking with the caught
function drawLate()
	bigText(110, 28, "JOINED MID-ROUND - you are watching", 0.85, 0.85, 0.9, 0.9)
	bigText(145, 18, "You play from the next round. You can talk with the caught.", 0.75, 0.75, 0.75, 0.85)
	spectateDraw()
end

-- the head start: the monster sees nothing; the humans are told to hide
-- names over players (AgeOfAlgorithms): humans see the humans (through walls) and the clickers in plain sight; clickers see the
-- clickers (through walls) and a human only while echolocation reveals them. The engine's own nameplates are off for
-- the round on every machine (level.hidenameplates, client.tick) - they showed anyone to anyone.
local function nameMarker(p, losRequired, color)
	local up = GetPlayerUp(p)
	return {pos = VecAdd(GetPlayerTransform(p).pos, up), offset = VecScale(up, 1.2), color = color, label = GetPlayerName(p),
		lineOfSightRequired = losRequired, maxRange = 9999.0, icon = "ui/hud/team-direction.png", drawIconInView = false, player = p}
end

local function drawNames(e, me)
	local mine = isMonsterOf(e, me)
	local revealed = mine and ehRevealedPlayers() or {}
	local hc, mc = teamsGetColor(TEAM_HUMANS), teamsGetColor(TEAM_MONSTER)
	local humanCol, clickerCol = {hc[1], hc[2], hc[3], 1}, {mc[1], mc[2], mc[3], 1}
	local markers = {}
	for p in Players() do
		if p ~= me and IsPlayerValid(p) and GetPlayerHealth(p) > 0 and not IsPlayerDisabled(p)
			and not (e.late and e.late[p]) and not (e.out and e.out[p]) then
			local clicker = isMonsterOf(e, p)
			if clicker and mine then markers[#markers + 1] = nameMarker(p, false, clickerCol)        -- a fellow clicker
			elseif clicker then markers[#markers + 1] = nameMarker(p, true, clickerCol)              -- seen by a human
			elseif not mine then markers[#markers + 1] = nameMarker(p, false, humanCol)              -- a fellow human
			elseif revealed[p] then markers[#markers + 1] = nameMarker(p, false, humanCol) end      -- echolocated
		end
	end
	hudDrawWorldMarkers(markers)
end

local function drawHide(e, me)
	local n = #monstersOf(e)
	if e.late and e.late[me] then drawLate(); return end
	if not isMonsterOf(e, me) then drawNames(e, me) end
	if isMonsterOf(e, me) then
		UiPush(); UiColor(0, 0, 0, 1); UiRect(UiWidth(), UiHeight()); UiPop()
		bigText(UiMiddle() - 40, 44, "THE HUMANS ARE HIDING", 0.85, 0.2, 0.15)
		bigText(UiMiddle() + 20, 30, "You wake in " .. clock(e.t), 0.9, 0.9, 0.9)
		bigText(UiMiddle() + 70, 20, "You are blind. Listen. LMB: strike / tear   F: echolocation   RMB: grab   Shift: run", 0.7, 0.7, 0.7)
	else
		bigText(120, 40, "HIDE", 1, 1, 1)
		bigText(165, 24, (n > 1 and ("The " .. n .. " clickers wake in ") or "The clicker wakes in ") .. clock(e.t) ..
			(n > 1 and " - they hunt by sound" or " - it hunts by sound"), 0.9, 0.9, 0.9)
		bigText(200, 18, "Crouch-walk to move silently. Shoot " .. (n > 1 and "them" or "it") .. " to stun " .. (n > 1 and "them." or "it.") ..
			" A hit takes half your health; downed, a teammate can help you up (hold E).", 0.75, 0.75, 0.75)
		if type(e.mspawns) == "table" then
			for i = 1, #e.mspawns do drawMonsterSpawn(e.mspawns[i], me) end
		end
	end
end

local function humansLeft(e)
	local left = 0
	for p in Players() do
		if not isMonsterOf(e, p) and GetPlayerHealth(p) > 0 and not (e.out and e.out[p]) and not (e.late and e.late[p]) and not ehIsDown(p) then left = left + 1 end
	end
	return left
end

local function scoreGroups(e, results)
	local groups = {
		{name = "Humans", color = teamsGetColor(TEAM_HUMANS), rows = {}},
		{name = #monstersOf(e) > 1 and "Clickers" or "Clicker", color = teamsGetColor(TEAM_MONSTER), rows = {}},
	}
	for p in Players() do
		local st = (e.stats or {})[p] or {0, 0, 0, 0}             -- (downs, kills, revives, damage dealt - AgeOfAlgorithms)
		local nums = {tostring(st[1]), tostring(st[2]), tostring(st[3]), tostring(st[4])}
		if isMonsterOf(e, p) then
			groups[2].rows[#groups[2].rows + 1] = {player = p, columns = {"-", nums[1], nums[2], nums[3], nums[4]}}
		else
			local o = e.out and e.out[p]
			local status = (e.late and e.late[p]) and "joined late" or o and ("caught at " .. clock(o))
				or (not results and ehIsDown(p) and "downed") or (results and "survived" or "hiding")
			groups[1].rows[#groups[1].rows + 1] = {player = p, columns = {status, nums[1], nums[2], nums[3], nums[4]}}
		end
	end
	return groups
end

local SCORE_COLUMNS = {{name = "Status", align = "center"}, {name = "Downs", align = "center"}, {name = "Kills", align = "center"},
	{name = "Revives", align = "center"}, {name = "Damage", align = "center"}}

local function drawHunt(e, me)
	hudDrawTimer(e.t, 1.0)
	drawNames(e, me)
	local left = humansLeft(e)
	bigText(92, 18, left .. (left == 1 and " human left" or " humans left"), 0.85, 0.85, 0.85, 0.8)   -- (under the timer: at the
	                                                                                                -- bottom it sat on the ammo)
	if isMonsterOf(e, me) then
		local cd = ehPulseCooldown()
		bigText(UiHeight() - 100, 20, cd > 0 and ("echolocation: " .. math.ceil(cd) .. " s") or "echolocation ready (F)", 0.55, 1, 0.95, 0.85)
		local still = ehHeartStill()                                 -- (AgeOfAlgorithms: tell them to wait for the heartbeats; once
		if still >= HEART_STILL then                                 --  on, an obvious message, beating like a heart)
			local beat = 0.6 + 0.4 * math.abs(math.sin(GetTime() * 3.2))
			bigText(UiHeight() * 0.7, 34, "SENSING HEARTBEATS...", 1, 0.25, 0.22, beat)
		else
			bigText(UiHeight() - 128, 18, still > 0.3 and ("Sensing heartbeats in " .. math.ceil(HEART_STILL - still) .. " s")
				or ("Stay still " .. math.floor(HEART_STILL) .. " s to sense heartbeats"), 1, 0.45, 0.45, 0.65)
		end
	elseif e.late and e.late[me] then
		drawLate()
	elseif e.out and e.out[me] then
		bigText(110, 28, "YOU WERE CAUGHT - spectating", 1, 0.4, 0.35, 0.9)   -- (out of the round, watching the others: "CAUGHT - you are watching" read as being watched - AgeOfAlgorithms)
		spectateDraw()
	end
	local age = GetTime() - C.caughtT
	if age < CAUGHT_SHOW then bigText(150, 24, C.caughtName .. " was caught", 1, 0.55, 0.45, math.min(1, (CAUGHT_SHOW - age) / 0.8)) end
	hudDrawScoreboard(hudIsScoreboardRequested(), "Humans vs Clickers", SCORE_COLUMNS, scoreGroups(e, false))
end

local function drawResults(e)
	local groups = scoreGroups(e, true)
	local win = e.winner == "monster"
	local tally = e.tally or {h = 0, m = 0}
	local banner = win and "THE CLICKERS WIN" or "THE HUMANS SURVIVE"   -- (AgeOfAlgorithms: always plural; "clickers" since the rename)
	local color = win and {0.6, 0.08, 0.06, 0.8} or {0.15, 0.35, 0.6, 0.8}
	if win then groups[1].dim = true else groups[2].dim = true end
	if win then groups[1], groups[2] = groups[2], groups[1] end
	hudDrawResults(banner, color, string.format("Humans vs Clickers   (this session: humans %d, clickers %d)", tally.h or 0, tally.m or 0),
		SCORE_COLUMNS, groups)
end

-- Proximity Comms runs here (its heartbeat this second), and this player is typing in it
local function chatAlive() return GetFloat("proxchat.alive") > GetTime() - 2 end
local function chatTyping() return GetBool("proxchat.typing." .. GetLocalPlayer()) end

-- the lobby and the results take the keys (interactive UI): Enter opens the chat through its API (proxchat.open, read
-- and cleared by the chat every frame); while typing the lobby is greyed out and takes no input (AgeOfAlgorithms)
-- (true on the frame Enter opens it: the lobby's buttons take Enter as menu_accept too - they must not get it)
local function lobbyChatOpening() return chatAlive() and not chatTyping() and InputPressed("return") end

local function chatHint()
	if not chatAlive() or chatTyping() then return end
	UiPush()
	UiTranslate(40, UiHeight() - 40)
	UiAlign("left middle")
	UiFont("bold.ttf", 20)
	UiColor(1, 1, 1, 0.75)
	local key = GetString("proxchat.key.open")
	UiText((key ~= "" and key or "Enter") .. ": chat")
	UiPop()
end

-- while this player types in the chat, the lobby / results are not drawn at all: the game mode draws after the chat
-- mod, so its windows covered the chat box, and mplib's windows (interactive UI) kept the mouse and keys - the chat's
-- text field never got them, not even Enter / Esc: stuck until a force quit (AgeOfAlgorithms). Only a line at the top instead.
local function chattingNote()
	UiPush()
	UiTranslate(UiCenter(), 60)
	UiAlign("center middle")
	UiFont("bold.ttf", 22)
	UiColor(1, 1, 1, 0.8)
	UiText("Chatting - Enter: send, Esc: close")
	UiPop()
end

function client.draw(dt)
	if not teamsIsSetup() then
		local typing = chatAlive() and chatTyping()
		local opening = lobbyChatOpening()
		if typing then chattingNote(); return end                -- (the chat has the screen and the keys)
		UiPush()
		if opening then UiDisableInput() end                     -- (this frame's Enter is the chat's, not a button's)
		teamsDraw(dt)
		if not hudGameIsSetup() then
			if hudDrawGameSetup(SETTINGS) and not opening then
				ServerCall("server.start", {roundTime = GetFloat(ROUND_KEY), headStart = GetFloat(HEAD_KEY),
					weather = GetString("savegame.mod.eh.weather"), globalChat = GetString("savegame.mod.eh.globalchat")})
			end
		end
		UiPop()
		chatHint()
		if opening then SetBool("proxchat.open", true) end
		return
	end
	local e = shared.eh
	if not e then return end
	local me = GetLocalPlayer()
	ehClientDraw()
	if e.phase == "hide" then drawHide(e, me)
	elseif e.phase == "hunt" then drawHunt(e, me)
	elseif e.phase == "over" then                               -- (the results: chat as in the lobby)
		local typing = chatAlive() and chatTyping()
		local opening = lobbyChatOpening()
		if typing then
			chattingNote()
		else
			UiPush()
			if opening then UiDisableInput() end
			drawResults(e)
			UiPop()
			chatHint()
			if opening then SetBool("proxchat.open", true) end
		end
	end
	hudDrawFade(dt)
end

function client.render(dt)
	ehClientRender(dt, huntingMonsters())
	local e = shared.eh
	if e and (e.phase == "hunt" or (e.phase == "hide" and e.late and e.late[GetLocalPlayer()])) then spectateRender(dt) end
end

function client.postUpdate(dt)
	ehClientPostUpdate(dt)
end
