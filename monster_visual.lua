-- Echo Hunt: the Blind Demon drawn for the monster player (client side, every machine). No #version line (included).
-- Needs "script/include/player.lua", "monster_rig.lua" and "monster_anim.lua" included before it. Globals:
--   monsterVisualRender(ms, screams, dt)  from client.render, every frame: ms = a list of the monster players (or one
--                                          player, 0 = none); screams[p] = a counter that changes when p screams
--   monsterVisualClear()                  removes every model (the mode ends)
--   monsterVisualBodies(m)                the bodies of m's model
--   MV_SHAPES                             every model's shapes (for rays that must skip the models)
-- One model per monster (several monsters: they see each other).
-- On every machine the monster player's own character is hidden (SetPlayerHidden) and the 17 parts follow it: placed
-- at its feet, turned with it, posed by MonsterPose from how it moves (idle, the walk / run gait by speed with the
-- phase advanced by distance, crouch, crawl under a low ceiling, mid-air, mantling) and screaming when it pulses.
-- On the monster's own machine the parts stay invisible (its view is first person from inside the head).
-- Pattern from Dread Keep's client rigs (verified in-game): one dynamic body per part, collision filtered off,
-- SetBodyTransform + zero velocities from client.render.

MV_LAYER = 32               -- collision layer of the parts (they collide with nothing)
MV_VOX_SCALE = 0.5          -- the parts are 0.05 m voxels (AgeOfAlgorithms: more detail; tools/make_monster.py VOX)
MV_HEADROOM_MAX = 4.2       -- m probed above the feet for the crawl under low ceilings
MV_SHAPES = {}              -- every monster's parts' shapes

local MVS = {}              -- [monster player] = its model: parts, pose state

local function newModel(m)
	return {m = m, parts = nil, out = {}, anim = {st = "idle", t = 0, phase = 0, speed = 0, look = 0, time = 0, seed = 7},
		st = "idle", stT0 = 0, scream = nil, screamT0 = -100, headroom = MV_HEADROOM_MAX, lastPos = nil, invisible = nil}
end

local function mvRebuildShapes()
	MV_SHAPES = {}
	for _, MV in pairs(MVS) do
		for _, q in ipairs(MV.parts or {}) do
			for _, s in ipairs(q.shapes) do MV_SHAPES[#MV_SHAPES + 1] = s end
		end
	end
end

local function mvSpawnPart(file)
	local ok, ents = pcall(Spawn, string.format("<body dynamic='true' tags='ehmonster'><vox tags='ehmonster' file='%s' scale='%.3f'/></body>",
		file, MV_VOX_SCALE), Transform(Vec(0, -400, 0)))
	if not ok or type(ents) ~= "table" then return nil, {} end
	local body = nil
	for _, h in ipairs(ents) do if GetEntityType(h) == "body" and not body then body = h end end
	if not body then return nil, {} end
	local shapes = GetBodyShapes(body) or {}
	for _, s in ipairs(shapes) do SetShapeCollisionFilter(s, MV_LAYER, 0) end
	return body, shapes
end

-- each part's voxel box centred on its body's origin (the rig places the body at the box centre). Scaled models
-- (< 1) on a scripted rig were placed off by the engine's own rule (voxel-assets: limbs detached); so the box is
-- measured once the engine reports it (a fresh shape can read 0 in its spawn frame) and moved: true when done
local function mvCentre(q)
	if q.centred then return true end
	for _, sh in ipairs(q.shapes) do
		if not IsHandleValid(sh) then return false end
		local x, y, z, vs = GetShapeSize(sh)
		if not x or x <= 0 or not vs or vs <= 0 then return false end
	end
	for _, sh in ipairs(q.shapes) do
		local t = GetShapeLocalTransform(sh)
		local x, y, z, vs = GetShapeSize(sh)
		local c = TransformToParentPoint(t, Vec(x * vs / 2, y * vs / 2, z * vs / 2))
		SetShapeLocalTransform(sh, Transform(VecSub(t.pos, c), t.rot))
	end
	q.centred = true
	return true
end

local function mvSpawn(MV)
	MV.parts = {}
	for _, pt in ipairs(RIG.parts) do
		local body, shapes = mvSpawnPart(pt.file)
		if body then
			MV.parts[#MV.parts + 1] = {name = pt.name, body = body, shapes = shapes,
				rest = Transform(Vec(pt.center[1], pt.center[2], pt.center[3]), Quat())}
		end
	end
	MV.invisible = nil
	mvRebuildShapes()
end

local function mvDelete(MV)
	for _, q in ipairs(MV.parts or {}) do
		if IsHandleValid(q.body) then Delete(q.body) end
	end
	MV.parts = nil
end

function monsterVisualClear()
	for m, MV in pairs(MVS) do mvDelete(MV) end
	MVS = {}
	MV_SHAPES = {}
end

local function mvSetInvisible(MV, inv)
	if MV.invisible == inv then return end
	MV.invisible = inv
	for _, q in ipairs(MV.parts) do
		for _, s in ipairs(q.shapes) do
			if IsHandleValid(s) then if inv then SetTag(s, "invisible") else RemoveTag(s, "invisible") end end
		end
	end
end

-- how much room above the feet (the pose crawls under a low ceiling), eased so a doorway doesn't pop
local function mvHeadroom(MV, m, feet, dt)
	QueryRejectPlayer(m)
	if #MV_SHAPES > 0 then QueryRejectShapes(MV_SHAPES) end
	if ehQueryMask then ehQueryMask() end
	-- (a 0.25 m sphere from 0.6 m up: started at 0.3 m with radius 0.3 it touched the floor - headroom 0.3 m always,
	-- the pose bent toward the crawl: "always crouching", two-window test)
	local hit, d = QueryRaycast(VecAdd(feet, Vec(0, 0.6, 0)), Vec(0, 1, 0), MV_HEADROOM_MAX - 0.6, 0.25)
	local want = hit and (d + 0.6 + 0.25) or MV_HEADROOM_MAX
	if want < MV.headroom then MV.headroom = math.max(want, MV.headroom - dt * 6)
	else MV.headroom = math.min(want, MV.headroom + dt * 3) end
	return MV.headroom
end

-- the fight's one-shots and the stun come from the server (eh_combat.lua: shared.ehAct[m], shared.ehHP[m])
local function mvAction(MV, m, now)
	local hp = type(shared.ehHP) == "table" and shared.ehHP[m] or nil
	if hp and hp.stun and hp.stun > 0 then
		if not MV.stunT0 then MV.stunT0 = now end
		return "dead", now - MV.stunT0
	end
	MV.stunT0 = nil
	local a = type(shared.ehAct) == "table" and shared.ehAct[m] or nil
	if a and a.n ~= MV.actN then
		if MV.actN ~= nil then MV.actKind, MV.actT0 = a.kind, now end   -- (the first value seen is not an action)
		MV.actN = a.n
	elseif not a and MV.actN == nil then
		MV.actN = 0
	end
	local k, t = MV.actKind, now - (MV.actT0 or -100)
	if k == "hold" then return "hold", t end
	if (k == "swing_l" or k == "swing_r") and t < MONSTER_ANIM.swing then return k, t end
	if k == "grab" and t < MONSTER_ANIM.grab then return "grab", t end
	return nil
end

local function mvState(MV, m, speed, now)
	local ak, at = mvAction(MV, m, now)
	if ak then return ak, at end
	if MV.scream and now - MV.screamT0 < MONSTER_ANIM.scream then return "scream", now - MV.screamT0 end
	local st
	if mantleActive and mantleActive(m) then st = "crawl"
	elseif not IsPlayerGrounded(m) then st = "run"
	elseif GetPlayerCrouch(m) > 0.5 then st = "crouch"
	elseif speed > 0.4 then st = "walk"
	else st = "idle" end
	if st ~= MV.st then MV.st, MV.stT0 = st, now end
	return st, now - MV.stT0
end

local function mvRenderOne(MV, m, screamN, dt)
	if not MV.parts then mvSpawn(MV) end
	SetPlayerHidden(m)                                          -- (the human character is never drawn for a monster)
	mvSetInvisible(MV, m == GetLocalPlayer())                    -- (first person: not in its own view; other monsters see it)
	local now = GetTime()
	if screamN and screamN ~= MV.scream then
		if MV.scream ~= nil then MV.screamT0 = now end           -- (the first value seen is not a scream)
		MV.scream = screamN
	end
	local tr = GetPlayerTransform(m)
	local feet = tr.pos
	local v = GetPlayerVelocity(m)
	local speed = math.sqrt(v[1] * v[1] + v[3] * v[3])
	local dist = MV.lastPos and VecLength(Vec(feet[1] - MV.lastPos[1], 0, feet[3] - MV.lastPos[3])) or 0
	MV.lastPos = VecCopy(feet)
	local headroom = mvHeadroom(MV, m, feet, dt)
	local st, t = mvState(MV, m, speed, now)
	local a = MV.anim
	if dist < 2 and IsPlayerGrounded(m) then                    -- (not across a teleport, not in the air)
		local stride = (st == "crawl") and MONSTER_ANIM.crawlStride or MonsterStride(speed, headroom)
		a.phase = (a.phase + dist / math.max(0.3, stride) * 2 * math.pi) % (2 * math.pi)
	end
	a.st, a.t, a.speed, a.time, a.headroom = st, t, speed, now, headroom
	a.look = 0
	local ok = pcall(MonsterPose, a, MV.out)
	if not ok then return end
	local root = Transform(feet, QuatRotateQuat(tr.rot, QuatEuler(0, 180, 0)))   -- (the rig's +z forward = the player's -z)
	local zero = Vec(0, 0, 0)
	for _, q in ipairs(MV.parts) do mvCentre(q) end
	for _, q in ipairs(MV.parts) do
		if IsHandleValid(q.body) then
			SetBodyTransform(q.body, TransformToParentTransform(root, MV.out[q.name] or q.rest))
			SetBodyVelocity(q.body, zero)
			SetBodyAngularVelocity(q.body, zero)
		end
	end
end

-- (diagnostics) a monster's pose state and the headroom its model reads
function monsterVisualDebug(m)
	local MV = MVS[m]
	if not MV then return "-", -1 end
	return MV.anim.st or "-", MV.headroom or -1
end

-- the bodies of a monster's model (its outline when another monster hears it), {} when it has none
function monsterVisualBodies(m)
	local l, MV = {}, MVS[m]
	for _, q in ipairs(MV and MV.parts or {}) do l[#l + 1] = q.body end
	return l
end

-- ms: a list of the monster players (or one player, 0 = none); screams: [player] = its scream counter (or one
-- counter for a single monster)
function monsterVisualRender(ms, screams, dt)
	if type(ms) ~= "table" then ms = (ms and ms ~= 0) and {ms} or {} end
	local live = {}
	for _, m in ipairs(ms) do
		if m ~= 0 and IsPlayerValid(m) then live[m] = true end
	end
	local removed = false
	for m, MV in pairs(MVS) do                                  -- (a monster that is no more: its model goes)
		if not live[m] then mvDelete(MV); MVS[m] = nil; removed = true end
	end
	if removed then mvRebuildShapes() end
	for _, m in ipairs(ms) do
		if live[m] then
			if not MVS[m] then MVS[m] = newModel(m) end
			local sc = nil                                        -- (its own counter; nil before its first scream - the
			if type(screams) == "table" then sc = screams[m]       -- whole table taken for a counter made a new
			elseif type(screams) == "number" then sc = screams end -- "scream" every frame: stuck screaming, low)
			mvRenderOne(MVS[m], m, sc, dt)
		end
	end
end
