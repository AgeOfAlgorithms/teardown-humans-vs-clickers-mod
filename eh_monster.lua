-- Echo Hunt: the monster's systems, shared by the game mode (echohunt.lua) and the TEST copies (the vision probe, the
-- test level). Included (no #version line) after "script/include/player.lua", "mantle.lua", "monster_rig.lua",
-- "monster_anim.lua", "monster_visual.lua". Textual include: its file-level locals are visible to the including
-- script (the probe's test keys use them).
--
-- Interface (the including script calls these from its own callbacks; an included file's locals are NOT visible to
-- the including script in Teardown - verified in-game 2026-10-18 - so everything it needs is a global function here):
--   client: ehClientInit(); ehClientDestroy(); ehClientTick(dt, ms) every frame (ms = a list of the monster players,
--           or one player, 0 = none: the view is on while this machine's player is one); ehClientDraw();
--           ehClientRender(dt, ms); ehClientPostUpdate()
--   server: ehServerInit(); ehServerUpdate(dt); ehServerTick(dt, ms, hunting) every frame (the hunting monsters);
--           applyWeather(env); ServerCall("server.ehScream", p) (a monster's client, on its pulse)
--   state:  ehViewOn(), ehPulseCooldown() (s left), ehPulseReset(), ehPulseLast(), ehFog(void, gamma) (sets either,
--           returns both), ehPlaceDummy() (TEST: a dummy human where the camera aims), ehDebug() (a snapshot table)
--   shared (written by the server): ehMonsters (the list), ehMonster (the first), ehNoise (noise events), ehCall[p]
--           (each monster's calls), ehScream[p] (counters), ehStam[p] (stamina {s, run, ex})
-- Several monsters (AgeOfAlgorithms): they see each other (only humans are hidden from a monster) and hear each other (every
-- monster's footfalls, calls, attacks play on every machine; their voices are Proximity Comms' own).
--
-- The monster's view: it sees what is near clearly, in black and white, and NOTHING beyond a radius: a black box (4
-- walls + a roof of panels its machine spawns and moves with its camera, colliding with nothing) at the void radius,
-- black smoke thickening from 55 % of it, gamma darkening; always first person from the head of a ~3.6 m creature.
-- Humans are never drawn for it, only highlights of what it hears: their pose (footsteps, tools, talking), a car's
-- outline, a gun at the hand, ripples and starbursts for loud world sounds. It hears the game's sounds as they are.
-- RMB: the echo pulse (35 m sphere, reveals humans live for 4 s, the void pushed out; cooldown 20 s miss / 45 s hit).
-- Standing still 5 s it hears nearby hearts. Server: walk 7 / run 11 m/s on Shift with stamina, a jump clearing its
-- body, mantling at chest height, calls (clicking / hissing) every 15-30 s, heavy footfalls everyone hears.

PULSE_RANGE = 60      -- m: echo pulse reach (a sphere): 3 times the normal view, FOG_VOID (AgeOfAlgorithms)
PULSE_SPEED = 55      -- m/s: the pulse front (reveals humans as it passes them)
PULSE_HOLD = 4.0      -- s the view stays opened out after the front reaches its end (AgeOfAlgorithms: to find the way for ~4 s)
PULSE_FADE = 1.4      -- s back to the normal fog
PULSE_PUSH = 3.0      -- the pulse pushes the void this many times further out at its peak (to its reach)
FOG_VOID = 20         -- m: nothing is drawn beyond this (the black box's walls)
FOG_MIN, FOG_MAX = 8, 30
FOG_START = 0.55      -- the fog starts at this share of the void radius and thickens to the walls (darker toward the
                      -- edge, AgeOfAlgorithms); thin smoke right at the walls only took the haze's grey and vanished (autotest)
FOG_RATE = 45         -- smoke particles per frame through the fog band (at 60 fps)
FOG_WALL_RATE = 30    -- and per frame in its outer 15 %, so the edge is darkest
FOG_LIGHT = 30        -- the unshadowed light at the eyes (made little difference in the photos)
EH_PANEL_SCALE = false -- (the void box's panel scale when set: a TEST benchmark)
EH_BENCH = false       -- (a TEST benchmark sets a table of parts to switch off: tools/autotest/benchtest.lua)
PULSE_COLOR = 0.5     -- colour comes back this much while the pulse holds the view open (0 = black and white; AgeOfAlgorithms)
FOG_BRIGHT = 0.6      -- image brightness (barely darkens inside the box: the auto-exposure makes up for it)
FOG_GAMMA = 0.5       -- below 1 darkens (gamma 0.5 was much darker in a test), dim things first: the edge goes dark
PANEL_SIZE = 3.2      -- m: fogpanel.vox (32 voxels) at scale 1; spawned big enough for the farthest box (pulse included)
FOG_LIFE = 0.6        -- s a fog particle lives (they are re-spawned around the camera all the time)
EYE_RAISE = 1.6       -- m the monster's eyes are above a human's (it is ~3.6 m tall); less under a low ceiling
FOG_GAP = 0.8         -- m a fog particle keeps in front of a surface
WAVE_TIME = 0.15      -- s the scan wave's particles are released over
WAVE_COUNT = 900      -- particles in the scan wave (they fly out at PULSE_SPEED and stick where they hit: sonar paint)
PULSE_CD_MISS = 20    -- s cooldown after a pulse that revealed no one
PULSE_CD_HIT = 45     -- s cooldown after a pulse that revealed a human
CLICK_PULSE_VOL = 2.0  -- its echolocation clicking: loud (AgeOfAlgorithms: "distinctive, loud, echoey, aggressive, organic")
MONSTER_WALK = 7.0    -- m/s: the same as a human's walk (the engine's default walkingSpeed)
MONSTER_RUN = 11.0    -- m/s while Shift is held (fairly fast) and there is stamina
MONSTER_JUMP = 3.2    -- m aimed: the jump clears its own ~3.6 m body (autotest: aiming 3.8 rose 4.5 m - the engine's
                      -- own jump adds on top; 3.2 should rise ~3.8 m)
JUMP_BOOST_TIME = 0.1 -- s the take-off speed is held (pushed every tick: works for a remote player too)
MONSTER_TOP = 3.7     -- m from its feet to the top of its head: rising, it stops short of a ceiling there (its player
                      -- body is a human's: a jump carried the model's head through roofs - AgeOfAlgorithms)
STAMINA = 6.0         -- s of running from a full bar
STAMINA_REGEN = 0.75  -- s of stamina back per s walking (x1.6 standing still)
EXHAUSTED_UNTIL = 0.35   -- an empty bar must refill this far before running again
ATTACK_STAMINA = 0.8  -- s of the bar an attack (a swipe or a grab) takes (AgeOfAlgorithms: not just running)
JUMP_STAMINA = 0.8    -- s of the bar its big jump takes (AgeOfAlgorithms); without enough (or exhausted) only a human's hop
MSTEP_WALK = 1.8      -- m between the monster's footfalls walking (its stride: 3.6 m per cycle), everyone hears them
MSTEP_RUN = 1.7       -- m running (feet and claws)
MSTEP_CROUCH_VOL = 0.12   -- crouch-walking, its footfalls are barely there (AgeOfAlgorithms)
-- its breathing (AgeOfAlgorithms): soft walking, harder and faster running, nothing crouched; idle a slow soft breath.
-- {seconds between breaths, volume} by gait
BREATH = {idle = {3.4, 0.25}, walk = {2.3, 0.45}, run = {0.85, 0.9}}
BREATH_OWN = 0.5      -- the monster hears its own breathing this much quieter (at its eyes)
MCALL_MIN, MCALL_MAX = 15, 30  -- s between the monster's calls (wet clicking or a hiss), everyone hears them (6-14: too often)
STEP_SPEED = 1.5      -- m/s: walking faster than this makes footsteps (not while crouched)
HEAR_MIN = 0.15       -- GetLastSound volume that can be heard at all (a remote player's footsteps read ~0.05)
HEAR_PER_VOL = 60     -- m a sound of volume 1 carries: louder = heard further. GetLastSound's volume is the sound's own,
                      -- not by distance (autotest 2026-10-18: holes 0.30-0.53, a dropped crate 0.22, a bullet impact
                      -- 0.52, explosions 1.3 (size 0.5) and 4.9 (size 1.5); the same hole at 11 and 26 m read the same)
HEAR_MAX = 150        -- m at most (breaking, impacts)
-- explosions (volume >= BURST_VOL) carry much further (AgeOfAlgorithms): BOOM_BASE + BOOM_PER_VOL x volume, at most BOOM_MAX -
-- a small one (1.3) ~170 m, a big one (4.9) 300 m
BOOM_BASE, BOOM_PER_VOL, BOOM_MAX = 120, 40, 300
PING_MIN, PING_MAX = 0.8, 4.0   -- s a heard noise's highlight lasts: weak (quiet, far) .. strong (loud, close)
STEP_REACH_WALK, STEP_REACH_RUN = 10, 18   -- m footsteps are heard
-- humans' tools as noises: reach (m), loudness 0..1, clip = what it is (gun: a gun shape is drawn); hold = while held
TOOL_NOISE = {
	gun = {r = 120, loud = 0.8, clip = "gun"},            -- (guns, explosions, vehicles: about twice as far, AgeOfAlgorithms)
	shotgun = {r = 140, loud = 0.9, clip = "gun"},
	rifle = {r = 160, loud = 1.0, clip = "gun"},
	rocket = {r = 200, loud = 1.0, clip = "gun"},
	sledge = {r = 25, loud = 0.5, clip = "thud"},
	blowtorch = {r = 15, loud = 0.3, clip = "thud", hold = true},
	extinguisher = {r = 12, loud = 0.3, clip = "thud", hold = true},
	leafblower = {r = 20, loud = 0.4, clip = "thud", hold = true},
	spraycan = {r = 6, loud = 0.2, clip = "thud", hold = true},
}
TOOL_DEFAULT = {r = 80, loud = 0.6, clip = "gun"}   -- any other tool fired (weapon mods register their own names)
HOLD_EVERY = 0.5      -- s between noises of a held tool
VEH_EVERY = 0.6       -- s between a vehicle's engine noises
VEH_REACH_MIN, VEH_REACH_PER, VEH_REACH_MAX = 25, 5, 120  -- m: 25 idling, +5 per m/s, at most 120
BOAT_REACH_MIN, BOAT_REACH_PER, BOAT_REACH_MAX = 80, 8, 200   -- m: a vehicle in water - a boat "a lot of noise" (AgeOfAlgorithms)
SPLASH_REACH = 50     -- m: a human getting into water (a big splash - AgeOfAlgorithms: "pretty large noises")
SWIM_EVERY = 0.6      -- s between a swimming human's noises (floating still: none)
SWIM_REACH_MIN, SWIM_REACH_PER, SWIM_REACH_MAX = 30, 6, 55   -- m: swimming, +6 per m/s
MONSTER_SWIM = 10.0   -- m/s a monster swims where it looks (AgeOfAlgorithms: "excellent swimmers"; a human swims ~3)
MONSTER_SWIM_RUN = 14.0   -- m/s with Shift (stamina, like running)
MONSTER_SWIM_RISE = 5.0   -- m/s up (jump held) or down (crouch held)
WEATHERS = {"sunny", "sunset", "night", "foggy", "rainynight"}
HEART_STILL = 7.0     -- s the monster must stand still before it hears heartbeats (AgeOfAlgorithms: 7 s, like the glow)
HEART_FADE = 3.0      -- s they take to fade in (out: 0.5 s once it moves)
HEART_R = 30          -- m: humans this close are heard (15: hardly ever - AgeOfAlgorithms)
HEART_FAST_R = 8      -- m: closer than this a heart races
HEART_GLOW_R = 200    -- m: standing still it also sees a faint red glow toward each human this close (AgeOfAlgorithms)
HEART_GLOW_STILL = 7  -- s still before the glow starts (AgeOfAlgorithms; the heartbeats' sound: HEART_STILL)
HEART_GLOW_EVERY = 7  -- s between its pulses
HEART_GLOW_LEN = 2.0  -- s a pulse lasts (in, then out to nothing)
HEART_GLOW_SCATTER = 0.5    -- each pulse centred on a random point up to this share of the distance off (6-60 m), where
                            -- it stays (it doesn't follow them): a hint of the direction, not the position (AgeOfAlgorithms)
HEART_COL = {0.95, 0.12, 0.18}
REVEAL_LIFE = 4.0     -- s a pulse-revealed human stays visible
REVEAL_COL = {1.0, 0.88, 0.2}   -- a revealed human's aura / the pointer to them off screen (AgeOfAlgorithms: easy to see)
GLOW = {1.0, 0.55, 0.35}
BURST = {1.0, 0.25, 0.12}  -- an explosion's starburst
BURST_VOL = 1.0            -- GetLastSound volume from which a sound is drawn as an explosion (explosions read 1.3-4.9)
FRONT = {0.55, 1.0, 0.95}
RIPPLE = {0.78, 0.86, 1.0}
MONSTER_GLOW = {0.72, 0.38, 1.0}   -- another monster heard (its model outlined): violet, unlike the humans' (AgeOfAlgorithms)
-- how far another monster's noises carry to a monster (m): its footfalls by gait, a landing (more for a harder one),
-- its claws tearing into something
MREACH_WALK, MREACH_RUN, MREACH_CROUCH = 20, 30, 5
MREACH_LAND_MIN, MREACH_LAND_MAX = 20, 45
MREACH_SWIPE = 30
PP_KEYS = {"brightness", "saturation", "gamma", "bloom"}
CHAINS = {
	{"pelvis", "stomach", "chest", "neck", "head"},
	{"chest", "shoulder_l", "arm_upper_l", "arm_lower_l", "hand_l"},
	{"chest", "shoulder_r", "arm_upper_r", "arm_lower_r", "hand_r"},
	{"pelvis", "leg_upper_l", "leg_lower_l", "foot_l", "toes_l"},
	{"pelvis", "leg_upper_r", "leg_lower_r", "foot_r", "toes_r"},
}
-- a standing figure (feet at 0) for when no animator pose can be read
STAND = {
	{{0, 1.0, 0}, {0, 1.25, 0}, {0, 1.45, 0}, {0, 1.6, 0}},
	{{0, 1.45, 0}, {-0.2, 1.45, 0}, {-0.25, 1.15, 0}, {-0.28, 0.85, 0}},
	{{0, 1.45, 0}, {0.2, 1.45, 0}, {0.25, 1.15, 0}, {0.28, 0.85, 0}},
	{{0, 1.0, 0}, {-0.1, 1.0, 0}, {-0.12, 0.5, 0}, {-0.12, 0.05, 0}},
	{{0, 1.0, 0}, {0.1, 1.0, 0}, {0.12, 0.5, 0}, {0.12, 0.05, 0}},
}

local on = false
local fogVoid = FOG_VOID
local fogGamma = FOG_GAMMA
local panels = {}          -- the void box's bodies (this machine's): both sets
local panelShapes = {}
local panelSet = {small = {}, big = {}, active = nil, smallReach = 0}   -- (two sizes: see voidSpawn)
local light = nil          -- the unshadowed light at the eyes (this machine's)
local mstep = {caught = nil, per = {}}   -- every monster's footfalls, landings, calls, attacks (every machine): per[p]
local saved = nil          -- the level's post-processing values while the view is on
local pulseT = -100
local pulseReady = 0
local pulseLast = ""
local pending = {}         -- humans the pulse front has yet to reach: {dist, target}
local reveals = {}         -- humans this pulse revealed: {t0, player | pos} (their aura / pointer for REVEAL_LIFE)
local pulseAlerted = false -- the alert played for this pulse
local pings = {}           -- {t0, life, pose | pos, col}
local dummies = {}         -- {pos, pose, nextNoise}
local steps = {}           -- [player] = time of their next footstep ping
local people = {}          -- other players this frame
local hiddenNow = 0        -- how many humans are hidden this frame (HUD)
local lastVol, lastVolT, lastRipT = 0, -100, -100
local snd = {}
local camRaise = EYE_RAISE
local camDip = nil          -- the mantle's pull-up dip, folded into the monster's camera
local cam = nil            -- the monster's camera this frame
EH_HEARD = false          -- a test hook: function(kind, distance, strength), called for everything the monster hears
local noiseSeen = nil      -- the last server noise event handled (shared.ehNoise.seq)
local detected = {n = nil, t = -100}   -- this player detected by the pulse: when (the warning)
local heart = {still = 0, level = 0, next = {}}   -- the monster's stillness, the heartbeats' fade, each human's next beat

----- helpers -----

local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end

-- 0 normally, rising to 1 while the pulse has cleared the fog, back to 0 as it fades
local function pulseClear(now)
	local a = now - pulseT
	local grow = PULSE_RANGE / PULSE_SPEED
	if a < 0 or a > grow + PULSE_HOLD + PULSE_FADE then return 0 end
	if a < grow then return a / grow end
	a = a - grow
	if a < PULSE_HOLD then return 1 end
	return 1 - (a - PULSE_HOLD) / PULSE_FADE
end

----- post-processing (per machine, persistent: save and restore the level's values) -----

-- (also kept in this machine's registry: a script restart - the host restarting a round - skips client.destroy, and
-- a machine that had been the monster kept its dark black-and-white view as a human; AgeOfAlgorithms' flashlight "didn't work")
PP_REG = "echohunt.pp"
local function ppSave()
	saved = {}
	for i = 1, #PP_KEYS do
		saved[PP_KEYS[i]] = GetPostProcessingProperty(PP_KEYS[i])
		SetFloat(PP_REG .. "." .. PP_KEYS[i], saved[PP_KEYS[i]] or 0)
	end
	local r, g, b = GetPostProcessingProperty("colorbalance")
	saved.cb = {r, g, b}
	SetFloat(PP_REG .. ".cbr", r or 1); SetFloat(PP_REG .. ".cbg", g or 1); SetFloat(PP_REG .. ".cbb", b or 1)
	SetBool(PP_REG .. ".saved", true)
end

-- a script start: undo what an earlier run of this script left on this machine (its darkened view, its void box, its
-- monster models, its lights)
local function leftovers()
	if GetBool(PP_REG .. ".saved") then
		for i = 1, #PP_KEYS do SetPostProcessingProperty(PP_KEYS[i], GetFloat(PP_REG .. "." .. PP_KEYS[i])) end
		SetPostProcessingProperty("colorbalance", GetFloat(PP_REG .. ".cbr"), GetFloat(PP_REG .. ".cbg"), GetFloat(PP_REG .. ".cbb"))
		SetBool(PP_REG .. ".saved", false)
	end
	for _, tag in ipairs({"ehfog", "ehmonster"}) do
		for _, b in ipairs(FindBodies(tag, true) or {}) do Delete(b) end
	end
	for _, l in ipairs(FindLights("ehfog", true) or {}) do Delete(l) end
end

local function ppApplySaved()
	if not saved then return end
	for i = 1, #PP_KEYS do
		local v = saved[PP_KEYS[i]]
		if v then SetPostProcessingProperty(PP_KEYS[i], v) end
	end
	if saved.cb[1] then SetPostProcessingProperty("colorbalance", saved.cb[1], saved.cb[2], saved.cb[3]) end
end

-- one batch of fog particles in a shell from near to far around eye (mostly where the camera looks), each kept
-- FOG_GAP in front of whatever is in its way (a particle touching a surface fades into it) and none in front of a
-- surface inside the clear zone
local function fogShell(eye, fwd, near, far, count)
	for i = 1, count do
		local d
		if math.random() < 0.8 then
			d = VecAdd(fwd, Vec(math.random() * 1.8 - 0.9, math.random() * 1.4 - 0.7, math.random() * 1.8 - 0.9))
		else
			d = Vec(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5)
		end
		local len = VecLength(d)
		if len > 0.01 then
			d = VecScale(d, 1 / len)
			local r = near + (far - near) * math.sqrt(math.random())   -- (thicker further out)
			QueryRejectPlayer(GetLocalPlayer())
			ehQueryMask()
			local hit, h = QueryRaycast(eye, d, r)
			if hit then r = h - FOG_GAP end
			if r >= near then SpawnParticle(VecAdd(eye, VecScale(d, r)), Vec(0, 0, 0), FOG_LIFE) end
		end
	end
end

-- the void box: 4 walls and a roof of black panels, and the light inside (this machine only)
local PANEL_DIRS = {
	{Vec(0, 0, -1), QuatEuler(90, 0, 0)}, {Vec(0, 0, 1), QuatEuler(90, 0, 0)},
	{Vec(-1, 0, 0), QuatEuler(0, 0, 90)}, {Vec(1, 0, 0), QuatEuler(0, 0, 90)},
	{Vec(0, 1, 0), QuatEuler(0, 0, 0)},
}

-- Two sets of panels: moving a static shape makes the engine redo what it overlaps, and the cost grows with its size
-- (Isla Estocastica, the host the monster: 184 m panels 21-31 fps, 124 m 45, 90 m and less 60 - benchtest.lua). The
-- small set (2.6 x the normal radius) serves the normal view; the big one only while a pulse pushes the box out (124 m
-- panels 60 m away: 60 fps). The set not in use is parked once, not moved.
local function spawnSet(scale, list)
	for i = 1, #PANEL_DIRS do
		local ents = Spawn(string.format("<body><vox file='MOD/vox/fogpanel.vox' scale='%.2f' tags='ehfog'/></body>", scale),
			Transform(Vec(0, -500, 0)))
		for _, e in ipairs(ents or {}) do
			if GetEntityType(e) == "body" then
				list[#list + 1] = e
				panels[#panels + 1] = e
				for _, sh in ipairs(GetBodyShapes(e)) do
					SetShapeCollisionFilter(sh, 64, 0)                  -- (nothing collides with it; bullets pass)
					panelShapes[#panelShapes + 1] = sh
				end
			end
		end
	end
end

local function voidSpawn()
	panelSet.small, panelSet.big, panelSet.active = {}, {}, nil
	panelSet.smallReach = fogVoid * 1.3
	spawnSet(EH_PANEL_SCALE or (2 * panelSet.smallReach) / PANEL_SIZE, panelSet.small)
	spawnSet(EH_PANEL_SCALE or (2 * fogVoid * PULSE_PUSH + 8) / PANEL_SIZE, panelSet.big)
	local ents = Spawn("<light tags='ehfog' type='sphere' color='1 1 1' scale='1' size='0.3' unshadowed='1'/>", Transform(Vec(0, -500, 0)))
	for _, e in ipairs(ents or {}) do
		if GetEntityType(e) == "light" then light = e end
	end
end

local function voidDelete()
	for _, b in ipairs(panels) do Delete(b) end
	if light then Delete(light) end
	panels, panelShapes, light = {}, {}, nil
	panelSet.small, panelSet.big, panelSet.active = {}, {}, nil
end

-- (TEST benchmark) the void box again at another panel scale (nil: the normal one)
function ehVoidRespawn(scale)
	EH_PANEL_SCALE = scale
	if not on then return end
	voidDelete()
	voidSpawn()
end

-- our rays skip the void box (the dummy's aim ray is long enough to reach it)
local function rejectFog()
	if #panelShapes > 0 then QueryRejectShapes(panelShapes) end
end

-- the view for this frame: black-and-white; the box at the void radius (pushed out by the pulse), the light inside
-- (short of the walls), and black smoke thickening from FOG_START of the radius to the walls
local function fogApply(eye, clear, dt)
	SetPostProcessingProperty("saturation", PULSE_COLOR * clear)    -- (black and white; some colour in a pulse)
	SetPostProcessingProperty("bloom", 0)
	SetPostProcessingProperty("gamma", fogGamma)
	SetPostProcessingProperty("brightness", FOG_BRIGHT)
	local dist = fogVoid * (1 + (PULSE_PUSH - 1) * clear)
	local bench = EH_BENCH or {}                                 -- (only a TEST benchmark sets it: parts switched off)
	local set = (dist <= panelSet.smallReach) and panelSet.small or panelSet.big
	if set ~= panelSet.active then                               -- (the other set parked, once)
		for _, b in ipairs(set == panelSet.small and panelSet.big or panelSet.small) do SetBodyTransform(b, Transform(Vec(0, -500, 0))) end
		panelSet.active = set
	end
	for i, b in ipairs(bench.nopanels and {} or set) do
		local pd = PANEL_DIRS[i]
		if pd then SetBodyTransform(b, Transform(VecAdd(eye, VecScale(pd[1], dist + 0.25)), pd[2])) end
	end
	if light then
		SetProperty(light, "transform", Transform(eye))
		SetProperty(light, "intensity", FOG_LIGHT)
		SetProperty(light, "reach", dist * 0.85)                -- (short of the walls: they stay black, the edge fades dark)
	end
	local fwd = TransformToParentVec(cam or GetCameraTransform(), Vec(0, 0, -1))
	ParticleReset()
	ParticleType("smoke")
	ParticleColor(0, 0, 0)
	ParticleRadius(1.0)
	ParticleAlpha(1.0, 1.0, "constant", 0.2, 0.7)
	ParticleGravity(0)
	ParticleDrag(0)
	ParticleEmissive(0)
	ParticleCollide(0)
	if bench.nofog then return end
	local k = math.min(dt, 0.05) * 60
	local near, far = dist * FOG_START, dist - 0.3
	k = k * (bench.fogk or 1)
	fogShell(eye, fwd, near, far, math.floor(FOG_RATE * k + math.random()))
	fogShell(eye, fwd, far - 0.15 * (far - near), far, math.floor(FOG_WALL_RATE * k + math.random()))
end

-- the monster's eyes: always first person whatever the player's third-person setting (the camera is set every
-- frame), at the head of a creature twice a human's height, eased down under a low ceiling (never through it)
local function monsterCamera(me, dt)
	local eye = GetPlayerEyeTransform(me)
	QueryRejectPlayer(me)
	ehQueryMask()
	local hit, d = QueryRaycast(eye.pos, Vec(0, 1, 0), EYE_RAISE + 0.3)
	local want = hit and math.max(0, d - 0.3) or EYE_RAISE
	if want < camRaise then camRaise = want                       -- (down at once: never into the ceiling)
	else camRaise = camRaise + (want - camRaise) * math.min(1, dt * 4) end
	cam = Transform(VecAdd(eye.pos, Vec(0, camRaise, 0)), eye.rot)
	if camDip then cam = TransformToParentTransform(cam, camDip) end
	SetCameraTransform(cam)
	-- Proximity Comms' pings from the clicker's eyes, through ITS OWN model and hit boxes only (another clicker can be
	-- pinged): its ping ray began at the hidden human's eyes inside them, so every pin landed on itself (AgeOfAlgorithms). The chat
	-- reads both keys every frame (proxchat.aim, proxchat.pingskip: its API 12, up to 64 handles)
	local d = TransformToParentVec(cam, Vec(0, 0, -1))
	SetString("proxchat.aim", string.format("%.3f %.3f %.3f %.4f %.4f %.4f", cam.pos[1], cam.pos[2], cam.pos[3], d[1], d[2], d[3]))
	local skip = {}
	for _, b in ipairs(panels) do skip[#skip + 1] = tostring(b) end   -- (the void box around its view: else a pin
	                                                                   --  stops on its wall in mid-air - the chat's agent)
	for _, b in ipairs(monsterVisualBodies(me)) do skip[#skip + 1] = tostring(b) end
	for _, b in ipairs(EH_HIT_BODIES or {}) do
		if GetTagValue(b, "ehowner") == tostring(me) then skip[#skip + 1] = tostring(b) end
	end
	SetString("proxchat.pingskip", table.concat(skip, " "))
	return cam.pos
end

----- poses -----

-- the pose of player p (0 = this machine's player), moved by offset; nil when it can't be read
local function capturePose(p, offset)
	local anim = GetPlayerAnimator(p)
	if not anim or anim == 0 then return nil end
	local segs = {}
	for c = 1, #CHAINS do
		local ch = CHAINS[c]
		local prev = nil
		for k = 1, #ch do
			local pt = VecAdd(GetBoneWorldTransform(anim, ch[k]).pos, offset)
			if prev then segs[#segs + 1] = {prev, pt} end
			prev = pt
		end
	end
	local head = VecAdd(GetBoneWorldTransform(anim, "head").pos, offset)
	local foot = VecAdd(GetBoneWorldTransform(anim, "foot_l").pos, offset)
	if VecLength(VecSub(head, foot)) < 0.6 then return nil end   -- no real pose
	return {segs = segs, head = VecAdd(head, Vec(0, 0.12, 0))}
end

local function standPose(feet)
	local segs = {}
	for c = 1, #STAND do
		local ch = STAND[c]
		for k = 2, #ch do
			segs[#segs + 1] = {VecAdd(feet, Vec(ch[k - 1][1], ch[k - 1][2], ch[k - 1][3])),
				VecAdd(feet, Vec(ch[k][1], ch[k][2], ch[k][3]))}
		end
	end
	return {segs = segs, head = VecAdd(feet, Vec(0, 1.72, 0))}
end

-- track: a player whose LIVE pose is drawn for the ping's life (an echolocation reveal follows every move)
-- how strongly a noise comes through, 0..1: closeness (1 at the source, 0 at the edge of its reach) times loudness
-- (0..1: a whisper 0.2 .. an explosion 1). A strong one is drawn brighter, steadier, thicker, and lasts longer.
function noiseStrength(d, reach, loud)
	local near = clamp(1 - d / math.max(reach, 0.1), 0, 1)
	return clamp(near * (0.5 + 0.5 * loud), 0.05, 1)
end

function pingLife(s) return PING_MIN + (PING_MAX - PING_MIN) * s end

-- s: the noise's strength; life: a fixed life instead (a reveal)
-- who: the human who made it (their name is shown over it - pinned where it appeared, never following them - AgeOfAlgorithms)
local function addPose(pose, s, col, track, life, who)
	pings[#pings + 1] = {t0 = GetTime(), life = life or pingLife(s), s = s, pose = pose, col = col, track = track, who = who,
		nameAt = (who and pose and pose.head) and VecAdd(pose.head, Vec(0, 0.45, 0)) or nil}
end

-- a body (a car, a gun) outlined for the ping's life
local function addBodyPing(body, s, col)
	pings[#pings + 1] = {t0 = GetTime(), life = pingLife(s), s = s, body = body, col = col}
end

-- a gun fired: its shape and a muzzle flash at the human's hand (the engine reports no visible tool for a player
-- hidden on this machine, so the gun itself can't be outlined - noise autotest, 2026-10-18)
local function addGunPing(p, pos, s)
	local hand = VecAdd(pos, Vec(0, 1.3, 0))
	local anim = IsPlayerValid(p) and GetPlayerAnimator(p) or 0
	if anim and anim ~= 0 then hand = GetBoneWorldTransform(anim, "hand_r").pos end
	pings[#pings + 1] = {t0 = GetTime(), life = pingLife(s), s = s, pos = hand, col = GLOW, gun = true}
end

-- an explosion: a red starburst, sized by its loudness
local function addBurst(pos, vol, s)
	local rays, sparks = {}, {}
	for i = 1, 18 do rays[i] = {ang = (i + math.random() * 0.6) / 18 * 2 * math.pi, len = 0.55 + 0.5 * math.random()} end
	for i = 1, 10 do sparks[i] = {ang = math.random() * 2 * math.pi, k = 0.7 + 0.8 * math.random()} end
	pings[#pings + 1] = {t0 = GetTime(), life = pingLife(s) * 1.2, s = s, pos = pos, col = BURST, burst = rays,
		sparks = sparks, size = math.min(3, 0.8 + vol * 0.5)}
end

local function addRipple(pos, col, vol, s)
	pings[#pings + 1] = {t0 = GetTime(), life = pingLife(s) * 0.8, s = s, pos = pos, col = col, size = clamp(vol or 0.3, 0.2, 3)}
end

----- humans: dummies and the other players -----

local function listPeople(me)
	people = {}
	for p in Players() do
		if p ~= me and IsPlayerValid(p) and not ehIsMonster(p) then people[#people + 1] = p end   -- (humans only)
	end
end

local function rejectPeople()
	rejectFog()
	if #MV_SHAPES > 0 then QueryRejectShapes(MV_SHAPES) end
	QueryRejectPlayer(GetLocalPlayer())
	for i = 1, #people do QueryRejectPlayer(people[i]) end
end

local function targets()
	local list = {}
	for i = 1, #dummies do list[#list + 1] = {pos = dummies[i].pos, dummy = dummies[i]} end
	for i = 1, #people do
		local p = people[i]
		if GetPlayerHealth(p) > 0 then list[#list + 1] = {pos = GetPlayerTransform(p).pos, player = p} end
	end
	return list
end

local function targetPose(t)
	if t.dummy then return t.dummy.pose end
	return capturePose(t.player, Vec(0, 0, 0)) or standPose(t.pos)
end

-- humans are never drawn for the monster: only their highlights (noise, the pulse) show where they are
-- On the HOST, SetPlayerHidden on a human also takes their tools and flashlight (a client human's gun didn't hurt the
-- monster, their sledge broke nothing, their F did nothing - two/four-window tests; with a client as the monster all of
-- it works). The character a human is drawn as is spawned on each machine by the game's playerbody.lua (an animator and
-- its shapes): on the host those shapes - every bone's body, and the tool in hand - are tagged invisible instead (this
-- machine only), put back when the view goes. A client keeps SetPlayerHidden (its own screen only).
local tagged = {}                                              -- [shape] = true: made invisible on this machine
local function tagInvisible(body)
	if not body or body == 0 or not IsHandleValid(body) then return end
	for _, sh in ipairs(GetBodyShapes(body) or {}) do
		if not HasTag(sh, "invisible") then SetTag(sh, "invisible") end
		tagged[sh] = true
	end
end

-- a human's character bodies: every bone's, and whatever hangs off them on joints - hair, a hood, a radio, the wrench
-- on the leg (the characters' "attachment" joints: AgeOfAlgorithms saw them on the monster's screen; GetJointedBodies found
-- nothing - it takes dynamic bodies only, the animated bones aren't). Walked through the shapes' joints, keeping only
-- bodies whose shapes are tagged "bone" or "attachment": GetPlayerBodies added the bodies bullets hit - tagged
-- invisible on the host, no gunshot hurt a human any more (AgeOfAlgorithms). Rebuilt every second (a respawn: a new character).
local function characterShape(b)
	for _, sh in ipairs(GetBodyShapes(b) or {}) do
		if HasTag(sh, "attachment") or HasTag(sh, "bone") then return true end
	end
	return false
end

local charCache = {}                                           -- [player] = {t, anim, bodies}
local function characterBodies(p)
	local anim = GetPlayerAnimator(p) or 0
	local c = charCache[p]
	if c and c.anim == anim and GetTime() - c.t < 1 then return c.bodies end
	local seen, list, queue = {}, {}, {}
	local world = GetWorldBody()
	local function add(b, bone)
		if not b or b == 0 or seen[b] or b == world or not IsHandleValid(b) or GetBodyVehicle(b) ~= 0 then return end
		if not bone and not characterShape(b) then return end
		seen[b] = true
		list[#list + 1] = b
		queue[#queue + 1] = b
	end
	if anim ~= 0 then
		for _, bone in ipairs(GetBoneNames(anim) or {}) do add(GetBoneBody(anim, bone), true) end
	end
	local i = 1
	while i <= #queue and #list < 80 do
		for _, sh in ipairs(GetBodyShapes(queue[i]) or {}) do
			for _, j in ipairs(GetShapeJoints(sh) or {}) do
				local other = GetJointOtherShape(j, sh)
				if other and other ~= 0 then add(GetShapeBody(other)) end
			end
		end
		i = i + 1
	end
	charCache[p] = {t = GetTime(), anim = anim, bodies = list}
	return list
end

local function hideByTag(p)
	for _, b in ipairs(characterBodies(p)) do tagInvisible(b) end
	tagInvisible(GetToolBody(p))                               -- (the tool in hand)
end

function ehUnhideTagged()
	for sh in pairs(tagged) do if IsHandleValid(sh) then RemoveTag(sh, "invisible") end end
	tagged = {}
end

local function hideHumans()
	local host = IsPlayerHost(GetLocalPlayer())
	for i = 1, #people do
		local p = people[i]
		if host then hideByTag(p) else SetPlayerHidden(p) end
		local fl = GetFlashlight(p)                              -- their flashlights aren't seen either (AgeOfAlgorithms: blind,
		if fl and fl ~= 0 and IsHandleValid(fl) then SetLightEnabled(fl, false) end   --  cohesive)
	end
	hiddenNow = #people
end

-- every monster's footfalls and landings: heavy, clawed (every machine plays them at its feet; they don't count
-- for a monster's hearing). The engine's ordinary footsteps for its player still play underneath. Its calls and
-- attacks too: other monsters hear them as everyone does (AgeOfAlgorithms: monsters hear each other).
-- another monster's noise, heard by this machine's monster: its model outlined (violet) as strongly as the noise
-- comes through (AgeOfAlgorithms: monsters highlighted to each other when close enough)
local function hearMonster(m, kind, reach, loud)
	if not on or not cam or m == GetLocalPlayer() then return end
	local at = VecAdd(GetPlayerTransform(m).pos, Vec(0, 1.8, 0))
	local d = VecLength(VecSub(at, cam.pos))
	if d > reach then return end
	local st = noiseStrength(d, reach, loud)
	local bodies = monsterVisualBodies and monsterVisualBodies(m) or {}
	if #bodies > 0 then
		pings[#pings + 1] = {t0 = GetTime(), life = pingLife(st), s = st, bodies = bodies, col = MONSTER_GLOW}
	else
		addPose(standPose(GetPlayerTransform(m).pos), st, MONSTER_GLOW)
	end
	if EH_HEARD then EH_HEARD("monster_" .. kind, d, st) end
end

-- (eh_combat.lua) a monster hurt: the other monsters see its whole model (violet), as for its loud noises
function ehHearMonsterPain(m) hearMonster(m, "pain", 40, 1.0) end

local function oneMonsterSounds(m, dt, acts, calls)
	local ms = mstep.per[m]
	local a, call = acts[m], calls[m]
	local screams = type(shared.ehScream) == "table" and shared.ehScream or {}
	if not ms then                                              -- (first sight: what happened before is not replayed)
		ms = {dist = 0, air = false, fallV = 0, act = a and a.n or 0, call = call and call.n or 0, breathT = GetTime() + math.random(),
			scream = screams[m] or 0}
		mstep.per[m] = ms
	end
	local mine = (m == GetLocalPlayer())
	local pos = GetPlayerTransform(m).pos
	if (screams[m] or 0) ~= ms.scream then                      -- its echolocation: loud, echoey clicking - every machine
		ms.scream = screams[m] or 0                              -- hears it from its head (AgeOfAlgorithms); its own machine played it
		if not mine then                                         -- already, at its eyes, the moment it clicked
			PlaySound(snd.clickPulse, VecAdd(pos, Vec(0, 3.2, 0)), CLICK_PULSE_VOL, false,
				0.95 + math.random() * 0.1)
		end
	end
	if a and a.n ~= ms.act then                                 -- its attack: a claw swipe or a grab (eh_combat.lua)
		ms.act = a.n
		local at = mine and (cam and cam.pos or GetCameraTransform().pos) or VecAdd(pos, Vec(0, 2.6, 0))
		if a.kind == "swing_l" or a.kind == "swing_r" then
			PlaySound(snd.mswipe, at, 0.9, false, 0.9 + math.random() * 0.2)
			if a.hit then PlaySound(snd.mgrab, at, 1.0, false, 0.95 + math.random() * 0.1) end   -- (it struck someone: its roar)
			hearMonster(m, "swipe", MREACH_SWIPE, 0.8)
		elseif a.kind == "grab" then
			PlaySound(snd.mgrab, at, 1.0, false, 0.95 + math.random() * 0.1)
			hearMonster(m, "grab", MREACH_SWIPE, 1.0)
		end
	end
	if call and call.n ~= ms.call then                          -- (the server times the calls: everyone hears the same one)
		ms.call = call.n
		-- a monster hears its own call at its eyes (its voice); everyone else from the creature's head
		local at = mine and (cam and cam.pos or GetCameraTransform().pos) or VecAdd(pos, Vec(0, 3.2, 0))
		PlaySound(call.kind == "hiss" and snd.mhiss or snd.mclick, at, 0.85, false, 0.95 + math.random() * 0.1)
	end
	local v = GetPlayerVelocity(m)
	local now = GetTime()
	if now >= ms.breathT then                                   -- its breathing, by gait (none crouched or stunned)
		local sp = math.sqrt(v[1] * v[1] + v[3] * v[3])
		local hp = type(shared.ehHP) == "table" and shared.ehHP[m] or nil
		if GetPlayerCrouch(m) > 0.5 or (hp and hp.stun and hp.stun > 0) then
			ms.breathT = now + 0.5
		else
			local gait = (sp > 9 and "run") or (sp > 1 and "walk") or "idle"
			local b = BREATH[gait]
			ms.breathT = now + b[1] * (0.9 + 0.2 * math.random())
			local at = mine and (cam and cam.pos or GetCameraTransform().pos) or VecAdd(pos, Vec(0, 3.0, 0))
			PlaySound(gait == "run" and snd.breathHard or snd.breathSoft, at, b[2] * (mine and BREATH_OWN or 1), false,
				0.92 + math.random() * 0.12)
		end
	end
	if not IsPlayerGrounded(m) then
		ms.air = true
		ms.fallV = math.min(ms.fallV, v[2])
		return
	end
	if ms.air then
		ms.air = false
		local impact = -ms.fallV
		ms.fallV = 0
		if impact > 4 then
			local lv = clamp(impact / 9, 0.4, 1)                  -- the game's own recorded impacts, pitched down for its
			PlaySound(snd.landHit, pos, lv, false, 0.55 + math.random() * 0.1)   -- weight (AgeOfAlgorithms: the synthesized
			PlaySound(snd.landDirt, pos, lv, false, 0.6 + math.random() * 0.1)   -- one sounded fried)
			PlaySound(snd.flesh, pos, lv * 0.6, false, 0.5)
			hearMonster(m, "land", clamp(MREACH_LAND_MIN + impact * 2, MREACH_LAND_MIN, MREACH_LAND_MAX), clamp(impact / 9, 0.4, 1))
		end
	end
	local sp = math.sqrt(v[1] * v[1] + v[3] * v[3])
	ms.dist = ms.dist + sp * dt
	if sp > 1 and ms.dist >= (sp > 9 and MSTEP_RUN or MSTEP_WALK) then
		ms.dist = 0
		local crouched = GetPlayerCrouch(m) > 0.5
		local vol = (crouched and MSTEP_CROUCH_VOL) or (sp > 9 and 1.0) or 0.75
		PlaySound(snd.mstep, pos, vol, false, 0.9 + math.random() * 0.2)
		hearMonster(m, crouched and "step_crouch" or (sp > 9 and "step_run" or "step_walk"),
			crouched and MREACH_CROUCH or (sp > 9 and MREACH_RUN or MREACH_WALK), vol)
	end
end

local function monsterSounds(dt)
	local c = shared.ehCaught
	if mstep.caught == nil then mstep.caught = c and c.n or 0 end   -- (first frame: not replayed)
	if c and c.n ~= mstep.caught then                           -- a human caught: the game's flesh impact where they were
		mstep.caught = c.n
		if IsPlayerValid(c.p) then
			PlaySound(snd.flesh, VecAdd(GetPlayerTransform(c.p).pos, Vec(0, 1, 0)), 1.0, false, 0.8)
		end
	end
	local acts = type(shared.ehAct) == "table" and shared.ehAct or {}
	local calls = type(shared.ehCall) == "table" and shared.ehCall or {}
	local seen = {}
	for _, m in ipairs(ehMonsterList()) do
		if IsPlayerValid(m) then
			seen[m] = true
			oneMonsterSounds(m, dt, acts, calls)
		end
	end
	for m in pairs(mstep.per) do if not seen[m] then mstep.per[m] = nil end end
end

----- the echo pulse -----

local function startPulse(now, eye)
	pulseT = now
	pending = {}
	pulseAlerted = false
	local list = targets()
	for i = 1, #list do
		local d = VecLength(VecSub(list[i].pos, eye))
		if d <= PULSE_RANGE then pending[#pending + 1] = {dist = d, target = list[i]} end
	end
	if #pending > 0 then
		pulseReady = now + PULSE_CD_HIT
		pulseLast = "revealed " .. #pending
	else
		pulseReady = now + PULSE_CD_MISS
		pulseLast = "no one"
	end
	PlaySound(snd.clickPulse, eye, CLICK_PULSE_VOL, false, 0.95 + math.random() * 0.1)
	ShakeCamera(0.5)
	ServerCall("server.ehScream", GetLocalPlayer())      -- (everyone sees it scream)
end

-- the scan wave: glowing particles burst out from the monster in every direction at the front's speed; where they
-- hit something they stick and fade (walls, floors, debris light up for a moment). This machine only.
local function waveTick(now, eye, dt)
	local a = now - pulseT
	if a < 0 or a > WAVE_TIME then return end
	local n = math.floor(WAVE_COUNT * math.min(dt, 0.05) / WAVE_TIME + math.random())
	ParticleReset()
	ParticleType("plain")
	ParticleColor(0.75, 1, 0.95)
	ParticleRadius(0.05, 0.08)                              -- (0.09-0.16 read as puffs in flight, autotest)
	ParticleAlpha(1, 0, "easein")
	ParticleEmissive(3, 0, "easein")
	ParticleGravity(0)
	ParticleDrag(0)
	ParticleCollide(1)
	ParticleSticky(1)
	local life = PULSE_RANGE / PULSE_SPEED + PULSE_HOLD       -- (the paint lasts as long as the opened view)
	for i = 1, n do
		local d = Vec(math.random() * 2 - 1, math.random() * 2 - 1, math.random() * 2 - 1)
		local len = VecLength(d)
		if len > 0.05 and len <= 1 then                       -- (uniform over the sphere)
			d = VecScale(d, 1 / len)
			SpawnParticle(VecAdd(eye, VecScale(d, 0.8)), VecScale(d, PULSE_SPEED), life)
		end
	end
end

-- the scan on screen: rings sweeping out from the centre
local function drawScanRings(now)
	local a = now - pulseT
	if a < 0 or a > 0.9 then return end
	UiPush()
	UiTranslate(UiCenter(), UiMiddle())
	UiAlign("center middle")
	for k = 0, 2 do
		local f = (a - k * 0.12) / 0.7
		if f > 0 and f < 1 then
			UiColor(FRONT[1], FRONT[2], FRONT[3], (1 - f) * 0.55)
			UiCircleOutline(f * UiWidth() * 0.75, 2 + 6 * (1 - f))
		end
	end
	UiPop()
end

local function pulseTick(now)
	local front = (now - pulseT) * PULSE_SPEED
	for i = #pending, 1, -1 do
		local e = pending[i]
		if front >= e.dist then
			addPose(targetPose(e.target), 1, FRONT, e.target.player, REVEAL_LIFE)
			PlaySound(snd.echo, e.target.pos, 0.6, false)
			reveals[#reveals + 1] = {t0 = now, player = e.target.player, pos = VecCopy(e.target.pos)}
			if not pulseAlerted then                         -- a hit: the alert, once per pulse, at its ears
				pulseAlerted = true
				PlaySound(snd.alert, cam and cam.pos or GetCameraTransform().pos, 1.0, false)
			end
			table.remove(pending, i)
		end
	end
end

----- pings: heard humans (their pose), world sounds (a ripple) -----

local function uiLine(x1, y1, x2, y2, wid)
	local dx, dy = x2 - x1, y2 - y1
	local len = math.sqrt(dx * dx + dy * dy)
	if len < 0.5 then return end
	UiPush()
	UiTranslate(x1, y1)
	UiRotate(-math.deg(math.atan2(dy, dx)))
	UiAlign("left middle")
	UiRect(len, wid)
	UiPop()
end

local function pxPerM(pos)
	local right = TransformToParentVec(GetCameraTransform(), Vec(1, 0, 0))
	local x1, y1 = UiWorldToPixel(pos)
	local x2, y2 = UiWorldToPixel(VecAdd(pos, right))
	return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local function drawPose(pose, a, col, s)
	local ppm = pxPerM(pose.head)
	local wid = math.max(2, ppm * 0.12 * (0.8 + 0.4 * (s or 1)))
	for pass = 1, 2 do
		local w = pass == 1 and wid * 2.6 or wid
		UiColor(col[1], col[2], col[3], pass == 1 and a * 0.25 or a)
		for s = 1, #pose.segs do
			local x1, y1, d1 = UiWorldToPixel(pose.segs[s][1])
			local x2, y2, d2 = UiWorldToPixel(pose.segs[s][2])
			if d1 > 0.1 and d2 > 0.1 then uiLine(x1, y1, x2, y2, w) end
		end
		local hx, hy, hd = UiWorldToPixel(pose.head)
		if hd > 0.1 then
			UiPush()
			UiTranslate(hx, hy)
			UiAlign("center middle")
			UiCircle(math.max(3, ppm * 0.13) * (pass == 1 and 1.8 or 1))
			UiPop()
		end
	end
end

-- outlines of the pinged bodies (client.tick: DrawBodyOutline draws the next frame)
local function outlinePings(now)
	for i = 1, #pings do
		local p = pings[i]
		if p.body or p.bodies then
			local fade = 1 - (now - p.t0) / p.life
			if fade > 0 then
				local a = fade * (0.35 + 0.65 * (p.s or 1))
				for _, b in ipairs(p.bodies or {p.body}) do              -- (a monster: every part of its model)
					DrawBodyOutline(b, p.col[1], p.col[2], p.col[3], a)
					DrawBodyHighlight(b, a * 0.4)
				end
			end
		end
	end
end

-- an explosion on screen: a quick pop easing out, a soft layered glow, a white-hot core, tapered rays (orange to deep
-- red), a thin shockwave ring running ahead, sparks flying out
local function drawBurst(p, age, fade)
	local sx, sy, dist = UiWorldToPixel(p.pos)
	if dist <= 0.1 then return end
	local base = math.min(260, pxPerM(p.pos) * p.size)            -- (capped: up close the rays turned into slabs)
	local e = 1 - (1 - math.min(1, age / 0.35)) ^ 3                -- (ease-out pop)
	local R = base * (0.35 + 0.65 * e)
	local a = fade * (0.45 + 0.55 * (p.s or 1))
	UiPush()
	UiTranslate(sx, sy)
	UiAlign("center middle")
	for k = 1, 5 do                                                -- the glow: wide and faint to tight and bright
		UiColor(0.85, 0.12 + 0.05 * k, 0.05, a * 0.06 * k)
		UiCircle(R * (1.15 - k * 0.17))
	end
	local hot = math.max(0, 1 - age / 0.6)                          -- the core, white-hot then gone
	if hot > 0 then
		UiColor(1, 0.95, 0.75, a * hot)
		UiCircle(R * 0.22 * (0.6 + 0.4 * hot))
	end
	local e2 = math.min(1, age / 0.6)                               -- the shockwave ring
	if e2 < 1 then
		UiColor(1, 0.55, 0.3, a * (1 - e2) * 0.8)
		UiCircleOutline(R * (0.9 + 1.0 * e2), math.max(1, 4 * (1 - e2)))
	end
	UiPop()
	local w = math.max(1.5, math.min(6, base * 0.04))
	for _, r in ipairs(p.burst) do                                  -- tapered rays: three pieces, thinner and fainter out
		local cx, cy = math.cos(r.ang), math.sin(r.ang)
		local L = R * r.len
		local pieces = {{0.12, 0.5, 1.0, 1.0, {1, 0.6, 0.2}}, {0.5, 0.8, 0.6, 0.7, {1, 0.35, 0.1}}, {0.8, 1.0, 0.3, 0.4, {0.85, 0.15, 0.08}}}
		for _, pc in ipairs(pieces) do
			UiColor(pc[5][1], pc[5][2], pc[5][3], a * pc[4])
			uiLine(sx + cx * L * pc[1], sy + cy * L * pc[1], sx + cx * L * pc[2], sy + cy * L * pc[2], w * pc[3])
		end
	end
	for _, sp in ipairs(p.sparks) do                                -- sparks flying out, fading
		local d = R * (0.4 + 1.2 * e) * sp.k
		UiPush()
		UiTranslate(sx + math.cos(sp.ang) * d, sy + math.sin(sp.ang) * d)
		UiAlign("center middle")
		UiColor(1, 0.7, 0.3, a * (1 - e2 * 0.7))
		UiCircle(math.max(1.5, base * 0.025))
		UiPop()
	end
end

local function drawGun(p, age, fade)
	local sx, sy, dist = UiWorldToPixel(p.pos)
	if dist <= 0.1 then return end
	local m = pxPerM(p.pos)
	local a = fade * (0.4 + 0.6 * (p.s or 1))
	UiPush()
	UiTranslate(sx, sy)
	UiColor(p.col[1], p.col[2], p.col[3], a)
	UiAlign("left middle")
	UiRect(math.max(6, m * 0.32), math.max(2, m * 0.07))          -- the barrel
	UiAlign("left top")
	UiRect(math.max(3, m * 0.08), math.max(4, m * 0.16))          -- the grip
	if age < 0.25 then                                            -- the muzzle flash
		UiTranslate(math.max(6, m * 0.32), 0)
		UiAlign("center middle")
		UiColor(1, 0.85, 0.4, a * (1 - age / 0.25))
		UiCircle(math.max(4, m * 0.12))
	end
	UiPop()
end

local function drawPings(now)
	UiPush()
	for i = #pings, 1, -1 do
		local p = pings[i]
		local age = now - p.t0
		if age > p.life then
			table.remove(pings, i)
		elseif p.body or p.bodies then
			-- (outlined in client.tick)
		elseif p.burst then
			drawBurst(p, age, 1 - age / p.life)
		elseif p.gun then
			drawGun(p, age, 1 - age / p.life)
		else
			local fade = 1 - age / p.life
			if p.track and IsPlayerValid(p.track) then           -- (keeps the last pose if one can't be read)
				p.pose = capturePose(p.track, Vec(0, 0, 0)) or p.pose
			end
			if p.pose then
				local a = p.track and (fade < 0.3 and fade / 0.3 or 1) or fade ^ 1.5    -- (a reveal stays bright, then fades)
				local st = p.s or 1                                                  -- (weak: faint and flickering)
				drawPose(p.pose, a * (0.3 + 0.7 * st) * (1 - (1 - st) * 0.6 * math.random()), p.col, st)
				if p.nameAt and IsPlayerValid(p.who) then           -- their name, where the noise was, fading with it
					local nx, ny, nd = UiWorldToPixel(p.nameAt)
					if nd > 0.1 then
						UiPush()
						UiTranslate(nx, ny)
						UiAlign("center bottom")
						UiFont("bold.ttf", 22)
						UiColor(1, 0.35, 0.3, a * (0.45 + 0.55 * st))
						UiText(GetPlayerName(p.who))
						UiPop()
					end
				end
			else
				local sx, sy, dist = UiWorldToPixel(p.pos)
				if dist > 0.1 then
					UiPush()
					UiTranslate(sx, sy)
					UiAlign("center middle")
					UiColor(p.col[1], p.col[2], p.col[3], fade * (0.3 + 0.6 * (p.s or 1)))
					UiCircleOutline(pxPerM(p.pos) * (0.3 + age * 2.5 * (0.6 + p.size)), 3)   -- (louder: a bigger ripple)
					UiPop()
				end
			end
		end
	end
	UiPop()
end

----- TEST dummies (the vision probe's J key; none in the game mode) -----

local function placeDummy(now)
	local c = (on and cam) or GetCameraTransform()
	local dir = TransformToParentVec(c, Vec(0, 0, -1))
	rejectPeople()
	ehQueryMask()
	local hit, dist = QueryRaycast(c.pos, dir, 60)
	if not hit then
		dummies = {}
		return
	end
	local at = VecAdd(c.pos, VecScale(dir, dist))
	local feet = GetPlayerTransform(GetLocalPlayer()).pos
	local pose = capturePose(0, VecSub(at, feet)) or standPose(at)
	dummies[#dummies + 1] = {pos = at, pose = pose, nextNoise = now + 4 + math.random() * 5}
	if on then
		addPose(pose, noiseStrength(VecLength(VecSub(at, c.pos)), 35, 0.5), GLOW)
		PlaySound(snd.voice, at, 0.9, false)
	end
end

local function dummiesTick(now, eye)
	for i = 1, #dummies do
		local d = dummies[i]
		if now >= d.nextNoise then
			d.nextNoise = now + 4 + math.random() * 6
			local dist = VecLength(VecSub(d.pos, eye))
			if dist <= STEP_REACH_RUN then
				addPose(d.pose, noiseStrength(dist, STEP_REACH_RUN, 0.6), GLOW)
				PlaySound(snd.step, d.pos, 0.9, false)
			end
		end
	end
end

----- hearing (client) -----

-- standing still, the monster hears the hearts of nearby humans: they fade in after HEART_STILL, louder the closer,
-- racing within HEART_FAST_R; sound only (nothing is drawn); moving stops them
local function heartbeats(now, dt, me, eye)
	local v = GetPlayerVelocity(me)
	local still = math.sqrt(v[1] * v[1] + v[3] * v[3]) < 0.5      -- (horizontal: a standing body's jitter read as moving)
	heart.still = still and heart.still + dt or 0
	if heart.still >= HEART_STILL then heart.level = math.min(1, heart.level + dt / HEART_FADE)
	else heart.level = math.max(0, heart.level - dt / 0.5) end
	if heart.level <= 0 then return end
	for i = 1, #people do
		local p = people[i]
		if GetPlayerHealth(p) > 0 then
			local pos = VecAdd(GetPlayerTransform(p).pos, Vec(0, 1.3, 0))
			local d = VecLength(VecSub(pos, eye))
			if d <= HEART_R and now >= (heart.next[p] or 0) then
				heart.next[p] = now + (d < HEART_FAST_R and 0.5 or 0.9) * (0.95 + 0.1 * math.random())
				local dir = VecScale(VecSub(pos, eye), 1 / math.max(d, 0.01))    -- (at its ears from their side: played
				PlaySound(snd.heart, VecAdd(eye, VecScale(dir, 1.5)), heart.level * (1 - d / HEART_R) ^ 0.7, false)   -- where they stand it faded out with the distance)
			end
		end
	end
end

-- the server's noise events (humans' tools, vehicles, Proximity Comms lines) within their reach: what made it is
-- highlighted (talking: the speaker's pose)
local function hearNoises(eye)
	local q = shared.ehNoise
	if not q or not q.seq then noiseSeen = noiseSeen or 0; return end     -- (none yet: hear the very first one)
	if not noiseSeen or q.seq < noiseSeen then noiseSeen = q.seq end      -- (older than the view: not heard)
	for _, e in ipairs(q.list or {}) do
		if e.seq > noiseSeen then
			local pos = Vec(e.x, e.y, e.z)
			local d = VecLength(VecSub(pos, eye))
			if d <= e.r then
				local st = noiseStrength(d, e.r, e.loud)
				local body = 0                                           -- the thing that made it: the car, the gun
				if IsPlayerValid(e.p) and e.clip ~= "voice" then         -- (a voice - talking, a cry of pain, a revive - is the
				                                                     --  person: not their tool - AgeOfAlgorithms: a hurt human's wrench lit up)
					local veh = GetPlayerVehicle(e.p)
					if veh ~= 0 then body = GetVehicleBody(veh) else body = GetToolBody(e.p) end
				end
				if body ~= 0 then addBodyPing(body, st, GLOW)
				elseif e.clip == "gun" then addGunPing(e.p, pos, st) end
				if body == 0 or e.kind:sub(1, 5) == "tool_" then
					addPose((IsPlayerValid(e.p) and capturePose(e.p, Vec(0, 0, 0))) or standPose(pos), st, GLOW, nil, nil,
						IsPlayerValid(e.p) and not ehIsMonster(e.p) and e.p or nil)
				end
				if EH_HEARD then EH_HEARD(e.kind .. (body ~= 0 and "+body" or ""), d, st) end
			end
		end
	end
	noiseSeen = q.seq
end

-- a human detected by the monster's pulse: a warning for DETECT_SHOW s and a sting
DETECT_SHOW = 3.0
local function detectTick(me, now)
	local d = shared.ehDetect
	if not d or d.n == detected.n then return end
	if detected.n ~= nil then
		for _, q in ipairs(d.list or {}) do
			if q == me then
				detected.t = now
				PlaySound(snd.echo, GetPlayerTransform(me).pos, 1.0, false, 0.8)
			end
		end
	end
	detected.n = d.n
end

local function drawDetected(now)
	local age = now - detected.t
	if age > DETECT_SHOW then return end
	local a = age < 0.15 and age / 0.15 or math.min(1, (DETECT_SHOW - age) / 0.6)
	UiPush()
	UiColor(0.6, 0.05, 0.05, 0.22 * a * (0.7 + 0.3 * math.sin(age * 18)))   -- a red pulse over the screen
	UiRect(UiWidth(), UiHeight())
	UiTranslate(UiCenter(), UiHeight() * 0.28)
	UiAlign("center middle")
	UiFont("bold.ttf", 44)
	UiColor(1, 0.35, 0.3, a)
	UiText("A CLICKER SENSED YOU")
	UiTranslate(0, 46)
	UiFont("bold.ttf", 24)
	UiColor(1, 0.85, 0.8, a * 0.9)
	UiText("It knows where you are. Move.")
	UiPop()
end

-- A human's flashlight: when the HOST is a monster, its SetPlayerHidden on a human (they are never drawn for it) also
-- turns that human's flashlight off on the human's own machine - F did nothing (4-player test: the host the monster,
-- every client human's F dead; a client the monster, everyone's F fine; hiding not done on the host: F fine). So each
-- human machine keeps its own flashlight state from the flashlight key and switches the light itself.
-- The state reaches the other machines through the server (shared.ehFlash): the engine's own wasn't toggled either,
-- so others never saw it (AgeOfAlgorithms: client humans couldn't see each other's flashlights).
local flash = {on = false, sent = nil}
function flashlightTick(me)
	if InputPressed("flashlight") then flash.on = not flash.on end
	if GetPlayerHealth(me) <= 0 then flash.on = false end
	local fl = GetFlashlight(me)
	if fl and fl ~= 0 and IsHandleValid(fl) then SetLightEnabled(fl, flash.on) end
	if flash.sent ~= flash.on then flash.sent = flash.on; ServerCall("server.ehFlash", me, flash.on) end
end

-- (a human machine, every frame) the other humans' flashlights as they have them
local function remoteFlashlights(me)
	local st = type(shared.ehFlash) == "table" and shared.ehFlash or {}
	for p in Players() do
		if p ~= me and not ehIsMonster(p) then
			local fl = GetFlashlight(p)
			if fl and fl ~= 0 and IsHandleValid(fl) then SetLightEnabled(fl, st[p] == true and GetPlayerHealth(p) > 0) end
		end
	end
end

local flashPub = {}
function server.ehFlash(p, on)
	flashPub[p] = on and true or nil
	local c = {}
	for k, v in pairs(flashPub) do if IsPlayerValid(k) then c[k] = v end end
	shared.ehFlash = c
end

-- the monster's view on / off on this machine
function ehViewSet(v)
	if on == v then return end
	on = v
	if on then
		ppSave()
		noiseSeen = nil
		voidSpawn()
	else
		ppApplySaved(); saved = nil; pings = {}; pending = {}
		ehUnhideTagged()
		SetBool(PP_REG .. ".saved", false)
		voidDelete()
	end
end

function ehClientInit()
	leftovers()
	snd.step = LoadSound("MOD/snd/hear_step0.ogg")             -- (the TEST dummies' sounds: they are not real players)
	snd.voice = LoadSound("MOD/snd/hear_voice0.ogg")
	snd.clickPulse = LoadSound("MOD/snd/clicker_pulse0.ogg")    -- (one of 3 at random; Dia takes: tools/audio/make_dia_sounds.py)
	snd.echo = LoadSound("MOD/snd/echo0.ogg")
	snd.mstep = LoadSound("MOD/snd/monster_step0.ogg")
	snd.heart = LoadSound("MOD/snd/heart0.ogg")
	snd.mclick = LoadSound("MOD/snd/monster_click0.ogg")
	snd.mhiss = LoadSound("MOD/snd/monster_hiss0.ogg")
	snd.breathSoft = LoadSound("MOD/snd/breath_soft0.ogg")      -- (its breathing: 3 of each, at random)
	snd.breathHard = LoadSound("MOD/snd/breath_hard0.ogg")
	snd.alert = LoadSound("MOD/snd/pulse_hit0.ogg")             -- (the pulse found someone)
	snd.landHit = LoadSound("dirt/hit-l0.ogg")                   -- (a landing: the game's big dirt hit, a landing thump
	snd.landDirt = LoadSound("dirt/land0.ogg")                   -- (one of 9 at random) and a flesh impact, layered)
	snd.mswipe = LoadSound("MOD/snd/monster_swipe0.ogg")
	snd.mgrab = LoadSound("MOD/snd/monster_grab0.ogg")
	snd.flesh = LoadSound("flesh-impact0.ogg")                    -- (the game's own)
end

function ehClientDestroy()
	ehViewSet(false)
	monsterVisualClear()
end

-- every frame: the monster's footfalls / calls (every machine); the monster's view and hearing (its machine)
local function asList(ms)
	if type(ms) == "table" then return ms end
	return (ms and ms ~= 0) and {ms} or {}
end

local function inList(l, p)
	for i = 1, #l do if l[i] == p then return true end end
	return false
end

function ehClientTick(dt, ms)
	local now = GetTime()
	local me = GetLocalPlayer()
	listPeople(me)
	ehCombatClientTick()                                         -- (eh_combat.lua: the hit boxes, for rays)
	ehViewSet(inList(asList(ms), me))
	if not on then detectTick(me, now) end
	camDip = mantleClientTick(not on)                  -- (view on: the monster camera carries the dip)
	monsterSounds(dt)
	local vol, pos = GetLastSound()
	if vol > 0 then lastVol, lastVolT = vol, now end
	if not on then flashlightTick(me); remoteFlashlights(me) end   -- (a human: its flashlight and the others', see flashlightTick)
	if not on then                                               -- not a monster here: a human's view, whatever the host's
		local pp = shared.ehPP                                   -- (a monster host's darkening reaches every machine)
		if type(pp) == "table" and pp.gamma then
			for i = 1, #PP_KEYS do if pp[PP_KEYS[i]] then SetPostProcessingProperty(PP_KEYS[i], pp[PP_KEYS[i]]) end end
			SetPostProcessingProperty("colorbalance", pp.cbr or 1, pp.cbg or 1, pp.cbb or 1)
		end
		return
	end
	SetBool("proxchat.hideBubbles", true)                        -- (Proximity Comms: no speech bubbles or "..." over the
	                                                             --  hidden humans' heads on a monster's screen - AgeOfAlgorithms;
	                                                             --  it hears talk as highlights; set every frame)

	if ehMapOpen() then                                          -- the map (Tab), like any player (AgeOfAlgorithms): its camera
		if panelSet.active then                                  -- free, the void box and
			for _, b in ipairs(panels) do SetBodyTransform(b, Transform(Vec(0, -500, 0))) end
			panelSet.active = nil
		end
		if light then SetProperty(light, "intensity", 0) end      -- the fog out of the way, the level's own look
		ppApplySaved()
		hideHumans()                                             -- (humans still never drawn)
		return
	end
	local eye = monsterCamera(me, dt)
	fogApply(eye, (EH_BENCH and EH_BENCH.clear) or pulseClear(now), dt)
	hideHumans()

	-- world sounds (breaking, debris, impacts, explosions) are highlighted as far as they are loud: a ripple there
	-- (explosions also a starburst); at most one every 0.12 s
	if vol >= HEAR_MIN and now - lastRipT > 0.12 then
		local reach = (vol >= BURST_VOL) and math.min(BOOM_MAX, BOOM_BASE + BOOM_PER_VOL * vol) or math.min(HEAR_MAX, vol * HEAR_PER_VOL)
		local d = VecLength(VecSub(pos, eye))
		if d <= reach then
			lastRipT = now
			addRipple(pos, RIPPLE, vol, noiseStrength(d, reach, math.min(1, vol / 1.5)))
			if vol >= BURST_VOL then addBurst(pos, vol, noiseStrength(d, reach, 1)) end
			if EH_HEARD then EH_HEARD(string.format("world%.2f", vol), d, noiseStrength(d, reach, math.min(1, vol / 1.5))) end
		end
	end

	-- other players' footsteps, silent while crouched (the game mode will do this on the server)
	for i = 1, #people do
		local p = people[i]
		local v = GetPlayerVelocity(p)
		local speed = math.sqrt(v[1] * v[1] + v[3] * v[3])
		local crouched = GetPlayerCrouch(p) > 0.5
		if speed > STEP_SPEED and not crouched and IsPlayerGrounded(p) and GetPlayerHealth(p) > 0 then
			if now >= (steps[p] or 0) then
				local running = speed > 5
				steps[p] = now + (running and 0.35 or 0.55)
				local at = GetPlayerTransform(p).pos
				local reach = running and STEP_REACH_RUN or STEP_REACH_WALK
				local dist = VecLength(VecSub(at, eye))
				if dist <= reach then
					local st = noiseStrength(dist, reach, running and 0.6 or 0.3)
					addPose(capturePose(p, Vec(0, 0, 0)) or standPose(at), st, GLOW, nil, nil, p)
					if EH_HEARD then EH_HEARD(running and "step_run" or "step_walk", dist, st) end
				end
			end
		end
	end

	-- echo pulse on F, the flashlight key - a monster has no flashlight (AgeOfAlgorithms: "kinda like a flashlight"); the action
	-- (rebound keys) or the key itself
	if (InputPressed("flashlight") or InputPressed("f")) and now >= pulseReady and ehCanAct() then startPulse(now, eye) end
	pulseTick(now)
	waveTick(now, eye, dt)

	hearNoises(eye)
	heartbeats(now, dt, me, eye)
	dummiesTick(now, eye)
	outlinePings(now)
end

-- where a heard sound came from, easy to track (AgeOfAlgorithms: the direction alone wasn't enough): a soft aura in the sound's
-- colour around its source while its highlight lasts, and off screen a small arrow at the screen's edge pointing there
local function pingSource(p)
	if p.pose and p.pose.head then return p.pose.head end
	if p.bodies or p.body then
		local b = p.body or p.bodies[1]
		if b and IsHandleValid(b) then
			local lo, hi = GetBodyBounds(b)
			if not lo or not hi then return GetBodyTransform(b).pos end
			if p.bodies then                                  -- (a monster: the middle of its whole model)
				for _, q in ipairs(p.bodies) do
					if IsHandleValid(q) then
						local a, c = GetBodyBounds(q)
						if a and c then lo, hi = Vec(math.min(lo[1], a[1]), math.min(lo[2], a[2]), math.min(lo[3], a[3])),
							Vec(math.max(hi[1], c[1]), math.max(hi[2], c[2]), math.max(hi[3], c[3])) end
					end
				end
			end
			return VecLerp(lo, hi, 0.5)
		end
		return nil
	end
	return p.pos
end

local function drawPingAuras(now)
	local w, h, m = UiWidth(), UiHeight(), 50
	for i = 1, #pings do
		local p = pings[i]
		local age = now - p.t0
		if not p.track and age <= p.life then               -- (a pulse reveal has its own marker)
			local at = pingSource(p)
			if at then
				local fade = 1 - age / p.life
				local a = fade * (0.25 + 0.55 * (p.s or 1))
				local c = p.col
				local x, y, dist = UiWorldToPixel(at)
				local off = dist <= 0 or x < m or x > w - m or y < m or y > h - m
				UiPush()
				if not off then
					local r = clamp(pxPerM(at) * 0.9, 16, 110) * (1 + 0.12 * math.sin((now - p.t0) * 9))
					UiTranslate(x, y)
					UiAlign("center middle")
					UiColor(c[1], c[2], c[3], a * 0.16)
					UiCircle(r)
					UiColor(c[1], c[2], c[3], a * 0.8)
					UiCircleOutline(r, 2)
				else
					local cx, cy = w / 2, h / 2
					local dx, dy = x - cx, y - cy
					if dist <= 0 then dx, dy = -dx, -dy end
					if math.abs(dx) < 1 and math.abs(dy) < 1 then dy = 1 end
					local k = math.min((w / 2 - m) / math.max(math.abs(dx), 1e-3), (h / 2 - m) / math.max(math.abs(dy), 1e-3))
					UiTranslate(cx + dx * k, cy + dy * k)
					UiRotate(-math.deg(math.atan2(dy, dx)))
					UiColor(c[1], c[2], c[3], a)
					for _, side in ipairs({1, -1}) do              -- (a small arrowhead pointing out)
						UiPush()
						UiRotate(side * 145)
						UiAlign("left middle")
						UiRect(14, 4)
						UiPop()
					end
				end
				UiPop()
			end
		end
	end
end

-- the humans this pulse revealed, impossible to miss (AgeOfAlgorithms): on screen a pulsing aura around each with its distance,
-- off screen (or behind) an arrow at the screen's edge pointing the way, with the distance
-- (client) the humans this machine's monster has revealed by echolocation right now: {[player] = true}
function ehRevealedPlayers()
	local set, now = {}, GetTime()
	for _, r in ipairs(reveals) do
		if r.player and now - r.t0 <= REVEAL_LIFE then set[r.player] = true end
	end
	return set
end

local function drawReveals(now)
	local camPos = GetCameraTransform().pos
	for i = #reveals, 1, -1 do
		local r = reveals[i]
		local age = now - r.t0
		if age > REVEAL_LIFE then
			table.remove(reveals, i)
		else
			if r.player and IsPlayerValid(r.player) and GetPlayerHealth(r.player) > 0 then r.pos = GetPlayerTransform(r.player).pos end
			local at = VecAdd(r.pos, Vec(0, 1.0, 0))
			local d = VecLength(VecSub(at, camPos))
			local a = math.min(1, (REVEAL_LIFE - age) / 0.6) * math.min(1, age / 0.08)
			local x, y, dist = UiWorldToPixel(at)
			local w, h, m = UiWidth(), UiHeight(), 70
			local off = dist <= 0 or x < m or x > w - m or y < m or y > h - m
			local c = REVEAL_COL
			UiPush()
			if not off then                                      -- the aura: rings beating out from them
				local base = clamp(pxPerM(at) * 1.3, 26, 170)
				UiTranslate(x, y)
				UiAlign("center middle")
				UiColor(c[1], c[2], c[3], a * 0.12)
				UiCircle(base * 1.1)
				for k = 0, 1 do
					local ph = ((now - r.t0) * 1.6 + k * 0.5) % 1
					UiColor(c[1], c[2], c[3], a * (1 - ph) * 0.9)
					UiCircleOutline(base * (0.8 + 0.9 * ph), 4)
				end
				UiColor(c[1], c[2], c[3], a)
				UiCircleOutline(base * 0.75, 3)
				UiTranslate(0, base + 16)
				UiFont("bold.ttf", 18)
				UiText(string.format("%d m", math.floor(d + 0.5)))
			else                                                 -- the pointer at the edge, on their side of the view
				local cx, cy = w / 2, h / 2
				local dx, dy = x - cx, y - cy
				if dist <= 0 then dx, dy = -dx, -dy end
				if math.abs(dx) < 1 and math.abs(dy) < 1 then dy = 1 end
				local k = math.min((w / 2 - m) / math.max(math.abs(dx), 1e-3), (h / 2 - m) / math.max(math.abs(dy), 1e-3))
				local px, py = cx + dx * k, cy + dy * k
				local ang = math.deg(math.atan2(dy, dx))
				local pulse = 1 + 0.15 * math.sin(now * 10)
				UiTranslate(px, py)
				UiAlign("center middle")
				UiColor(0, 0, 0, a * 0.5)
				UiCircle(30 * pulse)
				UiColor(c[1], c[2], c[3], a)
				UiCircleOutline(30 * pulse, 3)
				UiPush()                                         -- an arrowhead: two bars meeting at the tip
				UiRotate(-ang)
				UiTranslate(14, 0)
				for _, side in ipairs({1, -1}) do
					UiPush()
					UiRotate(side * 140)
					UiAlign("left middle")
					UiRect(22, 6)
					UiPop()
				end
				UiPop()
				UiTranslate(0, 46)
				UiFont("bold.ttf", 18)
				UiText(string.format("%d m", math.floor(d + 0.5)))
			end
			UiPop()
		end
	end
end

-- standing still HEART_GLOW_STILL s: every HEART_GLOW_EVERY s a short faint pulse of red glow toward each human within
-- HEART_GLOW_R - very wide, fainter the farther, centred on a point scattered around them anew each pulse, at the
-- screen's edge when off screen or behind (AgeOfAlgorithms)
-- (client) seconds this machine's monster has stood still (the heartbeats come at HEART_STILL)
function ehHeartStill() return heart.still end

local function drawHeartGlow(now)
	if heart.still < HEART_GLOW_STILL or not cam then heart.glowN = nil; return end
	local since = heart.still - HEART_GLOW_STILL
	local n = math.floor(since / HEART_GLOW_EVERY)
	local age = since - n * HEART_GLOW_EVERY
	if age > HEART_GLOW_LEN then return end
	if heart.glowN ~= n then                                     -- a new pulse: where each human is now, scattered, fixed
		heart.glowN, heart.spots = n, {}
		for i = 1, #people do
			local p = people[i]
			if GetPlayerHealth(p) > 0 then
				local real = VecAdd(GetPlayerTransform(p).pos, Vec(0, 1.2, 0))
				local d = VecLength(VecSub(real, cam.pos))
				if d <= HEART_GLOW_R then
					local r = math.max(6, math.min(60, d * HEART_GLOW_SCATTER)) * math.sqrt(math.random())
					local a = math.random() * 2 * math.pi
					heart.spots[#heart.spots + 1] = VecAdd(real, Vec(math.cos(a) * r, (math.random() - 0.5) * r * 0.2, math.sin(a) * r))
				end
			end
		end
	end
	local env = math.sin(math.pi * age / HEART_GLOW_LEN) ^ 2       -- (0 at both ends: in, then out to nothing)
	local w, h, m = UiWidth(), UiHeight(), 40
	for _, at in ipairs(heart.spots or {}) do
		local d = VecLength(VecSub(at, cam.pos))
		local x, y, dist = UiWorldToPixel(at)
		if dist <= 0 or x < m or x > w - m or y < m or y > h - m then
			local cx, cy = w / 2, h / 2
			local dx, dy = x - cx, y - cy
			if dist <= 0 then dx, dy = -dx, -dy end
			if math.abs(dx) < 1 and math.abs(dy) < 1 then dy = 1 end
			local k = math.min((w / 2 - m) / math.max(math.abs(dx), 1e-3), (h / 2 - m) / math.max(math.abs(dy), 1e-3))
			x, y = cx + dx * k, cy + dy * k
		end
		local near = math.max(0, 1 - d / HEART_GLOW_R)
		local r = 350 + 800 * near                                  -- (huge: a wash of colour, not a marker)
		local c = HEART_COL
		UiPush()
		UiTranslate(x, y)
		UiAlign("center middle")
		for k = 1, 6 do                                             -- (soft edges: barely there)
			UiColor(c[1], c[2], c[3], env * 0.0025 * k * (0.25 + 0.75 * near))   -- (a little deeper than 0.0018 - AgeOfAlgorithms)
			UiCircle(r * (1.3 - k * 0.15))
		end
		UiPop()
	end
end

-- the stamina bar (bottom centre): shown while running or not full; red while exhausted
local function drawStamina()
	local sm = type(shared.ehStam) == "table" and shared.ehStam[GetLocalPlayer()] or nil
	if not sm then return end
	local st, run, tired = sm.s, sm.run, sm.ex
	if st >= 0.999 and not run then return end
	UiPush()
	UiAlign("center middle")
	UiTranslate(UiCenter(), UiHeight() - 70)
	UiColor(0, 0, 0, 0.5)
	UiRect(324, 16)
	UiAlign("left middle")
	UiTranslate(-160, 0)
	if tired then UiColor(0.85, 0.2, 0.15, 0.9) else UiColor(0.85, 0.88, 0.9, 0.85) end
	UiRect(320 * math.max(0, math.min(1, st)), 10)
	UiPop()
end

-- the map is open (or fading) on this machine
function ehMapOpen() return GetBool("game.map.enabled") or GetFloat("game.map.fade") > 0 end

function ehClientDraw()
	ehCombatDraw(on)                                             -- (eh_combat.lua: its HP, the stun)
	if not on then drawDetected(GetTime()); return end
	if ehMapOpen() then return end                               -- (its markers belong to its own view, not the map)
	local now = GetTime()
	drawHeartGlow(now)
	drawPings(now)
	drawPingAuras(now)
	drawScanRings(now)
	drawReveals(now)
	drawStamina()
	UiPush()                                                     -- a crosshair: where its claws and grab aim (AgeOfAlgorithms)
	UiTranslate(UiCenter(), UiMiddle())
	UiAlign("center middle")
	UiColor(0, 0, 0, 0.5)
	UiCircle(4)
	UiColor(1, 1, 1, 0.85)
	UiCircle(2.5)
	UiPop()
end

function ehClientRender(dt, ms)
	if EH_BENCH and EH_BENCH.nomodel then ms = {} end
	monsterVisualRender(asList(ms), type(shared.ehScream) == "table" and shared.ehScream or {}, dt)
end

function ehClientPostUpdate(dt)
	mantleClientPostUpdate()
	ehCombatClientPostUpdate(dt)
end

----- server -----

MONSTER_REACH = 2.6   -- m: the monster mantles at its chest height (~3.6 m tall; a human's ribcage: 1.4)
function mantleReach(p)
	if ehIsDown and ehIsDown(p) then return 0 end                -- (the downed crawl: no climbing)
	return ehIsMonster(p) and MONSTER_REACH or MANTLE_MAX_RISE
end

local weatherSet = ""
local noiseQ = {seq = 0, list = {}}
local nextHold, nextVeh = {}, {}

local emitNoise
-- (eh_combat.lua) a noise the monsters hear and see: a hurt human's cry, a revive
function ehEmitNoise(p, kind, pos, r, loud, clip) emitNoise(p, kind, pos, r, loud, clip) end

function emitNoise(p, kind, pos, r, loud, clip)
	noiseQ.seq = noiseQ.seq + 1
	local l = noiseQ.list
	l[#l + 1] = {seq = noiseQ.seq, p = p, kind = kind, x = pos[1], y = pos[2], z = pos[3], r = r, loud = loud, clip = clip}
	while #l > 16 do table.remove(l, 1) end
	local copy = {}
	for i = 1, #l do copy[i] = l[i] end
	shared.ehNoise = {seq = noiseQ.seq, list = copy}          -- (whole tables: nested shared writes are unverified)
end

-- humans' tools and vehicles become noises with a reach (every human: not the monsters)
-- in water: the body's middle under the surface (as the game's own swimming animation tests it)
function ehInWater(p)
	return IsPointInWater(VecAdd(GetPlayerTransform(p).pos, Vec(0, 0.8, 0)))
end

local wasInWater, nextSwim = {}, {}
local function humanNoises(monsters)
	local now = GetTime()
	for q in Players() do
		if not monsters[q] and GetPlayerHealth(q) > 0 then
			local pos = GetPlayerTransform(q).pos
			local veh = GetPlayerVehicle(q)
			if veh ~= 0 then
				wasInWater[q] = nil
				if now >= (nextVeh[q] or 0) then
					nextVeh[q] = now + VEH_EVERY
					local v = GetBodyVelocity(GetVehicleBody(veh))
					local sp = math.sqrt(v[1] * v[1] + v[2] * v[2] + v[3] * v[3])
					local vp = GetVehicleTransform(veh).pos
					local boat = IsPointInWater(vp) or IsPointInWater(VecAdd(vp, Vec(0, -0.6, 0)))
					local r = boat and math.min(BOAT_REACH_MAX, BOAT_REACH_MIN + BOAT_REACH_PER * sp)
						or math.min(VEH_REACH_MAX, VEH_REACH_MIN + VEH_REACH_PER * sp)
					emitNoise(q, string.format(boat and "boat%.0f" or "vehicle%.0f", sp), vp, r, math.min(1, (boat and 0.6 or 0.3) + sp / 30), "engine")
				end
			else
				local wet = ehInWater(q)                             -- water (AgeOfAlgorithms): getting in splashes loudly, swimming is
				if wet and not wasInWater[q] then                     --  loud, floating still makes no noise
					emitNoise(q, "splash", pos, SPLASH_REACH, 1.0, "voice")
					nextSwim[q] = now + SWIM_EVERY
				elseif wet and now >= (nextSwim[q] or 0) then
					local v = GetPlayerVelocity(q)
					local sp = math.sqrt(v[1] * v[1] + v[3] * v[3])
					if sp > 0.6 then
						nextSwim[q] = now + SWIM_EVERY
						emitNoise(q, "swim", pos, math.min(SWIM_REACH_MAX, SWIM_REACH_MIN + SWIM_REACH_PER * sp), 0.7, "voice")
					end
				end
				wasInWater[q] = wet
				local tool = GetPlayerTool(q)
				local n = TOOL_NOISE[tool] or ((tool ~= "" and tool ~= "none") and TOOL_DEFAULT or nil)
				if n then
					local fire = false
					if n.hold then
						if InputDown("usetool", q) and now >= (nextHold[q] or 0) then nextHold[q] = now + HOLD_EVERY; fire = true end
					else
						fire = InputPressed("usetool", q)
					end
					if fire then emitNoise(q, "tool_" .. tool, pos, n.r, n.loud, n.clip) end
				end
			end
		end
	end
end
local jumpT = -100

local saidSeenS = nil

-- Proximity Comms lines (the host's registry) become noise events with the chat's own radius for each line
local function chatNoises(monsters)
	local last = GetInt("proxchat.said.last")
	if not saidSeenS or last < saidSeenS then saidSeenS = last end
	for n = saidSeenS + 1, last do
		local k = "proxchat.said." .. (n % 16)
		local p = GetInt(k .. ".player")
		local mode = GetString(k .. ".mode")
		if not monsters[p] and mode ~= "global" and not GetBool(k .. ".lobby") and GetString(k .. ".channel") == "" then
			local pos = Vec(GetFloat(k .. ".x"), GetFloat(k .. ".y"), GetFloat(k .. ".z"))
			local loud = (mode == "whisper" and 0.2) or (mode == "yell" and 1.0) or 0.5
			emitNoise(p, "talk_" .. mode, pos, GetFloat(k .. ".radius"), loud, "voice")
		end
	end
	saidSeenS = last
end

-- a monster's scream (its pulse), asked by its client: everyone sees it, and the humans within its reach are told
-- they were detected (AgeOfAlgorithms)
local detectN = 0
local screamPub = {}
function server.ehScream(m)
	if not ehIsMonster(m) then m = shared.ehMonster or 0 end     -- (an old caller without the player: the first)
	if m == 0 or not IsPlayerValid(m) then return end
	screamPub[m] = (screamPub[m] or 0) + 1
	local copy = {}
	for k, v in pairs(screamPub) do copy[k] = v end
	shared.ehScream = copy
	local mp = GetPlayerTransform(m).pos
	local list = {}
	for q in Players() do
		if not ehIsMonster(q) and GetPlayerHealth(q) > 0 and VecLength(VecSub(GetPlayerTransform(q).pos, mp)) <= PULSE_RANGE then
			list[#list + 1] = q
		end
	end
	detectN = detectN + 1
	shared.ehDetect = {n = detectN, list = list}
end

function ehServerInit()
	mantleServerInit()
	ehPublishPP()                                                -- (the map's own look, before any monster darkens a view)
	for _, b in ipairs(FindBodies("ehhit", true) or {}) do Delete(b) end   -- (hit boxes an earlier run left)
end

function ehServerUpdate(dt)
	mantleServerUpdate(dt)
	ehCombatUpdate(dt)
end

-- the game's ready-made environments (copied from data/script/weather.lua setWeather; server only, for everyone):
-- a really dark night (AgeOfAlgorithms: "a lot darker"): the presets left the map's own sun, sky light and ambient on (a day map
-- stayed half lit) and let the auto-exposure brighten the dark up to 5x. Only lamps and flashlights light it now.
function nightDark()
	SetEnvironmentProperty("skyboxbrightness", 0.01)              -- (dark but readable for a human: night test screenshots on
	SetEnvironmentProperty("sunBrightness", 0)                    --  Isla Estocastica; its "pitch black" was the host monster's
	SetEnvironmentProperty("ambient", 0.15)                       --  darkening reaching every machine - ehPublishPP)
	SetEnvironmentProperty("constant", 0.0003, 0.0003, 0.0004)
	SetEnvironmentProperty("fogColor", 0.005, 0.005, 0.007)
	SetEnvironmentProperty("exposure", 1, 1.5)
end

-- sunny (day), sunset (evening), night, sunrise, foggy, rain, rainynight, snowy, snowynight
-- The HOST's post-processing reaches every machine (two-window test, the host the monster: the human's view had
-- saturation 0.000 - black and white, darkened; "the flashlight doesn't work", the night all black - AgeOfAlgorithms); a client's
-- stays its own. So the server publishes how a human's view should look (the map's own, then the time of day's) and
-- every machine that is not a monster puts it back every frame (ehClientTick).
function ehPublishPP()
	local pp = {}
	for i = 1, #PP_KEYS do pp[PP_KEYS[i]] = GetPostProcessingProperty(PP_KEYS[i]) end
	local r, g, b = GetPostProcessingProperty("colorbalance")
	pp.cbr, pp.cbg, pp.cbb = r or 1, g or 1, b or 1
	shared.ehPP = pp
end

function applyWeather(env)
	applyWeatherRaw(env)
	ehPublishPP()
end

function applyWeatherRaw(env)
	SetEnvironmentDefault()
	SetPostProcessingDefault()
	if env == "sunset" then
		SetEnvironmentProperty("skybox", "sunset.dds")
		SetEnvironmentProperty("skyboxtint", 1, 0.5, 0.2) 
		SetEnvironmentProperty("fogColor", 0.3, 0.2, 0.08) 
		SetEnvironmentProperty("fogParams", 80, 200, 1, 6)
		SetEnvironmentProperty("sunBrightness", 1)
		SetEnvironmentProperty("sunColorTint", 0.2, 0.3, 1) 
		SetEnvironmentProperty("sunFogScale", 1.0)
		SetEnvironmentProperty("sunGlare", 0.8)
		SetEnvironmentProperty("exposure", 1, 5)
		SetEnvironmentProperty("nightlight", false)
	elseif env == "sunny" then
		SetEnvironmentProperty("skybox", "day.dds")
		SetEnvironmentProperty("skyboxbrightness", 0.7)
		SetEnvironmentProperty("fogColor", 0.9, 0.9, 0.9) 
		SetEnvironmentProperty("fogParams", 50, 200, 0.9, 8) 
		SetEnvironmentProperty("sunBrightness", 4) 
		SetEnvironmentProperty("sunColorTint", 1, 0.8, 0.6)
		SetEnvironmentProperty("exposure",1, 5)
		SetEnvironmentProperty("sunFogScale",0.15)
		SetEnvironmentProperty("nightlight", false)
	elseif env == "night" then
		SetEnvironmentProperty("skybox", "cloudy.dds")
		SetEnvironmentProperty("fogParams", 20, 120, 0.9, 2)
		nightDark()
		SetEnvironmentProperty("ambience", "outdoor/night.ogg")
		SetEnvironmentProperty("nightlight", true)
		SetPostProcessingProperty("gamma", 0.9)
		SetPostProcessingProperty("bloom", 1.5)
	elseif env == "sunrise" then
		SetEnvironmentProperty("skybox", "cloudy.dds")
		SetEnvironmentProperty("skyboxtint", 1, 0.4, 0.2)
		SetEnvironmentProperty("skyboxbrightness", 0.6)
		SetEnvironmentProperty("fogColor", 1, 0.2, 0.1)
		SetEnvironmentProperty("fogParams", 30, 160, 0.95, 6)
		SetEnvironmentProperty("exposure", 1, 5)
		SetEnvironmentProperty("nightlight", true)
	elseif env == "foggy" then
		SetEnvironmentProperty("skybox", "cloudy.dds")
		SetEnvironmentProperty("skyboxtint", 1.0, 0.6, 0.4)
		SetEnvironmentProperty("fogType", "exp2")
		SetEnvironmentProperty("fogColor", 0.48, 0.46, 0.42)
		SetEnvironmentProperty("fogParams", 18.0, 0.3, 1.0, 0.22)
		SetEnvironmentProperty("fogHeightOffset", -31.5)
		SetEnvironmentProperty("exposure", 1, 5)
		SetEnvironmentProperty("wetness", 0.4)
		SetEnvironmentProperty("puddleamount", 0.3)
		SetEnvironmentProperty("nightlight", false)
		SetEnvironmentProperty("slippery", 0.1)
	elseif env == "rain" then
		SetEnvironmentProperty("skybox", "cloudy.dds")
		SetEnvironmentProperty("skyboxtint", 1.0, 0.6, 0.4)
		SetEnvironmentProperty("fogColor", 0.1, 0.1, 0.1)
		SetEnvironmentProperty("fogParams", 0, 70, 0.9, 1)
		SetEnvironmentProperty("exposure", 1, 5)
		SetEnvironmentProperty("wetness", 0.5)
		SetEnvironmentProperty("puddleamount", 0.5)
		SetEnvironmentProperty("puddlesize", 0.7)
		SetEnvironmentProperty("rain", 0.5)
		SetEnvironmentProperty("ambience", "outdoor/rain_light.ogg")
		SetEnvironmentProperty("nightlight", false)
		SetEnvironmentProperty("slippery", 0.2)
	elseif env == "rainynight" then
		SetEnvironmentProperty("skybox", "cloudy.dds")
		SetEnvironmentProperty("fogParams", 10, 90, 0.9, 2)
		nightDark()
		SetEnvironmentProperty("wetness", 0.7)
		SetEnvironmentProperty("puddleamount", 0.7)
		SetEnvironmentProperty("puddlesize", 0.7)
		SetEnvironmentProperty("rain", 0.9)
		SetEnvironmentProperty("ambience", "outdoor/rain_heavy.ogg")
		SetEnvironmentProperty("nightlight", true)
		SetEnvironmentProperty("slippery", 0.3)
		SetPostProcessingProperty("gamma", 0.9)
		SetPostProcessingProperty("bloom", 1.5)
	elseif env == "snowy" then
		SetEnvironmentProperty("skybox", "cool_day.dds")
		SetEnvironmentProperty("skyboxtint", 0.7, 0.7, 1.0)
		SetEnvironmentProperty("skyboxbrightness", 0.4)
		SetEnvironmentProperty("ambient", 1.0)
		SetEnvironmentProperty("fogColor", 0.35, 0.45, 0.6)
		SetEnvironmentProperty("fogParams", 10, 200, 1.0, 1.5)
		SetEnvironmentProperty("ambience", "outdoor/winter.ogg")
		SetEnvironmentProperty("sunbrightness", 3.14)
		SetEnvironmentProperty("suncolortint", 1, 0.85, 0.75)
		SetEnvironmentProperty("sunfogscale", 0.25)
		SetEnvironmentProperty("sunglare", 0.35)
		SetEnvironmentProperty("nightlight", false)
		SetEnvironmentProperty("slippery", 0.3)
		SetEnvironmentProperty("snowamount", 0.2)
		SetEnvironmentProperty("snowdir", 0.2, -1, 0.2, 0.2)
		SetPostProcessingProperty("saturation", 0.7)
		SetPostProcessingProperty("colorbalance", 0.7, 0.8, 1.0)
	elseif env == "snowynight" then
		SetEnvironmentProperty("skybox", "cold_wispy_sky.dds")
		SetEnvironmentProperty("skyboxbrightness", 0.035)
		SetEnvironmentProperty("fogColor", 0.005, 0.0055, 0.006)
		SetEnvironmentProperty("fogParams", 1, 125, 0.9, 0.5)
		SetEnvironmentProperty("constant", 0.002, 0.002, 0.002)
		SetEnvironmentProperty("ambient", 1.0)
		SetEnvironmentProperty("fogscale", 1.5)
		SetEnvironmentProperty("ambience", "outdoor/winter.ogg")
		SetEnvironmentProperty("nightlight", true)
		SetEnvironmentProperty("slippery", 0.3)
		SetEnvironmentProperty("snowamount", 0.2)
		SetEnvironmentProperty("snowdir", 0.2, -1, 0.2, 0.2)
		SetPostProcessingProperty("saturation", 0.7)
		SetPostProcessingProperty("colorbalance", 0.7, 0.8, 1.0)
		SetPostProcessingProperty("gamma", 0.85)
		SetPostProcessingProperty("bloom", 1.5)
	end
end

-- every frame: who the monsters are, their calls, the humans' noises, each monster's speed, stamina and jump
local mon = {}             -- [monster] = {stamina, exhausted, jumpT, nextCall}
local monKey, stamKey = nil, nil
local callPub = {}

-- (server) take cost seconds of monster m's stamina for an attack or a jump: false (nothing taken) when it hasn't
-- that much or is exhausted
function ehStaminaUse(m, cost)
	local st = mon[m]
	if not st then return true end
	if st.exhausted or st.stamina < cost then return false end
	st.stamina = st.stamina - cost
	if st.stamina <= 0.01 then st.stamina, st.exhausted = 0, true end
	return true
end

local function copyTable(t)
	local c = {}
	for k, v in pairs(t) do c[k] = v end
	return c
end

local function monsterMove(dt, p, st, now)
	local v = GetPlayerVelocity(p)
	local moving = math.sqrt(v[1] * v[1] + v[3] * v[3]) > 0.5
	local run = InputDown("shift", p) and moving and not st.exhausted and GetPlayerCrouch(p) < 0.5 and GetPlayerHealth(p) > 0
	if run then
		st.stamina = st.stamina - dt
		if st.stamina <= 0 then st.stamina, st.exhausted = 0, true end
	else
		st.stamina = math.min(STAMINA, st.stamina + dt * STAMINA_REGEN * (moving and 1 or 1.6))
		if st.exhausted and st.stamina >= STAMINA * EXHAUSTED_UNTIL then st.exhausted = false end
	end
	st.run = run and true or false
	SetPlayerParam("walkingSpeed", (run and MONSTER_RUN or MONSTER_WALK) * ehHitSlow(p), p)   -- (one frame: every tick; a hit slows it)
	if ehInWater(p) and GetPlayerHealth(p) > 0 and not mantleActive(p) then   -- (AgeOfAlgorithms: "excellent swimmers") where it
		local eye = GetPlayerEyeTransform(p)                     --  looks, fast; jump rises, crouch dives
		local f = (InputDown("up", p) and 1 or 0) - (InputDown("down", p) and 1 or 0)
		local r = (InputDown("right", p) and 1 or 0) - (InputDown("left", p) and 1 or 0)
		local u = (InputDown("jump", p) and 1 or 0) - (InputDown("crouch", p) and 1 or 0)
		local wish = VecAdd(VecScale(TransformToParentVec(eye, Vec(0, 0, -1)), f), VecScale(TransformToParentVec(eye, Vec(1, 0, 0)), r))
		local cur = GetPlayerVelocity(p)
		local swimRun = InputDown("shift", p) and not st.exhausted and (f ~= 0 or r ~= 0)
		local want = VecScale(VecLength(wish) > 0.01 and VecNormalize(wish) or Vec(0, 0, 0), (swimRun and MONSTER_SWIM_RUN or MONSTER_SWIM) * ehHitSlow(p))
		if u ~= 0 then want[2] = u * MONSTER_SWIM_RISE elseif f == 0 and r == 0 then want[2] = cur[2] end
		if f ~= 0 or r ~= 0 or u ~= 0 then
			SetPlayerVelocity(VecLerp(cur, want, math.min(1, dt * 8)), p)
		end
		st.swim = true
		return
	end
	st.swim = false
	-- the big jump: on take-off hold the upward speed that reaches MONSTER_JUMP (gravity 10)
	if InputPressed("jump", p) and IsPlayerGrounded(p) and not mantleActive(p) and ehStaminaUse(p, JUMP_STAMINA) then st.jumpT = now; jumpT = now end
	if now - st.jumpT < JUMP_BOOST_TIME then
		local jv = GetPlayerVelocity(p)
		jv[2] = math.sqrt(2 * 10 * MONSTER_JUMP)
		SetPlayerVelocity(jv, p)
	end
	local v2 = GetPlayerVelocity(p)
	if v2[2] > 0 and not mantleActive(p) then                -- rising: its head must not go through the ceiling
		local feet = GetPlayerTransform(p).pos
		QueryRejectPlayer(p)
		ehQueryMask()
		local from = 1.9                                        -- (above its player body)
		local hit = QueryRaycast(VecAdd(feet, Vec(0, from, 0)), Vec(0, 1, 0), MONSTER_TOP - from + v2[2] * dt + 0.05, 0.3)
		if hit then
			v2[2] = 0
			SetPlayerVelocity(v2, p)
			st.jumpT = -100                                     -- (the take-off push ends too)
		end
	end
end

function ehServerTick(dt, ms, hunting)
	if type(ms) == "number" then ms = (ms ~= 0) and {ms} or {} end
	local live, set = {}, {}
	for _, m in ipairs(ms or {}) do
		if m ~= 0 and IsPlayerValid(m) and not set[m] then live[#live + 1] = m; set[m] = true end
	end
	local key = table.concat(live, ",")
	if key ~= monKey then                                    -- (published when it changes)
		monKey = key
		shared.ehMonsters = copyTable(live)
		shared.ehMonster = live[1] or 0                      -- (the first: the TEST probe and the autotests read it)
	end
	ehCombatTick(dt, live, hunting ~= false)                     -- (eh_combat.lua: their attacks, HP, hit boxes, stuns)
	local now = GetTime()
	local callsChanged = false
	for m in pairs(mon) do
		if not set[m] then mon[m] = nil; callPub[m] = nil; callsChanged = true end
	end
	for _, m in ipairs(live) do
		local st = mon[m]
		if not st then                                       -- (calls staggered: two monsters don't call together)
			st = {stamina = STAMINA, exhausted = false, run = false, jumpT = -100, nextCall = now + 2 + math.random() * 6, callN = 0}
			mon[m] = st
		end
		if now >= st.nextCall then                           -- its calls, at random, the same for everyone
			st.nextCall = now + MCALL_MIN + math.random() * (MCALL_MAX - MCALL_MIN)
			st.callN = st.callN + 1
			callPub[m] = {n = st.callN, kind = (math.random() < 0.55) and "click" or "hiss"}
			callsChanged = true
		end
		monsterMove(dt, m, st, now)
	end
	if callsChanged then shared.ehCall = copyTable(callPub) end
	humanNoises(set)
	chatNoises(set)
	local stam, sk = {}, ""
	for _, m in ipairs(live) do
		local st = mon[m]
		stam[m] = {s = st.stamina / STAMINA, run = st.run, ex = st.exhausted}
		sk = sk .. string.format("%d:%.2f%s%s ", m, stam[m].s, tostring(st.run), tostring(st.exhausted))
	end
	if sk ~= stamKey then                                    -- (published when it changes)
		stamKey = sk
		shared.ehStam = stam
	end
end

----- the public interface for the including scripts (their code can't see this file's locals) -----

function ehViewOn() return on end
function ehPulseCooldown() return pulseReady - GetTime() end
function ehPulseReset() pulseReady = 0 end
function ehPulseLast() return pulseLast end
function ehFog(void, gamma)
	if void and void ~= fogVoid then
		fogVoid = void
		if on then voidDelete(); voidSpawn() end                 -- (the panels are sized by the radius)
	end
	if gamma then fogGamma = gamma end
	return fogVoid, fogGamma
end
function ehPlaceDummy() placeDummy(GetTime()) end
function ehDebug()
	return {void = fogVoid, gamma = fogGamma, panels = #panels, lastVol = lastVol, lastVolT = lastVolT, people = #people,
		hidden = hiddenNow, jumpT = jumpT, dummies = #dummies, on = on, camRaise = camRaise}
end
