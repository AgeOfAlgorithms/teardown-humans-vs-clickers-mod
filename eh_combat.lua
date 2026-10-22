-- Echo Hunt: the fight - the monster's attack, its HP, hit areas, the stun (server) and what it shows (client).
-- Included (no #version line) next to eh_monster.lua; it shares only GLOBALS with it (an included file's locals are
-- not visible to other files: verified in-game). Interface:
--   server: ehCombatTick(dt, monsters, hunting) every frame (a list of the monster players; eh_monster.lua's
--           ehServerTick calls it); ehCombatReset() (a new round); ehCombatCatches() -> {[player] = catches};
--           ehCombatStats() -> {[player] = {downs, kills, revives, dmg}} this round (the scoreboard; dmg in health points:
--           a human's full health 100, a monster's HP_MAX);
--           ehHitSlow(p) (its speed factor just after a hit)
--   both:   ehIsMonster(p), ehMonsterList() (from shared.ehMonsters, written by eh_monster.lua's ehServerTick)
--   client: ehCanAct() (this machine's monster may scream / attack now); ehCombatDraw(isMonster) (its HP bar, stun)
--   shared: ehHP[p] {hp, max, stun = seconds left or 0}, ehAct[p] {n, kind} (each monster's one-shot actions for its
--           model: swing_l / swing_r / grab / hold / idle), ehHunt (bool), ehCaught {n, p, by}
-- Several monsters (AgeOfAlgorithms): each has its own HP, stun, hit boxes, attack; monsters never grab each other.
-- Monsters can't pick up or carry anything (no interact, no physics grab, no tools).
--
-- LMB (the monster): a human in front within reach (GRAB_RANGE, a GRAB_CONE around its aim, in sight) loses half their
-- health (no grab: AgeOfAlgorithms); at 0 they are downed - crawling, a bar draining over DOWN_TIME s, revived by a human holding E
-- for REVIVE_TIME s, out when it empties. Nobody in reach: a claw swipe tears holes where it aims. A hit makes the human
-- cry out (the monsters see them). Its HP: bullets
-- (the engine's projectilehit on its invisible hit boxes: head / torso / legs), explosions (by distance), a human's
-- sledge swung at it. At 0 it is stunned STUN_MIN-MAX s (frozen, its model collapsed), then
-- back to full; from HP_REGEN_DELAY s after the last damage it heals slowly (AgeOfAlgorithms: 8 s, very slowly).

ATTACK_CD = 0.9            -- s between swings
GRAB_RANGE = 6.1           -- m from the monster's head to a human's chest: its reach (3.6 + 70 %, AgeOfAlgorithms)
GRAB_CONE = 0.72           -- cos of the cone around its aim (~44 degrees)
HIT_DAMAGE = 0.5           -- of a human's health per hit: half (AgeOfAlgorithms; no grab any more)
DOWN_HEALTH = 0.05         -- a downed human's engine health (kept above 0: the engine's death is "out")
DOWN_TIME = 25             -- s for the downed bar to empty (AgeOfAlgorithms)
DOWN_HIT = 0.08            -- of the bar a hit on a downed human takes ("decreases the bar slowly")
DOWN_SPEED = 7.0 / 3       -- m/s: crawling, a third of walking (AgeOfAlgorithms)
REVIVE_TIME = 5            -- s of holding E next to them (AgeOfAlgorithms)
REVIVE_RANGE = 2.2         -- m
REVIVE_HEALTH = 1 / 3      -- their health when helped up (AgeOfAlgorithms)
HUMAN_HEAL_MAX = 0.4       -- a human heals by itself up to this (AgeOfAlgorithms; the engine's own regeneration stays off)...
HUMAN_HEAL_DELAY = 6       -- ... from this many s after they last lost health ...
HUMAN_HEAL_RATE = 0.02     -- ... at this much health per s ("slowly": 10 % -> 40 % in 15 s)
REVIVE_REACH = 20          -- m a revive's soft noise carries (between a whisper, 8, and speaking, 25 - closer to speaking)
HURT_REACH = 40            -- m a human's cry when hit carries (the monsters see who)
VEH_ARMOR = 3              -- strikes a vehicle takes before the monster rips its humans out (AgeOfAlgorithms: a little cover)
VEH_REACH = 8.5            -- m from the monster's head to a vehicle (bigger than a human; + 70 %)
RAM_MIN = 5                -- m/s: a vehicle hitting the monster faster than this hurts it (AgeOfAlgorithms)
RAM_DMG = 6                -- hp per m/s above RAM_MIN (20 m/s: 90), at most RAM_MAX, once a second per vehicle
RAM_MAX = 100
RAM_RANGE = 3.0            -- m from the vehicle's middle to the monster's torso
SWIPE_RANGE = 7.1          -- m a swipe reaches into what it aims at (4.2 + 70 %)
SWIPE_HOLE = {1.5, 1.2, 0.9}    -- m hole radius at the hit: soft / medium / hard materials (AgeOfAlgorithms: steel too, a bit bigger)
SWIPE_HOLE2 = {1.1, 0.9, 0.7}   -- m the second hole, SWIPE_DEEP further in (through thick walls)
SWIPE_DEEP = 0.7
SWIPE_SHOVE = 9                 -- m/s given to a dynamic body it strikes (doors burst open) ...
SWIPE_SHOVE_MASS = 400          -- ... up to this much mass (kg; heavier things get less)
HP_MAX = 100
HP_REGEN_DELAY = 8         -- s after the last damage before it heals (AgeOfAlgorithms)
HP_REGEN = 2               -- hp per s ("very slowly": empty to full in 50 s)
HIT_SLOW_TIME = 0.1        -- s it is slowed after each hit (AgeOfAlgorithms)
HIT_SLOW = 0.3             -- its walking speed meanwhile (x)
STUN_MIN, STUN_MAX = 5, 10 -- s
DMG_HEAD, DMG_TORSO, DMG_LEGS = 20, 12, 8
DMG_SLEDGE = 10             -- a swing (10 to stun it; AgeOfAlgorithms: 2 hits downed it - each click had counted)
CARRY_REACH = GRAB_RANGE   -- m its own grab reaches from its head: as far as its strike (AgeOfAlgorithms: a big creature)
CARRY_MASS = 400           -- kg it can carry (the engine's grab came from the hidden human's eyes: knee height - AgeOfAlgorithms)
CARRY_THROW = 14
CARRY_HOLD = 2.0           -- m at least, a carried thing is held out in front of its big body
SLEDGE_CD = 0.8            -- s: a sledge swing's length - clicks within it are the same swing
DMG_EXPLOSION = 70         -- at the centre of a size-1 explosion, less with distance
HIT_LAYER = 128            -- the hit boxes' collision layer: bullets hit it, players' CollisionMask leaves it out
-- players and the world's rays (mantle, camera, fog, scan, the models' headroom) skip the hit boxes (128) and the
-- monsters' models (MV_LAYER 32). Players collided with layer 32: the monster stood on its own model (placed at its feet
-- every frame) and walked up the air (AgeOfAlgorithms; two-window test: grounded, rising 3.5 m/s, down when the stun collapsed it).
-- The player's CollisionMask set on the server does reach a client's own player (read there: 127 before this fix).
EH_QUERY_MASK = 255 - 128 - 32
PLAYER_MASK = 255 - 128 - 32
EH_HIT_BODIES = {}
function ehQueryMask()
	QueryCollisionMask(EH_QUERY_MASK)
	if #EH_HIT_BODIES > 0 then QueryRejectBodies(EH_HIT_BODIES) end
	if MV_SHAPES and #MV_SHAPES > 0 then QueryRejectShapes(MV_SHAPES) end
end
EH_OUT = {}                -- [player] = caught (the game mode replaces it with its own list; the probe has none)
-- the hit boxes around the monster's feet (m): centre {x, y, z} (z forward) and size in voxels {x, y, z}
HIT_BOXES = {
	{part = "legs", c = {0, 0.95, 0}, size = {6, 18, 5}},
	{part = "torso", c = {0, 2.35, 0}, size = {8, 11, 6}},
	{part = "head", c = {0, 3.3, -0.1}, size = {6, 7, 7}},
}

-- every monster's own state, by player
local CB = {}
local CBG = {down = {}, vehArmor = {}, ramT = {}, catches = {}, stats = {}, boomBy = 0, swingT = {}, clickT = {}, caughtN = 0, maskT = -100, hitShapes = {}, hitBodies = {}, hpKey = nil, actPub = {}}

function ehMonsterList()
	local l, src = {}, shared.ehMonsters
	if type(src) == "table" then for i = 1, #src do if src[i] and src[i] ~= 0 then l[#l + 1] = src[i] end end end
	return l
end

function ehIsMonster(p)
	if not p or p == 0 then return false end
	local src = shared.ehMonsters
	if type(src) ~= "table" then return false end
	for i = 1, #src do if src[i] == p then return true end end
	return false
end

local function newState()
	return {nextAttack = 0, actN = 0, swingL = true, hp = HP_MAX, lastDmg = -100, stunEnd = 0,
		boxes = nil, bodies = {}}
end

local function act(m, kind, hit)
	CBG.actSeq = (CBG.actSeq or 0) + 1                          -- (one counter for all: a monster's state made anew must not
	CBG.actPub[m] = {n = CBG.actSeq, kind = kind, hit = hit}    --  repeat a number a client has seen - its sound was missed)
	local copy = {}                                                 -- (whole tables, as the other shared writes)
	for p, a in pairs(CBG.actPub) do copy[p] = a end
	shared.ehAct = copy
end

local function painEvent(p, kind)                                -- (every machine: its cry - eh_monster.lua plays it)
	CBG.painN = (CBG.painN or 0) + 1
	shared.ehPain = {n = CBG.painN, p = p, kind = kind}
end

function ehCombatCatches() return CBG.catches end
function ehCombatStats() return CBG.stats end

-- the scoreboard's count for player p (0 / nil: nobody's - an unattributed hit)
local function stat(p, k, n)
	if not p or p == 0 then return end
	local t = CBG.stats[p]
	if not t then t = {downs = 0, kills = 0, revives = 0, dmg = 0}; CBG.stats[p] = t end
	t[k] = t[k] + (n or 1)
end

function ehCombatReset()
	for _, st in pairs(CB) do
		st.hp, st.lastDmg, st.stunEnd, st.nextAttack = HP_MAX, -100, 0, 0
	end
	CBG.catches, CBG.stats, CBG.boomBy = {}, {}, 0
	CBG.down, CBG.downKey = {}, nil
	CBG.vehArmor, CBG.ramT = {}, {}
	shared.ehDown = {}
end

----- hit boxes (server): invisible, unbreakable, in their own layer, moved onto each monster every frame -----

local function rebuildHitLists()
	CBG.hitShapes, CBG.hitBodies = {}, {}
	for m, st in pairs(CB) do
		for _, b in ipairs(st.boxes or {}) do
			CBG.hitBodies[#CBG.hitBodies + 1] = b.body
			for _, s in ipairs(b.shapes) do CBG.hitShapes[s] = {m = m, part = b.hb.part} end
		end
	end
	EH_HIT_BODIES = CBG.hitBodies
end

local function boxesSpawn(m)
	local st = CB[m]
	st.boxes, st.bodies = {}, {}
	for _, hb in ipairs(HIT_BOXES) do
		local sx, sy, sz = hb.size[1], hb.size[2], hb.size[3]
		local xml = string.format("<body tags='ehhit ehowner=%d'><voxbox tags='invisible unbreakable ehhit' pos='%.2f %.2f %.2f' size='%d %d %d' color='0 0 0'/></body>",
			m, -sx * 0.05, -sy * 0.05, -sz * 0.05, sx, sy, sz)          -- (ehowner: whose boxes - its own ping passes through them)
		local ents = Spawn(xml, Transform(Vec(0, -300, 0)))
		for _, e in ipairs(ents or {}) do
			if GetEntityType(e) == "body" then
				local shapes = GetBodyShapes(e)
				for _, s in ipairs(shapes) do SetShapeCollisionFilter(s, HIT_LAYER, 0) end   -- (bullets find them by
				-- query; colliding with everything (255), the boxes moved onto the monster each frame flung a dying
				-- human's ragdoll next to it into the air - AgeOfAlgorithms)
				st.boxes[#st.boxes + 1] = {body = e, hb = hb, shapes = shapes}
				st.bodies[#st.bodies + 1] = e
			end
		end
	end
	rebuildHitLists()
end

local function boxesDelete(m)
	local st = CB[m]
	if not st then return end
	for _, b in ipairs(st.bodies) do if IsHandleValid(b) then Delete(b) end end
	st.boxes, st.bodies = nil, {}
	rebuildHitLists()
end

-- rays of a monster's skip every monster's hit boxes and models, and itself
local function rejectOwn(m)
	ehQueryMask()
	QueryRejectPlayer(m)
	if #CBG.hitBodies > 0 then QueryRejectBodies(CBG.hitBodies) end
	if MV_SHAPES and #MV_SHAPES > 0 then QueryRejectShapes(MV_SHAPES) end
end

local function crouchFactor(m)
	if (mantleActive and mantleActive(m)) or GetPlayerCrouch(m) > 0.5 then return 0.6 end
	return 1
end

local function boxesPlace(m)
	local tr = GetPlayerTransform(m)
	local k = crouchFactor(m)
	for _, b in ipairs(CB[m].boxes) do
		local c = b.hb.c
		local local_ = Vec(c[1], c[2] * k, -c[3])               -- (the player's forward is -z)
		SetBodyTransform(b.body, Transform(TransformToParentPoint(tr, local_), tr.rot))
		SetBodyDynamic(b.body, false)                            -- (a hit must never knock it loose: autotest)
	end
end

-- the monster's eyes (a 3.6 m creature: 1.6 m over a human's, less under a ceiling or crouched) and its aim
local function monsterHead(m)
	local eye = GetPlayerEyeTransform(m)
	rejectOwn(m)
	local hit, d = QueryRaycast(eye.pos, Vec(0, 1, 0), 1.9)
	local raise = math.min(hit and math.max(0, d - 0.3) or 1.6, 1.6 * crouchFactor(m))
	local head = VecAdd(eye.pos, Vec(0, raise, 0))
	return head, TransformToParentVec(eye, Vec(0, 0, -1))
end

----- its grab: RMB held picks up what its own eyes look at (doors drag open), LMB throws it -----

-- the engine's grab works from the human body hidden inside it (its eyes ~1.7 m up: the clicker's knees, AgeOfAlgorithms), so
-- it's released every frame and this one runs from monsterHead instead: in tick the press / release / throw, in
-- update (ConstrainPosition belongs there) the holding
local function carryTick(m, st, now)
	if GetPlayerGrabBody(m) ~= 0 then ReleasePlayerGrab(m) end
	local c = st.carry
	if c and (not InputDown("rmb", m) or not IsHandleValid(c.body) or now < st.stunEnd) then st.carry, c = nil, nil end
	if not c and InputPressed("rmb", m) and now >= st.stunEnd then
		local head, aim = monsterHead(m)
		rejectOwn(m)
		local hit, d, _, shape = QueryRaycast(head, aim, CARRY_REACH)
		local b = (hit and shape and shape ~= 0) and GetShapeBody(shape) or 0
		if b and b ~= 0 and IsBodyDynamic(b) and GetBodyMass(b) <= CARRY_MASS then
			local pt = VecAdd(head, VecScale(aim, d))
			st.carry = {body = b, lp = TransformToLocalPoint(GetBodyTransform(b), pt), dist = math.max(CARRY_HOLD, d)}
		end
	end
	c = st.carry
	if c and InputPressed("lmb", m) then                           -- (a throw, not a swipe)
		local head, aim = monsterHead(m)
		local wp = TransformToParentPoint(GetBodyTransform(c.body), c.lp)
		ApplyBodyImpulse(c.body, wp, VecScale(aim, GetBodyMass(c.body) * CARRY_THROW))
		st.carry, st.threwT = nil, now
	end
end

-- (server.update) each monster's carried body held in front of its head
function ehCombatUpdate(dt)
	for m, st in pairs(CB) do
		local c = st.carry
		if c and IsHandleValid(c.body) and IsPlayerValid(m) then
			local head, aim = monsterHead(m)
			local wp = TransformToParentPoint(GetBodyTransform(c.body), c.lp)
			ConstrainPosition(c.body, 0, wp, VecAdd(head, VecScale(aim, c.dist)), 12, 150)
		end
	end
end

----- damage -----

local function damage(m, dmg, why, by)
	local st = CB[m]
	if not st or dmg <= 0 or GetTime() < st.stunEnd then return end
	stat(by, "dmg", math.min(dmg, st.hp))
	st.hp = st.hp - dmg
	if GetTime() - (st.painT or -100) > 0.6 then st.painT = GetTime(); painEvent(m, "monster") end   -- (its cry)
	st.lastDmg = GetTime()
	if st.hp <= 0 then
		st.hp = 0
		st.stunEnd = GetTime() + STUN_MIN + math.random() * (STUN_MAX - STUN_MIN)
		act(m, "idle")
	end
end

-- who fired the shot that hit at point going dir (the events don't say): the human with a gun out, shooting, whose eye
-- lies closest to the line back along the shot
local function shooter(point, dir)
	local best, bd = 0, 2.5
	dir = VecNormalize(dir)
	for q in Players() do
		local tool = GetPlayerTool(q)
		if not CB[q] and GetPlayerHealth(q) > 0 and tool ~= "sledge" and tool ~= "none" and tool ~= "" then
			local v = VecSub(GetPlayerEyeTransform(q).pos, point)    -- (the shot came from behind the hit: -dir)
			local back = VecDot(v, dir)
			local off = VecLength(VecSub(v, VecScale(dir, back)))
			if back < 0 and off < bd then best, bd = q, off end
		end
	end
	return best
end

local BOOM_TOOLS = {bomb = true, pipebomb = true, rocket = true, explosive = true, grenade = true}

-- a human who swung a sledge in the last half second near this point: the hit is the sledge's blow (it registers as
-- projectile hits on the boxes it touches, several per swing), already counted once as DMG_SLEDGE
-- (from the last CLICK, not the last counted swing: blows from clicks inside the cooldown slipped through as bullets)
local function sledgeBlow(point, now)
	for q, t in pairs(CBG.clickT) do
		if now - t < SLEDGE_CD and IsPlayerValid(q) and VecLength(VecSub(GetPlayerTransform(q).pos, point)) < 4.5 then return true end
	end
	return false
end

local function takeHits(ms)
	local now = GetTime()
	local swung = {}                                             -- humans whose sledge swing lands this frame
	for q in Players() do                                        -- (explosions say nobody: the last to use an explosive)
		if not CB[q] and BOOM_TOOLS[GetPlayerTool(q)] and InputPressed("usetool", q) then CBG.boomBy = q end
		-- a sledge swings once per SLEDGE_CD however fast it is clicked (AgeOfAlgorithms: a triple click counted three hits)
		if not CB[q] and GetPlayerTool(q) == "sledge" and InputPressed("usetool", q) then CBG.clickT[q] = now end
		if not CB[q] and GetPlayerTool(q) == "sledge" and InputPressed("usetool", q) and now - (CBG.swingT[q] or -100) >= SLEDGE_CD then
			CBG.swingT[q] = now
			swung[q] = true
		end
	end
	for i = 1, GetEventCount("projectilehit") do
		local shape, point, dir = GetEvent("projectilehit", i)
		local h = CBG.hitShapes[shape]
		if h and not (point and sledgeBlow(point, now)) then
			local by = (point and dir) and shooter(point, dir) or 0
			damage(h.m, h.part == "head" and DMG_HEAD or (h.part == "torso" and DMG_TORSO or DMG_LEGS), "bullet", by)
		end
	end
	for _, m in ipairs(ms) do
		local torso = VecAdd(GetPlayerTransform(m).pos, Vec(0, 2.3 * crouchFactor(m), 0))
		for i = 1, GetEventCount("explosion") do
			local point, strength = GetEvent("explosion", i)
			strength = strength or 1
			local r = 4 * strength
			local d = VecLength(VecSub(point, torso))
			if d < r then damage(m, DMG_EXPLOSION * strength * (1 - d / r), "explosion", CBG.boomBy) end
		end
		local mv = GetPlayerVelocity(m)
		for q in Players() do                                        -- a vehicle driven into it
			local veh = not CB[q] and GetPlayerVehicle(q) or 0
			if veh ~= 0 and GetTime() >= (CBG.ramT[veh] or 0) then
				local vb = GetVehicleBody(veh)
				local vv = GetBodyVelocity(vb)
				local rel = VecLength(VecSub(vv, mv))
				local vp = GetVehicleTransform(veh).pos
				if rel > RAM_MIN and VecLength(VecSub(vp, torso)) <= RAM_RANGE then
					CBG.ramT[veh] = GetTime() + 1
					damage(m, math.min(RAM_MAX, (rel - RAM_MIN) * RAM_DMG), "vehicle", q)
				end
			end
		end
		for q in Players() do                                        -- a human's sledge swung at it
			if swung[q] and GetPlayerHealth(q) > 0 then
				local eye = GetPlayerEyeTransform(q)
				local v = VecSub(torso, eye.pos)
				local d = VecLength(v)
				if d < 3.0 and VecDot(VecScale(v, 1 / math.max(d, 0.01)), TransformToParentVec(eye, Vec(0, 0, -1))) > 0.6 then
					damage(m, DMG_SLEDGE, "sledge", q)
				end
			end
		end
	end
end

----- humans hurting humans (AgeOfAlgorithms: "being killed by humans should also down a human, not outright kill them") -----

-- The engine kills at 0 health and there is no way in between: with DisablePlayerDamage or godMode a hit raises no
-- "playerhurt" at all (verified in-game 2026-10-18), so the hit can't be taken over. What works: the killing blow
-- says who (playerdied: attacker), and RespawnPlayerAtTransform where they fell brings them back at once (health 1,
-- their tools) - then they are put down there. Killed by anything else (falling, drowning, their own bomb): out.
local function friendlyFire(hunting)
	for i = 1, GetEventCount("playerhurt") do                    -- (a human's damage to another human: their score)
		local v, b, a, att = GetEvent("playerhurt", i)
		if hunting and att and att ~= 0 and att ~= v and not CB[att] and not CB[v] and b and a then
			stat(att, "dmg", 100 * math.max(0, b - math.max(a, 0)))
		end
	end
	for i = 1, GetEventCount("playerdied") do
		local q, att, _, _, cause, point, impulse = GetEvent("playerdied", i)
		local byHuman = att and att ~= 0 and att ~= q and IsPlayerValid(att) and not CB[att]
		-- (a tool's kill - cause "loc@TOOL_NAME_GUN" and the like - counts even when the engine names nobody: AgeOfAlgorithms saw
		--  real gunshot kills between humans stay kills while the test's attributed shots downed; who fired: the
		--  human whose eye lies on the line the killing hit came along)
		local byTool = type(cause) == "string" and cause:find("TOOL_NAME", 1, true) ~= nil
		if not byHuman and byTool then
			att = (point and impulse and VecLength(impulse) > 0.001) and shooter(point, impulse) or 0
			if att == q then att = 0 end
		end
		if hunting and q and (byHuman or byTool) and IsPlayerValid(q) and not CB[q] and not (EH_OUT and EH_OUT[q]) then
			local t = GetPlayerTransform(q)
			RespawnPlayerAtTransform(Transform(t.pos, t.rot), q)
			SetPlayerHealth(DOWN_HEALTH, q)
			local d = CBG.down[q]
			if d then                                                -- (already down: like a strike on the downed)
				d.bar = d.bar - DOWN_HIT
				d.by = att
			else
				d = {bar = 1, by = att, rev = 0, helper = nil, tool = GetPlayerTool(q), noiseT = 0}
				CBG.down[q] = d
				stat(att, "downs")
			end
			d.respawnT = GetTime()                                   -- (its health reads 0 until the respawn lands)
			painEvent(q, "human")
			if ehEmitNoise then ehEmitNoise(q, "hurt", VecAdd(t.pos, Vec(0, 1, 0)), HURT_REACH, 1.0, "voice") end
		end
	end
end

----- the attack: a hit takes half a human's health; at 0 they are downed (AgeOfAlgorithms) -----

-- a human in front of monster m within reach (a cone around its aim, in sight), downed ones too
local function hitTarget(m, head, aim)
	local best, bestDot = nil, GRAB_CONE
	for q in Players() do
		if not CB[q] and GetPlayerHealth(q) > 0 and not (EH_OUT and EH_OUT[q]) then
			local low = CBG.down[q] or (ehInWater and ehInWater(q))  -- (downed, or swimming: their body is low - AgeOfAlgorithms:
			local chest = VecAdd(GetPlayerTransform(q).pos, Vec(0, low and 0.5 or 1.2, 0))   --  monsters attack in water)
			local v = VecSub(chest, head)
			local d = VecLength(v)
			if d <= GRAB_RANGE then
				local dot = VecDot(VecScale(v, 1 / math.max(d, 0.01)), aim)
				if dot >= bestDot then
					rejectOwn(m)
					QueryRejectPlayer(q)
					if not QueryRaycast(head, VecScale(v, 1 / math.max(d, 0.01)), math.max(0, d - 0.3)) then best, bestDot = q, dot end
				end
			end
		end
	end
	return best
end

local function hurtHuman(q, m)
	local d = CBG.down[q]
	if d then
		d.bar = d.bar - DOWN_HIT                                    -- (down: the bar goes a little faster)
		d.by = m
	else
		local h0 = GetPlayerHealth(q)
		local h = h0 - HIT_DAMAGE
		stat(m, "dmg", 100 * math.min(HIT_DAMAGE, h0))
		if h <= 0.02 then                                        -- downed: crawling, the bar draining
			CBG.down[q] = {bar = 1, by = m, rev = 0, helper = nil, tool = GetPlayerTool(q), noiseT = 0}
			SetPlayerHealth(DOWN_HEALTH, q)
			stat(m, "downs")
		else
			SetPlayerHealth(h, q)
		end
	end
	painEvent(q, "human")
	if ehEmitNoise then ehEmitNoise(q, "hurt", VecAdd(GetPlayerTransform(q).pos, Vec(0, 1, 0)), HURT_REACH, 1.0, "voice") end
end

-- a vehicle in front of monster m (in reach, in its aim's cone) with a human inside: they have cover until it is torn
-- open (VEH_ARMOR strikes: holes, its health down), then they are ripped out
local function vehicleTarget(m, head, aim)
	for q in Players() do
		local veh = (not CB[q] and GetPlayerHealth(q) > 0) and GetPlayerVehicle(q) or 0
		if veh ~= 0 then
			local vp = VecAdd(GetVehicleTransform(veh).pos, Vec(0, 0.8, 0))
			local v = VecSub(vp, head)
			local d = VecLength(v)
			if d <= VEH_REACH and VecDot(VecScale(v, 1 / math.max(d, 0.01)), aim) >= GRAB_CONE - 0.15 then
				rejectOwn(m)                                       -- (nothing in between: a wall shields them - AgeOfAlgorithms)
				QueryRejectVehicle(veh)
				QueryRejectPlayer(q)
				if not QueryRaycast(head, VecScale(v, 1 / math.max(d, 0.01)), math.max(0, d - 1.2)) then return veh, q, vp end
			end
		end
	end
	return nil
end

local function strikeVehicle(m, veh, q, vp, head)
	local left = (CBG.vehArmor[veh] or VEH_ARMOR) - 1
	CBG.vehArmor[veh] = left
	local dir = VecNormalize(VecSub(vp, head))
	MakeHole(VecSub(vp, VecScale(dir, 0.6)), 1.3, 1.0, 0.7)     -- (tearing into it)
	SetVehicleHealth(veh, math.max(0, GetVehicleHealth(veh) - 1 / VEH_ARMOR))
	painEvent(q, "human")                                       -- (the human inside cries out)
	if ehEmitNoise then ehEmitNoise(q, "hurt", vp, HURT_REACH, 0.8, "voice") end
	if left <= 0 then                                          -- torn open: everyone in it out, exposed
		for p in Players() do if GetPlayerVehicle(p) == veh then SetPlayerVehicle(0, p) end end
	end
end

local function attack(m)
	local st = CB[m]
	local head, aim = monsterHead(m)
	st.swingL = not st.swingL
	local veh, vq, vp = vehicleTarget(m, head, aim)
	if veh and (CBG.vehArmor[veh] or VEH_ARMOR) > 0 then
		act(m, st.swingL and "swing_l" or "swing_r", true)
		strikeVehicle(m, veh, vq, vp, head)
		return
	end
	local q = hitTarget(m, head, aim)
	act(m, st.swingL and "swing_l" or "swing_r", q and true or false)
	if q then hurtHuman(q, m); return end
	rejectOwn(m)
	local hit, d, _, shape = QueryRaycast(head, aim, SWIPE_RANGE)
	if hit then                                                   -- (claws tearing what it hits)
		local pt = VecAdd(head, VecScale(aim, d))
		-- (bigger and deeper, hard metal included - AgeOfAlgorithms: rooms behind steel were out of its reach; heavy metal and
		--  "unbreakable" can't be holed by anything, by the engine's design)
		MakeHole(pt, SWIPE_HOLE[1], SWIPE_HOLE[2], SWIPE_HOLE[3])
		MakeHole(VecAdd(pt, VecScale(aim, SWIPE_DEEP)), SWIPE_HOLE2[1], SWIPE_HOLE2[2], SWIPE_HOLE2[3])
		-- what moves - doors on hinges, hatches, loose metal - is shoved hard along the swipe: a door it can't hole
		-- still bursts open (it can't use doors: no interact)
		local b = (shape and shape ~= 0) and GetShapeBody(shape) or 0
		if b and b ~= 0 and IsHandleValid(b) and IsBodyDynamic(b) then
			ApplyBodyImpulse(b, pt, VecScale(aim, math.min(GetBodyMass(b), SWIPE_SHOVE_MASS) * SWIPE_SHOVE))
		end
	end
end

-- the downed (server, every frame of the hunt): crawling at a third of the walking speed, no tool, the bar draining
-- over DOWN_TIME s; a human holding E (interact) next to them for REVIVE_TIME s helps them up (bandage sounds, a soft
-- noise the monsters hear); the bar empty: out (caught, a catch for the monster that downed them)
-- (server, every frame of the hunt) a human not downed heals slowly to HUMAN_HEAL_MAX, HUMAN_HEAL_DELAY s after they
-- last lost health (from anything: a strike, a shot, a fall)
local heal = {}                                                 -- [player] = {h = last health seen, t = when it last dropped}
local function humanHeal(dt, hunting, now)
	for q in Players() do
		local h = GetPlayerHealth(q)
		local hs = heal[q]
		if not hs then hs = {h = h, t = -100}; heal[q] = hs end
		if h < hs.h - 1e-4 then hs.t = now end
		if hunting and not CB[q] and not CBG.down[q] and h > 0 and h < HUMAN_HEAL_MAX and now - hs.t >= HUMAN_HEAL_DELAY then
			h = math.min(HUMAN_HEAL_MAX, h + HUMAN_HEAL_RATE * dt)
			SetPlayerHealth(h, q)
		end
		hs.h = h
	end
end

local function downedTick(dt, hunting)
	local pub, key = {}, ""
	for q, d in pairs(CBG.down) do
		local respawning = d.respawnT and GetTime() - d.respawnT < 1.0
		if not IsPlayerValid(q) or (GetPlayerHealth(q) <= 0 and not respawning) or not hunting then
			CBG.down[q] = nil                                        -- (killed some other way, left, the round over)
		else
			SetPlayerParam("walkingSpeed", DOWN_SPEED, q)
			if GetPlayerTool(q) ~= "none" then SetPlayerTool("none", q) end
			if GetPlayerHealth(q) > DOWN_HEALTH then SetPlayerHealth(DOWN_HEALTH, q) end   -- (no healing back up alone)
			local qp = GetPlayerTransform(q).pos
			local helper = nil
			for h in Players() do
				if h ~= q and not CB[h] and not CBG.down[h] and GetPlayerHealth(h) > 0 and not (EH_OUT and EH_OUT[h])
					and InputDown("interact", h) and VecLength(VecSub(GetPlayerTransform(h).pos, qp)) <= REVIVE_RANGE then
					helper = h
				end
			end
			if helper and helper == d.helper then d.rev = d.rev + dt / REVIVE_TIME else d.rev = 0 end
			if not helper then d.bar = d.bar - dt / DOWN_TIME end   -- (held while someone helps them up - AgeOfAlgorithms)
			d.helper = helper
			if helper and GetTime() >= d.noiseT then                 -- (reviving makes a little noise: between a
				d.noiseT = GetTime() + 1                             --  whisper and speaking - AgeOfAlgorithms)
				if ehEmitNoise then ehEmitNoise(helper, "revive", VecAdd(qp, Vec(0, 0.5, 0)), REVIVE_REACH, 0.45, "voice") end
			end
			if d.rev >= 1 then                                       -- up again, a third of their health
				CBG.down[q] = nil
				SetPlayerHealth(REVIVE_HEALTH, q)
				stat(helper, "revives")
				if d.tool and d.tool ~= "" and d.tool ~= "none" then SetPlayerTool(d.tool, q) end
			elseif d.bar <= 0 and not d.dieAt then                  -- bled out: out of the crawl first (not published: the
				d.dieAt = GetTime() + 0.4                            -- machines stop posing it), dead in 0.4 s - a ragdoll
			elseif d.dieAt and GetTime() < d.dieAt then              -- started from the crawl (hands and knees in the
				SetPlayerParam("walkingSpeed", 0, q)                 -- ground) was flung into the air (AgeOfAlgorithms)
			elseif d.dieAt then                                      -- dead now: caught
				CBG.down[q] = nil
				SetPlayerHealth(0, q)
				local m = d.by or 0
				CBG.catches[m] = (CBG.catches[m] or 0) + 1
				stat(m, "kills")
				CBG.caughtN = CBG.caughtN + 1
				shared.ehCaught = {n = CBG.caughtN, p = q, by = m}
			else
				pub[q] = {bar = math.floor(d.bar * 100 + 0.5) / 100, rev = math.floor(d.rev * 100 + 0.5) / 100, h = helper or 0}
				key = key .. string.format("%d:%.2f/%.2f/%d ", q, pub[q].bar, pub[q].rev, pub[q].h)
			end
		end
	end
	if key ~= CBG.downKey then
		CBG.downKey = key
		shared.ehDown = pub
	end
end

-- (both) is human p downed now
function ehIsDown(p)
	local t = shared.ehDown
	return type(t) == "table" and t[p] ~= nil
end

----- every frame (server) -----

local function monsterTick(dt, m, hunting, now)
	local st = CB[m]
	SetPlayerParam("godMode", true, m)                            -- (the engine never kills it: its HP is ours)
	-- it grabs and carries with RMB like anyone - doors too (AgeOfAlgorithms); interact stays on (switched off it blocked the grab -
	-- AgeOfAlgorithms tried it), but no tool is ever kept and no vehicle driven
	if GetPlayerParam("disableInteract", m) then SetPlayerParam("disableInteract", false, m) end
	if GetPlayerParam("flashlightAllowed", m) ~= false then SetPlayerParam("flashlightAllowed", false, m) end   -- (F: echolocation)
	carryTick(m, st, GetTime())
	if GetPlayerVehicle(m) ~= 0 then SetPlayerVehicle(0, m) end
	local tool = GetPlayerTool(m)
	if tool ~= "" and tool ~= "none" then
		SetToolEnabled(tool, false, m)
		SetPlayerTool("none", m)
	end
	if not st.boxes then boxesSpawn(m) end
	boxesPlace(m)
	local stunned = now < st.stunEnd
	if stunned then
		DisablePlayerInput(m)
	elseif st.stunEnd > 0 then
		st.stunEnd, st.hp = 0, HP_MAX                            -- (back on its feet, at full strength)
	elseif st.hp < HP_MAX and now - st.lastDmg >= HP_REGEN_DELAY then
		st.hp = math.min(HP_MAX, st.hp + HP_REGEN * dt)
	end
	if hunting and not stunned then
		if InputPressed("lmb", m) and not st.carry and st.threwT ~= now and now >= st.nextAttack   -- (carrying: LMB threw it)
			and (not ehStaminaUse or ehStaminaUse(m, ATTACK_STAMINA)) then
			st.nextAttack = now + ATTACK_CD
			attack(m)
		end
	end
end

function ehCombatTick(dt, ms, hunting)
	local now = GetTime()
	if type(ms) == "number" then ms = (ms ~= 0) and {ms} or {} end
	local live, set = {}, {}
	for _, m in ipairs(ms or {}) do
		if m ~= 0 and IsPlayerValid(m) then live[#live + 1] = m; set[m] = true end
	end
	if shared.ehHunt ~= (hunting and true or false) then shared.ehHunt = hunting and true or false end
	if now - CBG.maskT > 0.25 then                                -- (players pass through the hit boxes and models; a respawn resets it)
		CBG.maskT = now
		for q in Players() do                                     -- (only when it differs: set every 0.25 s on a client's
			if GetPlayerParam("CollisionMask", q) ~= PLAYER_MASK then  -- player it undid its flashlight - AgeOfAlgorithms: F did nothing
				SetPlayerParam("CollisionMask", PLAYER_MASK, q)       -- for a client human, worked for the host's)
			end
			if GetPlayerParam("healthRegeneration", q) ~= false then  -- (no healing back by itself - AgeOfAlgorithms)
				SetPlayerRegenerationState(false, q)
			end
		end
	end
	for m in pairs(CB) do                                        -- monsters that are no more (left, the round ended)
		if not set[m] then
			if IsPlayerValid(m) then SetPlayerParam("godMode", false, m); SetPlayerParam("flashlightAllowed", true, m) end
			boxesDelete(m)
			CB[m] = nil
			CBG.actPub[m] = nil
		end
	end
	for _, m in ipairs(live) do
		if not CB[m] then CB[m] = newState() end
	end
	takeHits(live)
	friendlyFire(hunting)
	for _, m in ipairs(live) do monsterTick(dt, m, hunting, now) end
	downedTick(dt, hunting)
	humanHeal(dt, hunting, now)
	local hp, key = {}, ""
	for _, m in ipairs(live) do
		local st = CB[m]
		local stun = now < st.stunEnd and math.ceil(st.stunEnd - now) or 0
		hp[m] = {hp = math.floor(st.hp + 0.5), max = HP_MAX, stun = stun}
		key = key .. string.format("%d:%d/%d ", m, hp[m].hp, stun)
	end
	if key ~= CBG.hpKey then                                     -- (published when it changes)
		CBG.hpKey = key
		shared.ehHP = hp
	end
end

-- (server) a monster's speed factor: HIT_SLOW just after a hit
function ehHitSlow(m)
	local st = CB[m]
	return (st and GetTime() - st.lastDmg < HIT_SLOW_TIME) and HIT_SLOW or 1
end

----- client -----

local CC = {snd = nil, painN = nil, crawl = {}, bandageT = {}, phase = {}, stunned = {}}

local function ccSounds()
	if CC.snd then return end
	CC.snd = {hurt = LoadSound("MOD/snd/human_hurt0.ogg"), mpain = LoadSound("MOD/snd/monster_pain0.ogg"),
		bandage = LoadSound("MOD/snd/bandage0.ogg"), stun = LoadSound("MOD/snd/monster_stun0.ogg")}
end

-- every frame, every machine: the hit boxes (for rays, every 0.5 s); the cries of the hurt; the downed crawling (the
-- crouch clip through the locomotion override, on all fours in ehCombatClientPostUpdate; their own view low); the
-- bandage sounds of a revive
-- a human who just died (health to 0): for RAGDOLL_CALM s their body's parts can't go faster than RAGDOLL_MAX_V on this
-- machine (each machine runs its own ragdoll) - dying humans were often flung high into the air (AgeOfAlgorithms); they drop where
-- they are
RAGDOLL_CALM, RAGDOLL_MAX_V = 2.5, 6
local alive, diedT = {}, {}
local function calmRagdolls(now)
	for p in Players() do
		local up = GetPlayerHealth(p) > 0
		if alive[p] and not up and not (ehIsMonster and ehIsMonster(p)) then diedT[p] = now end
		alive[p] = up
	end
	for p, t in pairs(diedT) do
		if now - t > RAGDOLL_CALM or not IsPlayerValid(p) then
			diedT[p] = nil
		else
			local anim = GetPlayerAnimator(p)
			for _, bone in ipairs((anim and anim ~= 0) and GetBoneNames(anim) or {}) do
				local b = GetBoneBody(anim, bone)
				if b and b ~= 0 and IsHandleValid(b) and IsBodyDynamic(b) then
					local v = GetBodyVelocity(b)
					local sp = VecLength(v)
					if sp > RAGDOLL_MAX_V then SetBodyVelocity(b, VecScale(v, RAGDOLL_MAX_V / sp)) end
				end
			end
		end
	end
end

local maskC = -100
function ehCombatClientTick()
	local now = GetTime()
	calmRagdolls(now)
	ccSounds()
	if now - maskC >= 0.5 then
		maskC = now
		EH_HIT_BODIES = FindBodies("ehhit", true) or {}
	end
	local hp = type(shared.ehHP) == "table" and shared.ehHP or {}   -- a clicker brought down (stunned): its scream, every
	for m, h in pairs(hp) do                                           -- machine, from its head (AgeOfAlgorithms' pick by ear)
		local st = (h.stun or 0) > 0
		if st and CC.stunned[m] == false and IsPlayerValid(m) then
			PlaySound(CC.snd.stun, VecAdd(GetPlayerTransform(m).pos, Vec(0, 3.0, 0)), 1.5, false, 0.95 + math.random() * 0.1)
		end
		CC.stunned[m] = st
	end
	local pe = shared.ehPain
	if CC.painN == nil then CC.painN = pe and pe.n or 0 end      -- (what happened before this machine looked: not replayed)
	if pe and pe.n ~= CC.painN then
		CC.painN = pe.n
		if IsPlayerValid(pe.p) then
			local at = VecAdd(GetPlayerTransform(pe.p).pos, Vec(0, pe.kind == "monster" and 3.0 or 1.3, 0))
			if pe.kind == "monster" then
				PlaySound(CC.snd.mpain, at, 1.0, false, 0.9 + math.random() * 0.2)
				if ehHearMonsterPain then ehHearMonsterPain(pe.p) end   -- (the other monsters see it, violet)
			else
				PlaySound(CC.snd.hurt, at, 1.0, false, 0.92 + math.random() * 0.16)
			end
		end
	end
	local down = type(shared.ehDown) == "table" and shared.ehDown or {}
	local me = GetLocalPlayer()
	for q in pairs(CC.crawl) do
		if not down[q] then
			CC.crawl[q] = nil
			SetString("game.override.animation." .. q, "")
			SetFloat("game.override.animation." .. q .. ".weight", 0)
		end
	end
	for q, d in pairs(down) do
		if IsPlayerValid(q) then
			CC.crawl[q] = true
			SetString("game.override.animation." .. q, "crouch_idle")
			SetFloat("game.override.animation." .. q .. ".weight", 1)
			if d.h and d.h ~= 0 and d.rev and d.rev > 0 and now >= (CC.bandageT[q] or 0) then   -- (a revive: bandages)
				CC.bandageT[q] = now + 1.1 + math.random() * 0.3
				PlaySound(CC.snd.bandage, VecAdd(GetPlayerTransform(q).pos, Vec(0, 0.4, 0)), 0.7, false, 0.9 + math.random() * 0.2)
			end
		end
	end
	if down[me] then SetPlayerCameraOffsetTransform(Transform(Vec(0, -1.0, 0))) end   -- (on the ground)
end

-- every frame, every machine, after the game's own character animation (client.postUpdate - the only callback where
-- it took: verified in-game 2026-10-18, tick and render did nothing): each downed human on all fours (AgeOfAlgorithms: "the
-- player is in all 4s") - the spine leant forward, hands under the shoulders and knees under the hips on the ground
-- (the game's IK), the limbs swinging in turn while they crawl
function ehCombatClientPostUpdate(dt)
	local down = type(shared.ehDown) == "table" and shared.ehDown or {}
	for q in pairs(down) do
		local anim = IsPlayerValid(q) and GetPlayerHealth(q) > 0 and GetPlayerAnimator(q) or 0
		if anim ~= 0 then
			local pt = GetPlayerTransform(q)
			local fwd = TransformToParentVec(pt, Vec(0, 0, -1))
			fwd[2] = 0
			fwd = VecNormalize(fwd)
			local v = GetPlayerVelocity(q)
			local speed = math.sqrt(v[1] * v[1] + v[3] * v[3])
			CC.phase[q] = (CC.phase[q] or 0) + (dt or 0) * math.min(speed, 3) * 5
			local sw = math.sin(CC.phase[q]) * math.min(speed, 1) * 0.14
			local g = pt.pos[2]
			RotateBone(anim, "stomach", QuatEuler(0, 0, 25))     -- (inside the skeleton's joint limits, 30: past them a ragdoll
			                                                   --  snaps back hard when they die)
			RotateBone(anim, "chest", QuatEuler(0, 0, 30))
			RotateBone(anim, "neck", QuatEuler(0, 0, -45))       -- (the head up, looking ahead: -30/-35 drooped it)
			RotateBone(anim, "head", QuatEuler(0, 0, -45))
			for _, s in ipairs({{"l", 1}, {"r", -1}}) do
				local sh = GetBoneWorldTransform(anim, "shoulder_" .. s[1])
				local hip = GetBoneWorldTransform(anim, "leg_upper_" .. s[1])
				if sh then
					local hand = VecAdd(Vec(sh.pos[1], g + 0.06, sh.pos[3]), VecScale(fwd, 0.12 + sw * s[2]))
					SetAnimatorTransformIK(anim, "shoulder_" .. s[1], "hand_" .. s[1], Transform(hand, pt.rot), 1.0, 0.0, false, true)
				end
				if hip then
					local foot = VecAdd(Vec(hip.pos[1], g + 0.08, hip.pos[3]), VecScale(fwd, -0.55 - sw * s[2]))
					SetAnimatorTransformIK(anim, "leg_upper_" .. s[1], "foot_" .. s[1], Transform(foot, pt.rot), 1.0, 0.0, false, true)
				end
			end
		end
	end
	for q in pairs(CC.phase) do if not down[q] then CC.phase[q] = nil end end
end

local function myHP()
	local t = shared.ehHP
	return type(t) == "table" and t[GetLocalPlayer()] or nil
end

-- this machine's monster may scream / attack: the hunt is on and it isn't stunned
function ehCanAct()
	if shared.ehHunt == false then return false end
	local h = myHP()
	return not (h and h.stun and h.stun > 0)
end

local function bar(x, y, w, k, r, g, b)
	UiPush()
	UiTranslate(x, y)
	UiAlign("left middle")
	UiColor(0, 0, 0, 0.55)
	UiRect(w + 4, 14)
	UiTranslate(2, 0)
	UiColor(r, g, b, 0.9)
	UiRect(w * math.max(0, math.min(1, k)), 8)
	UiPop()
end

-- a human's HUD: their health, or downed - the bar draining and who is helping; next to a downed human, the prompt
local function humanDraw()
	if shared.ehHunt == false then return end
	local me = GetLocalPlayer()
	if GetPlayerHealth(me) <= 0 then return end
	local down = type(shared.ehDown) == "table" and shared.ehDown or {}
	local d = down[me]
	UiPush()
	UiFont("bold.ttf", 18)
	if d then
		UiTranslate(UiCenter(), UiMiddle() + 120)
		UiAlign("center middle")
		UiColor(1, 0.3, 0.25, 0.95)
		UiText(d.rev > 0 and "BEING HELPED UP" or "DOWNED - crawl to cover; a human can help you up (E)")
		bar(-160, 26, 320, d.bar, 0.85, 0.15, 0.12)
		if d.rev > 0 then bar(-160, 46, 320, d.rev, 0.4, 0.9, 0.5) end
	else
		UiTranslate(40, UiHeight() - 80)
		UiAlign("left middle")
		UiColor(1, 1, 1, 0.7)
		UiText("Health")
		local hk = GetPlayerHealth(me)
		bar(0, 20, 200, hk, 0.85 - 0.5 * hk, 0.25 + 0.6 * hk, 0.2)
	end
	UiPop()
	if d then return end
	local mp = GetPlayerTransform(me).pos
	for q, dq in pairs(down) do                                   -- a downed human near: the prompt / the progress
		if q ~= me and IsPlayerValid(q) and VecLength(VecSub(GetPlayerTransform(q).pos, mp)) <= REVIVE_RANGE + 0.3 then
			UiPush()
			UiTranslate(UiCenter(), UiMiddle() + 90)
			UiAlign("center middle")
			UiFont("bold.ttf", 20)
			UiColor(0.6, 1, 0.7, 0.95)
			UiText(dq.h == me and ("Helping " .. GetPlayerName(q) .. " up...") or ("Hold E to help " .. GetPlayerName(q) .. " up"))
			if dq.h == me then bar(-120, 24, 240, dq.rev, 0.4, 0.9, 0.5) end
			UiPop()
			break
		end
	end
end

function ehCombatDraw(isMonster)
	if not isMonster then humanDraw(); return end
	local h = myHP()
	if not h then return end
	UiPush()                                                     -- its HP (top centre)
	UiTranslate(UiCenter(), 46)
	UiAlign("center middle")
	UiColor(0, 0, 0, 0.55)
	UiRect(324, 14)
	UiAlign("left middle")
	UiTranslate(-160, 0)
	local k = math.max(0, math.min(1, h.hp / math.max(1, h.max)))
	UiColor(0.75 + 0.2 * (1 - k), 0.15 + 0.5 * k, 0.12, 0.9)
	UiRect(320 * k, 8)
	UiPop()
	if h.stun and h.stun > 0 then                                -- (only the monster's own screen: humans get no banner)
		UiPush()
		UiTranslate(UiCenter(), UiMiddle())
		UiAlign("center middle")
		UiFont("bold.ttf", 44)
		UiColor(1, 0.3, 0.25, 0.95)
		UiText("STUNNED  " .. h.stun)
		UiPop()
	end
end
