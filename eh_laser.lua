-- Humans vs Clickers: how a clicker's laser looks and sounds, on every machine (included by echohunt.lua; the server
-- side - charge, shot, damage, hole - is in eh_combat.lua; the upgrade that unlocks it in eh_upgrade.lua).
-- An anime-style energy beam (the user, 2026-11-15): while it charges, red sparks are sucked into its maw, which
-- glows brighter and brighter (its charge sound rising); on the shot a white-hot core in a wide red glow, swelling
-- then thinning out, sparks spiralling round it, a shockwave ring bursting from the maw, a flash and a burst of sparks
-- where it strikes, the camera shaking nearby; its terrifying fire sound. Clickers who own it have a faint red glow
-- pulsing in the maw.
--   ehLaserClientTick(dt)   every frame (client.tick: sprites are drawn from tick)
-- Reads shared.ehLaser[m] (charging: a number per charge), shared.ehBeam (the last shot), shared.ehUp (who owns it).

LASER_LIFE = 0.9          -- s the beam shows
LASER_WIDTH = 2.0         -- m: the beam's width at its fullest (the glow is wider still)
LASER_SHAKE_R = 30        -- m: cameras this close to the beam shake (harder closer)

local LZ = {charge = {}, beams = {}, beamN = nil, spr = nil, snd = nil}

local function lzAssets()
	if LZ.spr then return end
	LZ.spr = {beam = LoadSprite("gfx/laser.png"), ring = LoadSprite("gfx/ring.png"), flare = LoadSprite("gfx/flare_0.png"),
		glare = LoadSprite("gfx/glare.png")}
	LZ.snd = {charge = LoadSound("MOD/snd/laser_charge0.ogg"), fire = LoadSound("MOD/snd/laser_fire0.ogg"),
		hit = LoadSound("MOD/snd/laser_fire0.ogg")}
end

-- a clicker's maw (approximately: its head 3.3 m up, a little forward of where its player faces)
local function maw(m)
	local t = GetPlayerTransform(m)
	return VecAdd(t.pos, VecAdd(Vec(0, 3.3, 0), VecScale(TransformToParentVec(t, Vec(0, 0, -1)), 0.4)))
end

-- a sprite facing the camera at pos (size m)
local function billboard(spr, pos, size, r, g, b, a)
	local cam = GetCameraTransform().pos
	local z = VecNormalize(VecSub(cam, pos))
	local up = math.abs(z[2]) > 0.95 and Vec(1, 0, 0) or Vec(0, 1, 0)
	local x = VecNormalize(VecCross(up, z))
	DrawSprite(spr, Transform(pos, QuatAlignXZ(x, z)), size, size, r, g, b, a, true, true)
end

-- a strip along a-b, turned to the camera round its own axis
local function strip(spr, a, b, width, r, g, b2, al)
	local cam = GetCameraTransform().pos
	local mid = VecLerp(a, b, 0.5)
	local x = VecSub(b, a)
	local len = VecLength(x)
	if len < 0.01 then return end
	x = VecScale(x, 1 / len)
	local toCam = VecSub(cam, mid)
	local z = VecSub(toCam, VecScale(x, VecDot(toCam, x)))
	if VecLength(z) < 0.001 then z = Vec(0, 1, 0) end
	DrawSprite(spr, Transform(mid, QuatAlignXZ(x, VecNormalize(z))), len, width, r, g, b2, al, true, true)
end

local function sparks(pos, vel, life, r, g, b, rad)
	ParticleReset()
	ParticleType("plain")
	ParticleTile(4)
	ParticleColor(r, g, b, 1, 0.1, 0.05)
	ParticleRadius(rad or 0.08, 0.01)
	ParticleAlpha(1, 0)
	ParticleEmissive(8, 0)
	ParticleGravity(0)
	ParticleDrag(0.5)
	ParticleCollide(0)
	SpawnParticle(pos, vel, life)
end

-- while it charges (0..1 of the charge): energy drawn into the maw, the glow building
local function drawCharge(m, c, now)
	local k = math.min(1, (now - c.t0) / (LASER_CHARGE or 2))
	local at = maw(m)
	local pulse = 0.75 + 0.25 * math.sin(now * (12 + 18 * k))
	local mine = m == GetLocalPlayer()                         -- (its own camera is in its head: no flare in its face)
	PointLight(at, 1, 0.12, 0.08, (1 + 9 * k) * pulse * (mine and 0.35 or 1))
	if not mine then
		billboard(LZ.spr.flare, at, 0.4 + 1.6 * k * pulse, 1, 0.25, 0.2, 0.6 + 0.4 * k)
		billboard(LZ.spr.glare, at, 0.2 + 0.6 * k, 3, 2.4, 2.4, k)
	end
	for i = 1, math.floor(2 + 6 * k) do                       -- sparks sucked in from all round
		local d = VecNormalize(Vec(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5))
		local r = 1.2 + 1.3 * math.random()
		local life = 0.25 + 0.15 * math.random()
		sparks(VecAdd(at, VecScale(d, r)), VecScale(d, -r / life), life, 1, 0.3 + 0.5 * math.random(), 0.25, 0.05 + 0.05 * k)
	end
end

-- the shot, age s old
local function drawBeam(bm, now)
	local age = now - bm.t0
	if age > LASER_LIFE then return false end
	local env = math.min(1, 0.35 + age / 0.06) * (1 - math.max(0, (age - 0.25) / (LASER_LIFE - 0.25)))   -- swell, hold, thin
	env = math.max(env, 0.02)                                  --  out (age 0 is the first frame: not over)
	local flick = 1 + 0.1 * math.sin(age * 70) + 0.05 * math.sin(age * 131)
	local w = LASER_WIDTH * env * flick
	strip(LZ.spr.beam, bm.from, bm.to, w * 2.4, 1, 0.08, 0.05, 0.55 * env)    -- the wide red glow
	strip(LZ.spr.beam, bm.from, bm.to, w * 1.1, 1, 0.12, 0.1, 0.9 * env)      -- crimson body
	strip(LZ.spr.beam, bm.from, bm.to, w * 0.4, 10, 9, 9, env)                -- the white-hot core
	strip(LZ.spr.beam, bm.from, bm.to, w * 0.15, 12, 12, 12, env)             -- its blinding centre line
	local len = VecLength(VecSub(bm.to, bm.from))
	for d = 0, len, 6 do PointLight(VecLerp(bm.from, bm.to, d / math.max(len, 0.01)), 1, 0.15, 0.1, 4 * env) end
	-- the shockwave ring at the maw, the flash where it struck
	local ring = math.min(1, age / 0.35)
	if bm.m ~= GetLocalPlayer() then
		billboard(LZ.spr.ring, bm.from, 0.5 + 5 * ring, 1, 0.3, 0.25, (1 - ring) * 0.9)
		billboard(LZ.spr.flare, bm.from, 2.5 * env, 1, 0.4, 0.35, env)
	end
	if bm.hit then
		billboard(LZ.spr.ring, bm.to, 0.5 + 7 * ring, 1, 0.45, 0.3, (1 - ring))
		billboard(LZ.spr.flare, bm.to, 4 * env, 1, 0.5, 0.4, env)
		PointLight(bm.to, 1, 0.3, 0.15, 14 * env)
	end
	if age < 0.5 then                                          -- sparks spiralling round the beam
		local axis = VecScale(VecSub(bm.to, bm.from), 1 / math.max(len, 0.01))
		local side = VecNormalize(VecCross(axis, math.abs(axis[2]) > 0.9 and Vec(1, 0, 0) or Vec(0, 1, 0)))
		local up = VecCross(axis, side)
		for i = 1, 10 do
			local d = math.random() * len
			local a = d * 0.8 + age * 25
			local out = VecAdd(VecScale(side, math.cos(a)), VecScale(up, math.sin(a)))
			local p = VecAdd(VecLerp(bm.from, bm.to, d / math.max(len, 0.01)), VecScale(out, w * 0.6))
			sparks(p, VecAdd(VecScale(out, 3), VecScale(axis, 6)), 0.4, 1, 0.5 + 0.5 * math.random(), 0.4, 0.07)
		end
	end
	return true
end

-- (client.draw, the hunt) a clicker that owns the laser: ready, charging or its cooldown, under its echolocation line
function ehLaserDraw()
	local me = GetLocalPlayer()
	if ehUpLevel(me, "laser") <= 0 or not ehIsMonster(me) then return end
	local now = GetTime()
	local left = (LZ.readyAt or 0) - now
	local text, a
	if LZ.charge[me] and not LZ.charge[me].fired then
		local k = math.min(1, (now - LZ.charge[me].t0) / (LASER_CHARGE or 2))
		text, a = k >= 1 and "LASER CHARGED - let go to fire" or string.format("charging laser %d %%", math.floor(k * 100)), 1
	elseif left > 0 then
		text, a = string.format("laser in %d s", math.ceil(left)), 0.6
	else
		text, a = "laser ready (hold LMB)", 0.85
	end
	UiPush()
	UiTranslate(UiCenter(), UiHeight() - 28)
	UiAlign("center middle")
	UiFont("bold.ttf", 20)
	UiColor(1, 0.35, 0.3, a)
	UiText(text)
	UiPop()
end

function ehLaserClientTick(dt)
	lzAssets()
	local now = GetTime()
	-- charges starting / ending (a charge let go early: its sound cut)
	local ch = type(shared.ehLaser) == "table" and shared.ehLaser or {}
	for m, c in pairs(LZ.charge) do
		if ch[m] ~= c.n then
			if c.h and not c.fired then StopSound(c.h) end
			LZ.charge[m] = nil
		end
	end
	for m, n in pairs(ch) do
		if not LZ.charge[m] and IsPlayerValid(m) then
			LZ.charge[m] = {n = n, t0 = now, h = PlaySound(LZ.snd.charge, maw(m), 0.55, false)}
		end
	end
	-- a new shot
	local b = shared.ehBeam
	if LZ.beamN == nil then LZ.beamN = b and b.n or 0 end        -- (shots before this machine looked: not replayed)
	if b and b.n ~= LZ.beamN then
		LZ.beamN = b.n
		local from, to = Vec(b.x0, b.y0, b.z0), Vec(b.x1, b.y1, b.z1)
		LZ.beams[#LZ.beams + 1] = {t0 = now, from = from, to = to, hit = b.hit, m = b.m}
		if LZ.charge[b.m] then LZ.charge[b.m].fired = true end
		if b.m == GetLocalPlayer() then LZ.readyAt = now + (LASER_CD or 45) end   -- (its own shot: the cooldown on its screen)
		PlaySound(LZ.snd.fire, from, 0.7, false)
		if b.hit then PlaySound(LZ.snd.hit, to, 0.45, false, 0.8) end
		local cam = GetCameraTransform().pos
		local u = VecSub(to, from)
		local L2 = math.max(VecDot(u, u), 1e-6)
		local s = math.max(0, math.min(1, VecDot(VecSub(cam, from), u) / L2))
		local d = VecLength(VecSub(cam, VecAdd(from, VecScale(u, s))))
		if d < LASER_SHAKE_R then ShakeCamera(1.2 * (1 - d / LASER_SHAKE_R)) end
		for i = 1, (b.hit and 40 or 0) do                        -- the burst where it struck
			local dir = VecNormalize(Vec(math.random() - 0.5, math.random() - 0.3, math.random() - 0.5))
			sparks(to, VecScale(dir, 6 + 10 * math.random()), 0.5 + 0.5 * math.random(), 1, 0.4 + 0.5 * math.random(), 0.2, 0.1)
		end
	end
	for m, c in pairs(LZ.charge) do if IsPlayerValid(m) and not c.fired then drawCharge(m, c, now) end end
	local keep = {}
	for _, bm in ipairs(LZ.beams) do if drawBeam(bm, now) then keep[#keep + 1] = bm end end
	LZ.beams = keep
	-- clickers who own it: a faint red glow pulsing in the maw (its model's glowing insert pulses with it: monster_visual)
	local up = type(shared.ehUp) == "table" and shared.ehUp or {}
	for m, u in pairs(up) do
		if (u.laser or 0) > 0 and IsPlayerValid(m) and m ~= GetLocalPlayer() and ehIsMonster(m) and not LZ.charge[m] then
			PointLight(maw(m), 1, 0.1, 0.06, 0.6 + 0.4 * math.sin(now * 3 + m))
		end
	end
end
