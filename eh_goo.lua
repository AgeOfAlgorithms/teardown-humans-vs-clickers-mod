-- Humans vs Clickers: the goo grenade (AgeOfAlgorithms). Every human starts with GOO_AMMO; LMB throws one (held with the
-- game's bomb poses, eh_decoy.lua's tool animator). It bursts where it first hits something:
--   * on a player (a human or a clicker): a foam cocoon round them - stuck for GOO_TRAP_TIME s, or until they swing
--     their way out (GOO_FREE_SWINGS melee swings: a sledge, a clicker's strike) or others break the foam open;
--   * anywhere else: a grey foam wall (tools/make_goo.py: 3.6 m wide, 3.2 m tall) across the way it flew - a doorway
--     blocked. It is soft plastic: a clicker's swipe, a sledge or bullets break it, and its broken-off pieces vanish
--     GOO_DEBRIS_TIME s after they fall.
-- Goo stays with what it stuck to (AgeOfAlgorithms): on the ground or a building it stays put (static); on something
-- that moves (a car, a crate, a door) the wall becomes part of it; a cocoon goes wherever its player goes (they fall).
-- The throw is silent to the clickers (TOOL_NOISE.eh_goo); the burst is an ordinary sound of the world (a ring where it is).
-- Included by echohunt.lua after eh_decoy.lua; interface:
--   server: ehGooServerInit(), ehGooReset(), ehGooServerTick(active) (after ehDecoyServerTick), ehGooServerUpdate(dt)
--   both:   ehGooTrapped(p) (server: its own state; client: shared.ehGooTrap)
--   server: ehGooStrike(m) - eh_combat.lua: a stuck clicker's strike (it lands in the goo)
--   client: ehGooClientInit(), ehGooClientTick(dt), ehGooDraw()

GOO_TOOL = "eh_goo"
GOO_AMMO = 2               -- grenades each human starts with (AgeOfAlgorithms)
GOO_THROW = 14             -- m/s along the aim ...
GOO_LOFT = 3               -- ... and up (the noisemaker's throw)
GOO_CD = 0.7               -- s between two throws
GOO_ARM = 0.1              -- s after the throw before it can burst (not in the thrower's hand)
GOO_OWN_SAFE = 0.4         -- s its thrower can't be hit by their own grenade
GOO_FUSE = 4               -- s: never hit anything (thrown into the sky, lying in a corner) - it bursts where it is
GOO_HIT_DV = 2.5           -- m/s: a change of its speed (beyond gravity) in one tick this big is a hit
GOO_TRAP_TIME = 5          -- s stuck (AgeOfAlgorithms: "waiting it out for 5 seconds")
GOO_FREE_SWINGS = 4        -- a human's sledge swings to break out (AgeOfAlgorithms) ...
GOO_FREE_STRIKES = 3       -- ... a clicker's strikes (each one that lands: ATTACK_CD apart, eh_combat.lua)
GOO_SWING_CD = SLEDGE_CD   -- s: clicks within a sledge swing's length are the same swing (spamming doesn't count)
GOO_OWN_SETTLE = 0.4       -- s after their own swing their cocoon's voxels are counted again (its holes aren't others')
GOO_FREE_LOSS = 0.3        -- of its cocoon broken away (by others: bullets, a swipe, a sledge from outside): free
GOO_DEBRIS_TIME = 3        -- s a broken-off piece of goo lies there before it vanishes
GOO_DEBRIS_REACH = 6       -- m round a goo wall / cocoon its pieces are looked for
GOO_FOOT = 0.4             -- m: a piece broken off that still reaches this low (its floor) stays standing; higher ones fall
GOO_WALL_SINK = 0.15       -- m the wall's foot sinks into the floor (no gap to crawl through; not on a moving thing:
                           -- it would be stuck in the floor)
GOO_FOAM_DENSITY = 0.2     -- foam is light: a cocoon or a wall on a moving thing barely weighs on what it touches
GOO_WALL_OUT = 0.5         -- m out from a wall it hit (the foam swells in front of it)
GOO_PLAYER_R, GOO_PLAYER_H = 0.55, 1.9      -- a human's body for a direct hit (m: radius, height)
GOO_CLICKER_R, GOO_CLICKER_H = 0.9, 3.6     -- a clicker's: its big model, not its human-sized collision
GOO_WALL_HALF = {1.8, 3.2, 0.5}             -- the wall's box (half width, height, half thickness): players in it are stuck
GOO_GREY = {0.37, 0.84, 0.03}               -- the foam's voxels: plastic, neutral grey between these (tools/make_goo.py FOAM_DARK
                                            -- .. FOAM_LIGHT), r, g, b within the last of each other
GOO_CAN_LAYER = 32         -- the thrown grenade's collision layer: one players leave out (PLAYER_MASK, eh_combat.lua)
GOO_BURST_VOL = 0.6        -- its burst's volume: a world sound a clicker hears within ~36 m (HEAR_PER_VOL x volume)

EH_HELD_THROWABLES[GOO_TOOL] = true         -- (eh_decoy.lua's tool animator holds it)

local GS = {cans = {}, goo = {}, trap = {}, debris = {}, nextThrow = {}, away = {}, swingT = {}, seq = 0, events = {}, scanT = 0, pubKey = nil}

----- server -----

function ehGooServerInit()
	RegisterTool(GOO_TOOL, "Goo grenade", "MOD/prefab/goo.xml", 4)
end

function ehGooReset()
	for _, c in ipairs(GS.cans) do if IsHandleValid(c.body) then Delete(c.body) end end
	for _, g in ipairs(GS.goo) do                                   -- (a wall on a moving thing: only the foam, not the thing)
		if g.attached then if IsHandleValid(g.shape) then Delete(g.shape) end
		elseif IsHandleValid(g.body) then Delete(g.body) end
	end
	for b in pairs(GS.debris) do if IsHandleValid(b) then Delete(b) end end
	GS.cans, GS.goo, GS.trap, GS.debris, GS.nextThrow, GS.away, GS.swingT = {}, {}, {}, {}, {}, {}, {}
	shared.ehGooTrap = {}
	GS.pubKey = ""
end

-- (both) is p stuck in goo now
function ehGooTrapped(p)
	if GS.trap[p] then return true end
	local t = shared.ehGooTrap
	return type(t) == "table" and t[p] ~= nil
end

local function event(kind, pos, big)
	GS.seq = GS.seq + 1
	GS.events[#GS.events + 1] = {seq = GS.seq, k = kind, x = pos[1], y = pos[2], z = pos[3], big = big and true or false}
	while #GS.events > 8 do table.remove(GS.events, 1) end
	local copy = {}                                                -- (whole tables: as eh_monster.lua's noises)
	for i, e in ipairs(GS.events) do copy[i] = e end
	shared.ehGoo = {seq = GS.seq, list = copy}
end

-- static: stays where it is (a wall, a cocoon); Spawn makes every body dynamic unless told (in the game the first wall
-- toppled over, 2026-11-03)
local function spawnBody(xml, t, static)
	local body
	for _, en in ipairs(Spawn(xml, t, static == true) or {}) do if GetEntityType(en) == "body" then body = en end end
	return body
end

local function throw(q)
	local eye = GetPlayerEyeTransform(q)
	local fwd = QuatRotateVec(eye.rot, Vec(0, 0, -1))
	local at = TransformToParentPoint(eye, Vec(0.3, -0.3, -0.5))  -- (from the hand, as the noisemaker)
	local body = spawnBody("<body dynamic='true' tags='ehgoocan unbreakable'><voxbox size='2 2 2' color='0.72 0.74 0.73' material='plastic'/></body>",
		Transform(at, eye.rot))
	if not body then return end
	for _, s in ipairs(GetBodyShapes(body)) do                    -- (it flies through players: in the game it bounced off its
		SetShapeCollisionFilter(s, GOO_CAN_LAYER, 255 - GOO_CAN_LAYER - HIT_LAYER)   --  thrower and burst at their feet; a
	end                                                            --  player it meets is found by playerHit)
	ehThrowHeard(at)                                               -- (eh_decoy.lua: the humans hear the throw, a clicker doesn't)
	local launch = VecAdd(VecScale(fwd, GOO_THROW), Vec(0, GOO_LOFT, 0))
	GS.cans[#GS.cans + 1] = {body = body, p = q, t0 = GetTime(), launch = launch, launchN = DECOY_LAUNCH_TICKS,
		prev = at, v = launch, dir = launch}
end

-- where on player r's body (a vertical capsule: feet up to its height) the segment a-b passes closest; the distance
local function bodyDist(r, a, b)
	local feet = GetPlayerTransform(r).pos
	local big = ehIsMonster(r)
	local h = big and GOO_CLICKER_H or GOO_PLAYER_H
	local best = 1e9
	for i = 0, 4 do
		local p = VecLerp(a, b, i / 4)
		local y = math.max(feet[2], math.min(feet[2] + h, p[2]))
		local d = VecLength(VecSub(p, Vec(feet[1], y, feet[3])))
		if d < best then best = d end
	end
	return best - (big and GOO_CLICKER_R or GOO_PLAYER_R)
end

local function hittable(r)
	return IsPlayerValid(r) and GetPlayerHealth(r) > 0 and not IsPlayerDisabled(r) and not (EH_OUT and EH_OUT[r])
end

-- the player its flight a-b struck (inside their body, give or take `slack` m), or nil
local function playerHit(c, a, b, slack, now)
	local best, bestD = nil, slack
	for r in Players() do
		if hittable(r) and not (r == c.p and now - c.t0 < GOO_OWN_SAFE) and not ehGooTrapped(r) then
			local d = bodyDist(r, a, b)
			if d <= bestD then best, bestD = r, d end
		end
	end
	return best
end

local function cocoonFile(r)
	return ehIsMonster(r) and "MOD/vox/goo_cocoon_big.vox" or "MOD/vox/goo_cocoon.vox", ehIsMonster(r) and 2.4 or 1.6
end

-- player r stuck in a foam cocoon from now
-- the cocoon round player r's feet, moving as they move (server.update: they still fall)
local function holdCocoon(g, r)
	local v = GetPlayerVelocity(r)
	SetBodyTransform(g.body, Transform(VecAdd(GetPlayerTransform(r).pos, Vec(0, 0.02, 0)), g.rot))
	SetBodyVelocity(g.body, Vec(0, v[2], 0))
	SetBodyAngularVelocity(g.body, Vec(0, 0, 0))
	g.pos = GetPlayerTransform(r).pos
end

-- player r stuck in a foam cocoon from now: a light dynamic body held round them, so it falls with them (a static one
-- stayed in the air when its player dropped - AgeOfAlgorithms)
local function trap(r, now)
	local feet = GetPlayerTransform(r).pos
	local file, half = cocoonFile(r)
	local rot = QuatEuler(0, math.random() * 360, 0)
	local body = spawnBody("<body tags='ehgoo'><vox file='" .. file .. "' pos='0 " .. half .. " 0'/></body>",
		Transform(VecAdd(feet, Vec(0, 0.02, 0)), rot))
	local g = {body = body or 0, kind = "cocoon", pos = feet, floor = feet[2], t = now, v0 = nil, p = r, rot = rot}
	if body then
		for _, s in ipairs(GetBodyShapes(body)) do SetShapeDensity(s, GOO_FOAM_DENSITY) end
		holdCocoon(g, r)
	end
	GS.goo[#GS.goo + 1] = g
	GS.trap[r] = {untilT = now + GOO_TRAP_TIME, swings = 0, goo = g, pos = VecCopy(feet), t0 = now}
	SetPlayerVelocity(Vec(0, math.min(0, GetPlayerVelocity(r)[2]), 0), r)
	event("trap", feet, ehIsMonster(r))
end

local function release(r, now)
	local t = GS.trap[r]
	GS.trap[r] = nil
	if not t then return end
	local g = t.goo
	if g and IsHandleValid(g.body) then Delete(g.body) end        -- (it falls apart: the clients show the foam crumbling)
	if g then g.gone = now end
	event("free", t.pos, IsPlayerValid(r) and ehIsMonster(r))
end

-- the wall where the grenade hit at `at` (normal n: the way it bounced) flying along `dir`
local function wall(c, at, n, now)
	local h = Vec(c.dir[1], 0, c.dir[3])
	if VecLength(h) < 0.05 then h = QuatRotateVec(GetPlayerEyeTransform(c.p).rot, Vec(0, 0, -1)); h[2] = 0 end
	h = VecNormalize(h)
	local centre = at
	if n[2] < 0.5 then                                             -- (a wall or a ceiling: the foam swells out in front of it)
		local out = Vec(n[1], 0, n[3])
		if VecLength(out) > 0.05 then centre = VecAdd(at, VecScale(VecNormalize(out), GOO_WALL_OUT)) end
	end
	ehQueryMask()                                                  -- what it stuck to: something that moves takes the wall
	QueryRequire("physical")
	local touched, _, _, ts = QueryClosestPoint(at, 0.6)
	local host = touched and GetShapeBody(ts) or 0
	if host ~= 0 and not IsBodyDynamic(host) then host = 0 end
	local base = VecAdd(centre, Vec(0, -0.2, 0))
	ehQueryMask()
	QueryRequire("physical static")
	local hit, d = QueryRaycast(VecAdd(centre, Vec(0, 0.3, 0)), Vec(0, -1, 0), 5)
	if hit then base = VecAdd(centre, Vec(0, 0.3 - d, 0)) end
	base[2] = base[2] - (host ~= 0 and -0.05 or GOO_WALL_SINK)
	local rot = QuatLookAt(Vec(0, 0, 0), h)
	local wt = Transform(base, rot)
	local body = spawnBody("<body tags='ehgoo'><vox file='MOD/vox/goo_wall.vox' pos='0 1.6 0'/></body>", wt, true)
	if not body then return end
	local g = {body = body, kind = "wall", pos = VecAdd(base, Vec(0, 1.6, 0)), floor = base[2] + GOO_WALL_SINK, t = now}
	GS.goo[#GS.goo + 1] = g
	event("wall", VecAdd(base, Vec(0, 1.2, 0)))
	for r in Players() do                                          -- whoever stood where it swelled: stuck in it
		if hittable(r) and not ehGooTrapped(r) then
			local l = TransformToLocalPoint(wt, VecAdd(GetPlayerTransform(r).pos, Vec(0, 0.9, 0)))
			local big = ehIsMonster(r) and 0.4 or 0.3
			if math.abs(l[1]) < GOO_WALL_HALF[1] + big and l[2] > -1 and l[2] < GOO_WALL_HALF[2] and math.abs(l[3]) < GOO_WALL_HALF[3] + big then
				local shapes = GetBodyShapes(body)                   -- (the wall gives way round them: their cocoon is there)
				if shapes[1] then
					local st = GetShapeWorldTransform(shapes[1])
					local feet = GetPlayerTransform(r).pos
					local a = VecScale(TransformToLocalPoint(st, VecAdd(feet, Vec(0, 0.3, 0))), 10)
					local b = VecScale(TransformToLocalPoint(st, VecAdd(feet, Vec(0, ehIsMonster(r) and 3.4 or 1.7, 0))), 10)
					SetBrush("sphere", 12, 0)
					DrawShapeLine(shapes[1], a[1], a[2], a[3], b[1], b[2], b[3])
				end
				trap(r, now)
			end
		end
	end
	local shape = GetBodyShapes(body)[1]
	if host ~= 0 and shape then                                    -- (stuck to a moving thing: part of it from now)
		SetShapeBody(shape, host, TransformToLocalTransform(GetBodyTransform(host), GetShapeWorldTransform(shape)))
		SetShapeDensity(shape, GOO_FOAM_DENSITY)
		SetBodyActive(host, true)
		Delete(body)
		g.body, g.shape, g.attached = host, shape, true
	end
end

local function burst(c, at, n, now)
	if IsHandleValid(c.body) then Delete(c.body) end
	local r = playerHit(c, c.prev, at, 0.45, now)                 -- (it bounced off someone: they're in it)
	if r then trap(r, now) else wall(c, at, n, now) end
end

local function cansTick(now, dt)
	for i = #GS.cans, 1, -1 do
		local c = GS.cans[i]
		local done = false
		if not IsHandleValid(c.body) then
			done = true
		elseif c.launchN > 0 then                                  -- (thrown: its speed, once it is in the physics)
			c.launchN = c.launchN - 1
			SetBodyActive(c.body, true)
			SetBodyVelocity(c.body, c.launch)
			c.prev = GetBodyTransform(c.body).pos
			c.v = c.launch
		else
			local pos = GetBodyTransform(c.body).pos
			local v = GetBodyVelocity(c.body)
			local dv = VecSub(v, VecAdd(c.v, Vec(0, -10 * dt, 0)))   -- (what gravity doesn't explain: it hit something)
			local armed = now - c.t0 >= GOO_ARM
			local r = armed and playerHit(c, c.prev, pos, 0, now)  -- (flew into someone's body: a clicker's model is
			if r then                                              --  bigger than what it collides with)
				if IsHandleValid(c.body) then Delete(c.body) end
				trap(r, now)
				done = true
			elseif armed and (VecLength(dv) > GOO_HIT_DV or now - c.t0 > GOO_FUSE) then
				local n = VecLength(dv) > 0.01 and VecNormalize(dv) or Vec(0, 1, 0)
				burst(c, pos, n, now)
				done = true
			else
				if VecLength(v) > 1 then c.dir = v end
				c.prev, c.v = pos, v
			end
		end
		if done then table.remove(GS.cans, i) end
	end
end

-- someone stuck: held still (server.update), swings counted, free when the time is up, they've swung their way out,
-- or the foam round them has been broken open
local function trapTick(now)
	for r, t in pairs(GS.trap) do
		local g = t.goo
		if g and IsHandleValid(g.body) and not g.v0 then
			local n = 0
			for _, s in ipairs(GetBodyShapes(g.body)) do n = n + GetShapeVoxelCount(s) end
			if n > 0 then g.v0 = n end                               -- (read a frame after the spawn: 0 in its own)
		end
		if not hittable(r) or now >= t.untilT then
			release(r, now)
		else
			SetPlayerParam("walkingSpeed", 0, r)
			SetPlayerParam("jumpSpeed", 0, r)
			if not ehIsMonster(r) and GetPlayerTool(r) == "sledge" and InputPressed("usetool", r)
				and now - (GS.swingT[r] or -100) >= GOO_SWING_CD then
				GS.swingT[r] = now
				t.swings = t.swings + 1
				t.settleT = now + GOO_OWN_SETTLE
				event("chip", g and g.pos or t.pos, false)
			end
			local left = 0
			if g and IsHandleValid(g.body) then
				for _, s in ipairs(GetBodyShapes(g.body)) do left = left + GetShapeVoxelCount(s) end
			end
			if t.settleT and now >= t.settleT then t.settleT = nil; if left > 0 then g.v0 = left end end   -- (their own holes)
			local broken = not (g and IsHandleValid(g.body)) or (g.v0 and not t.settleT and left < g.v0 * (1 - GOO_FREE_LOSS))
			if t.swings >= (ehIsMonster(r) and GOO_FREE_STRIKES or GOO_FREE_SWINGS) or broken then release(r, now) end
		end
	end
	local pub, key = {}, ""                                         -- (published as it changes: each one's seconds left)
	for r, t in pairs(GS.trap) do
		local left = math.ceil((t.untilT - now) * 10) / 10
		pub[r] = {left = left, sw = t.swings}
		key = key .. string.format("%d:%.1f/%d ", r, left, t.swings)
	end
	if key ~= GS.pubKey then GS.pubKey = key; shared.ehGooTrap = pub end
end

-- one solid voxel's material in shape s (cells sampled through its box), or nil
local function voxelOf(s)
	local x, y, z = GetShapeSize(s)
	for i = 0, 3 do
		for j = 0, 3 do
			for k = 0, 3 do
				local typ, r, g, b, _, entry = GetShapeMaterialAtIndex(s, math.floor(x * (i + 0.5) / 4), math.floor(y * (j + 0.5) / 4), math.floor(z * (k + 0.5) / 4))
				if entry and entry > 0 then return typ, r, g, b end
			end
		end
	end
end

-- (server) is body b made of goo foam - by its voxels, not its palette (a piece the engine splits off may not keep an
-- unused palette slot: a marker colour there found no piece in the game, 2026-11-03)
function ehGooIsFoam(b)
	local lo, hi, d = GOO_GREY[1], GOO_GREY[2], GOO_GREY[3]
	for _, s in ipairs(GetBodyShapes(b)) do
		local typ, r, g, bl = voxelOf(s)
		if typ == "plastic" and g >= lo and g <= hi and math.abs(r - g) < d and math.abs(bl - g) < d then return true end
	end
	return false
end

-- goo broken in two: a static shape keeps its cut-off parts where they were, hanging in the air (in the game a clicker's
-- swipe took half a wall and nothing fell, 2026-11-03). SplitShape makes each connected piece its own shape (tiny residue
-- dropped); pieces still standing on the floor stay, every other one is moved into a falling body of its own (the
-- game's own way, creativemode.lua), which the sweep below clears. (Only a static wall: the engine splits dynamic
-- bodies by itself.)
local function breakApart(g)
	if g.kind ~= "wall" or g.attached or not IsHandleValid(g.body) then return end
	local split = false
	for _, s in ipairs(GetBodyShapes(g.body)) do
		if IsShapeDisconnected(s) or IsStaticShapeDetached(s) then SplitShape(s, true); split = true end
	end
	if not split then return end
	for _, s in ipairs(GetBodyShapes(g.body)) do
		local lo = GetShapeBounds(s)
		if GetShapeVoxelCount(s) > 0 and lo[2] > g.floor + GOO_FOOT then
			local nb = spawnBody("<body/>", GetBodyTransform(g.body))
			if nb then
				SetShapeBody(s, nb)
				SetBodyDynamic(nb, true)
				SetBodyActive(nb, true)
			end
		end
	end
end

-- (4 times a second) loose pieces of goo near every wall and cocoon: gone GOO_DEBRIS_TIME s after they broke off
local function debrisTick(now)
	for b, t in pairs(GS.debris) do
		if not IsHandleValid(b) then GS.debris[b] = nil
		elseif now >= t then Delete(b); GS.debris[b] = nil end
	end
	if now < GS.scanT then return end
	GS.scanT = now + 0.25
	local own = {}
	for i = #GS.goo, 1, -1 do
		local g = GS.goo[i]
		if g.gone and now - g.gone > 20 then table.remove(GS.goo, i)   -- (its pieces have long fallen)
		elseif not g.gone and not IsHandleValid(g.attached and g.shape or g.body) then g.gone = now end
		if IsHandleValid(g.body) then own[g.body] = true; breakApart(g) end
	end
	for _, g in ipairs(GS.goo) do
		local R = GOO_DEBRIS_REACH
		QueryRequire("physical dynamic")
		local bodies = QueryAabbBodies(VecAdd(g.pos, Vec(-R, -R, -R)), VecAdd(g.pos, Vec(R, R, R)))
		for _, b in ipairs(bodies) do
			if not own[b] and not GS.debris[b] and b > g.body and ehGooIsFoam(b) then GS.debris[b] = now + GOO_DEBRIS_TIME end   -- (newer than the goo: broken off it)
		end
	end
end

-- (server, eh_combat.lua) stuck clicker m struck: one strike into the goo
function ehGooStrike(m)
	local t = GS.trap[m]
	if not t then return end
	t.swings = t.swings + 1
	event("chip", t.goo and t.goo.pos or t.pos, true)
end

-- active: the round is on (head start or hunt) - throws only then
function ehGooServerTick(active, dt)
	local now = GetTime()
	dt = dt or GetTimeStep()
	if active then
		for q in Players() do
			if GetPlayerTool(q) == GOO_TOOL and InputPressed("usetool", q) and GetPlayerHealth(q) > 0 and not ehIsMonster(q)
				and GetToolAmmo(GOO_TOOL, q) >= 1 and now >= (GS.nextThrow[q] or 0) then
				GS.nextThrow[q] = now + GOO_CD
				local left = GetToolAmmo(GOO_TOOL, q) - 1
				throw(q)
				if left >= 1 then SetToolAmmo(GOO_TOOL, left, q)
				else GS.nextThrow[q] = math.huge; GS.away[q] = now + DECOY_PUT_AWAY end
			end
		end
	end
	for q, t in pairs(GS.away) do                             -- the last one thrown: used up and put away (its
		if now >= t then                                           -- ammo stays until then: none and the engine might
			GS.away[q] = nil                                       -- switch tools at once, no throw pose - the noisemaker)
			GS.nextThrow[q] = nil
			if IsPlayerValid(q) then
				SetToolAmmo(GOO_TOOL, 0, q)
				SetToolEnabled(GOO_TOOL, false, q)
				if GetPlayerTool(q) == GOO_TOOL then SetPlayerTool("none", q) end
			end
		end
	end
	cansTick(now, dt)
	if active then trapTick(now) else for r in pairs(GS.trap) do release(r, now) end; trapTick(now) end
	debrisTick(now)
end

-- (server.update, 60 Hz) the stuck can't move: no walking, no jumping (they may still fall), their cocoon round them
function ehGooServerUpdate(dt)
	for r, t in pairs(GS.trap) do
		if IsPlayerValid(r) then
			local v = GetPlayerVelocity(r)
			SetPlayerVelocity(Vec(0, math.min(0, v[2]), 0), r)
			if t.goo and IsHandleValid(t.goo.body) then holdCocoon(t.goo, r) end
		end
	end
end

----- client (every machine) -----

local GC = {seen = nil, snd = {}, hiss = nil, hissUntil = 0, hissPos = nil}

function ehGooClientInit()
	for i = 0, 3 do GC.snd[#GC.snd + 1] = LoadSound("water/splash-m" .. i .. ".ogg") end
	GC.small = {}
	for i = 0, 3 do GC.small[#GC.small + 1] = LoadSound("water/splash-s" .. i .. ".ogg") end
	GC.hiss = LoadLoop("tools/extinguisher-loop.ogg")
end

local function foamParticles(pos, n, spread, up, big)
	ParticleReset()
	ParticleType("plain")
	ParticleColor(0.78, 0.79, 0.78, 0.55, 0.57, 0.57)
	ParticleRadius(big and 0.22 or 0.16, 0.05)
	ParticleAlpha(1, 0)
	ParticleGravity(-8)
	ParticleDrag(0.4)
	ParticleCollide(1)
	for _ = 1, n do
		local d = Vec(math.random() * 2 - 1, math.random() * up, math.random() * 2 - 1)
		SpawnParticle(VecAdd(pos, Vec((math.random() * 2 - 1) * spread, math.random() * spread, (math.random() * 2 - 1) * spread)),
			VecScale(d, 2 + math.random() * 3), 0.6 + math.random() * 0.8)
	end
end

function ehGooClientTick(dt)
	local now = GetTime()
	if GC.hissPos and now < GC.hissUntil and GC.hiss then PlayLoop(GC.hiss, GC.hissPos, 0.7, false) end   -- (the foam swelling)
	local q = shared.ehGoo
	if not q or not q.seq then GC.seen = GC.seen or 0; return end
	if not GC.seen or q.seq < GC.seen then GC.seen = q.seq end      -- (joined late, or a new session: from now on)
	for _, e in ipairs(q.list or {}) do
		if e.seq > GC.seen then
			local pos = Vec(e.x, e.y, e.z)
			if e.k == "wall" then                                    -- (registered: a clicker hears it as a sound of the world)
				if #GC.snd > 0 then PlaySound(GC.snd[math.random(#GC.snd)], pos, GOO_BURST_VOL) end
				GC.hissPos, GC.hissUntil = pos, now + 0.6
				foamParticles(pos, 60, 1.2, 1.5, true)
			elseif e.k == "trap" then
				local at = VecAdd(pos, Vec(0, e.big and 2 or 1, 0))
				if #GC.snd > 0 then PlaySound(GC.snd[math.random(#GC.snd)], at, GOO_BURST_VOL) end
				GC.hissPos, GC.hissUntil = at, now + 0.5
				foamParticles(at, 40, e.big and 1.0 or 0.6, 1.2, e.big)
			elseif e.k == "chip" then                                -- (a hit on the cocoon from inside: a puff of foam)
				local at = VecAdd(pos, Vec(0, e.big and 2.2 or 1.2, 0))
				if #GC.small > 0 then PlaySound(GC.small[math.random(#GC.small)], at, 0.35, false) end
				foamParticles(at, 16, e.big and 0.9 or 0.5, 0.8, e.big)
			elseif e.k == "free" then                                -- (the cocoon crumbling)
				local at = VecAdd(pos, Vec(0, e.big and 2 or 1, 0))
				if #GC.small > 0 then PlaySound(GC.small[math.random(#GC.small)], at, 0.5) end
				foamParticles(at, 70, e.big and 1.3 or 0.8, 0.6, e.big)
			end
		end
	end
	GC.seen = q.seq
end

-- (client.draw) stuck: how to get out, and the time left
function ehGooDraw()
	local t = shared.ehGooTrap
	local me = GetLocalPlayer()
	local s = type(t) == "table" and t[me]
	if not s then return end
	UiPush()
	UiTranslate(UiCenter(), UiHeight() * 0.68)
	UiAlign("center middle")
	UiFont(FONT_BOLD, FONT_SIZE_30)
	UiColor(0.85, 0.87, 0.86)
	UiText("STUCK IN GOO")
	UiTranslate(0, 34)
	UiFont(FONT_MEDIUM, FONT_SIZE_22)
	local how = ehIsMonster(me) and "Strike" or "Swing your sledge"
	UiText(how .. " to break out (" .. math.max(0, (ehIsMonster(me) and GOO_FREE_STRIKES or GOO_FREE_SWINGS) - (s.sw or 0)) .. ")")
	UiTranslate(0, 28)
	local w = 260
	UiColor(0, 0, 0, 0.5)
	UiRect(w, 8)
	UiAlign("left middle")
	UiTranslate(-w / 2, 0)
	UiColor(0.8, 0.82, 0.81)
	UiRect(w * math.max(0, math.min(1, (s.left or 0) / GOO_TRAP_TIME)), 8)
	UiPop()
end
