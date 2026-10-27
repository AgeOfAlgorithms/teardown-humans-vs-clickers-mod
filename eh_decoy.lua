-- Humans vs Clickers: the noisemaker (AgeOfAlgorithms) - a decoy. Each human starts with one; LMB throws it (the game's
-- pipe bomb in the hand, a small metal can when thrown), and from DECOY_FUSE s after the throw it fires gunshots at a
-- random cadence for DECOY_TIME s.
-- Everyone hears the shots there; a clicker sees each one as its thrower firing a gun from where it lies (a "decoy"
-- noise: eh_monster.lua draws their shape and name, as for a real shot). Included by echohunt.lua; interface:
--   server: ehDecoyServerInit(), ehDecoyReset(), ehDecoyServerTick(active) - after ehServerTick (its tool noise)
--   client: ehDecoyClientInit(), ehDecoyClientTick(dt)

DECOY_TOOL = "eh_noisemaker"
DECOY_FUSE = 1.2           -- s from the throw to the first shot (it has landed)
DECOY_TIME = 7             -- s of shots (AgeOfAlgorithms)
DECOY_THROW = 14           -- m/s along the aim ...
DECOY_LOFT = 3             -- ... and up
DECOY_GONE = 4             -- s after its last shot it is removed
DECOY_VOL = 4.9            -- each shot's volume: a real gunshot's (GetLastSound read 4.94 on the clicker's machine, 2026-10-26),
                           -- so the clicker hears it the same way: a starburst to 300 m (at 1.0 it read 0.98: rings only)
DECOY_SOUND_UP = 1.0       -- m above the can each shot sounds: at hip height, where a real gun is (AgeOfAlgorithms: from the
                           -- clicker's view the rings at the feet gave it away)
DECOY_PUT_AWAY = 0.3       -- s it stays in hand after the throw (the game's tool animator shows its throw pose meanwhile)
DECOY_LAUNCH_TICKS = 2     -- ticks after the spawn its throw speed is set (set in the spawn's own tick it was lost: in the
                           -- game the can dropped at the thrower's feet)

local DS = {list = {}, away = {}, throwN = 0}

----- server -----

function ehDecoyServerInit()
	RegisterTool(DECOY_TOOL, "Noisemaker", "MOD/prefab/noisemaker.xml", 5)
end

function ehDecoyReset()
	for _, d in ipairs(DS.list) do if IsHandleValid(d.body) then Delete(d.body) end end
	DS.list, DS.away = {}, {}
end

local function throw(q)
	local eye = GetPlayerEyeTransform(q)
	local fwd = QuatRotateVec(eye.rot, Vec(0, 0, -1))
	-- (a small metal can, 0.2 x 0.3 x 0.2 m: the pipe bomb model at its tool size, scale 0.5, made the body static - it
	--  hung in the air where it was thrown, in the game; unscaled it is 0.7 m long)
	local at = TransformToParentPoint(eye, Vec(0.3, -0.3, -0.5))  -- (from the hand, as the game's snowball)
	local ents = Spawn("<body dynamic='true' tags='ehdecoy unbreakable'><voxbox size='2 3 2' color='0.28 0.32 0.22' material='metal'/></body>",
		Transform(at, eye.rot))
	local body
	for _, en in ipairs(ents or {}) do if GetEntityType(en) == "body" then body = en end end
	if not body then return end
	DS.throwN = DS.throwN + 1                                     -- (its sound: the humans' machines only - the clickers
	shared.ehThrow = {n = DS.throwN, x = at[1], y = at[2], z = at[3]}   --  never hear a throw, AgeOfAlgorithms)
	local now = GetTime()
	DS.list[#DS.list + 1] = {body = body, p = q, nextShot = now + DECOY_FUSE, stop = now + DECOY_FUSE + DECOY_TIME,
		launch = VecAdd(VecScale(fwd, DECOY_THROW), Vec(0, DECOY_LOFT, 0)), launchN = DECOY_LAUNCH_TICKS}
end

-- the gap to the next shot: mostly quick follow-ups (a burst), sometimes a pause - never a steady beat
local function nextGap()
	if math.random() < 0.6 then return 0.09 + math.random() * 0.18 end
	return 0.45 + math.random() * 0.9
end

-- active: the round is on (head start or hunt) - throws only then; noisemakers already out keep going until done
function ehDecoyServerTick(active)
	local now = GetTime()
	if active then
		for q in Players() do
			if GetPlayerTool(q) == DECOY_TOOL and InputPressed("usetool", q) and GetPlayerHealth(q) > 0 and not ehIsMonster(q)
				and GetToolAmmo(DECOY_TOOL, q) >= 1 and not DS.away[q] then
				DS.away[q] = now + DECOY_PUT_AWAY                    -- (its ammo stays until then: none and the engine
				throw(q)                                             --  might switch tools at once, no throw pose)
			end
		end
	end
	for q, t in pairs(DS.away) do                                 -- thrown: used up and put away
		if now >= t then
			DS.away[q] = nil
			if IsPlayerValid(q) then
				SetToolAmmo(DECOY_TOOL, 0, q)
				SetToolEnabled(DECOY_TOOL, false, q)
				if GetPlayerTool(q) == DECOY_TOOL then SetPlayerTool("none", q) end
			end
		end
	end
	for i = #DS.list, 1, -1 do
		local d = DS.list[i]
		if not IsHandleValid(d.body) or now > d.stop + DECOY_GONE then
			if IsHandleValid(d.body) then Delete(d.body) end
			table.remove(DS.list, i)
		elseif d.launchN > 0 then                                -- (thrown: its speed, once it is in the physics)
			d.launchN = d.launchN - 1
			SetBodyActive(d.body, true)
			SetBodyVelocity(d.body, d.launch)
			SetBodyAngularVelocity(d.body, Vec(math.random() * 8 - 4, math.random() * 8 - 4, math.random() * 8 - 4))
		elseif now >= d.nextShot and now <= d.stop then
			d.nextShot = now + nextGap()
			local gun = TOOL_NOISE.gun
			ehEmitNoise(d.p, "decoy", GetBodyTransform(d.body).pos, gun.r, gun.loud, "gun", true)
		end
	end
end

----- client (every machine: the shots are heard by everyone) -----

local DC = {seen = nil, snd = {}, throwSnd = nil, throwN = nil}

function ehDecoyClientInit()
	for i = 0, 7 do DC.snd[#DC.snd + 1] = LoadSound("tools/gun" .. i .. ".ogg") end
	DC.throwSnd = LoadSound("throw/m0.ogg")                     -- (the game's throw: its snowball's)
end

-- the noisemaker in the hand: the game's own tool animator (script/toolanimation.lua, as its snowball does) poses it
-- from the prefab's locations - the game's pipe bomb poses (first / third person, crouch, run, jump, swim, the hand on
-- its grip) - for every player holding one. (Without it the engine draws a mod's tool right in front of the eyes: the
-- locations alone do nothing - Mochi the Corgi's toys, seen in-game 2026-10-24.)
local animators = {}
local function holdNoisemakers(dt)
	for p in Players() do
		if GetPlayerTool(p) == DECOY_TOOL then
			local ta = animators[p]
			if not ta then                                          -- (tuned as the game's snowball, a throwable)
				ta = ToolAnimator()
				ta.armPitchScale, ta.toolPitchScale, ta.maxActionPoseTime = 0.2, 0.1, 0.05
				animators[p] = ta
			end
			tickToolAnimator(ta, dt, nil, p)
		end
	end
end

function ehDecoyClientTick(dt)
	holdNoisemakers(dt)
	local th = shared.ehThrow                                      -- a throw: heard by the humans, never by a clicker
	if th and th.n then
		if DC.throwN and th.n > DC.throwN and not ehIsMonster(GetLocalPlayer()) and DC.throwSnd then
			PlaySound(DC.throwSnd, Vec(th.x, th.y, th.z), 1.0, false)   -- (false: no noise for the clicker's GetLastSound)
		end
		DC.throwN = th.n
	else
		DC.throwN = DC.throwN or 0
	end
	local q = shared.ehNoise
	if not q or not q.seq then DC.seen = DC.seen or 0; return end
	if not DC.seen or q.seq < DC.seen then DC.seen = q.seq end          -- (joined late, or a new session: from now on)
	for _, e in ipairs(q.list or {}) do
		if e.seq > DC.seen and e.decoy and #DC.snd > 0 then
			PlaySound(DC.snd[math.random(#DC.snd)], Vec(e.x, e.y + DECOY_SOUND_UP, e.z), DECOY_VOL)
		end
	end
	DC.seen = q.seq
end
