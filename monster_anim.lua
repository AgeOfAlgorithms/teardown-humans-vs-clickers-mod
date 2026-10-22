-- Echo Hunt: procedural animation of the Blind Demon (hand-written). Same pose framework as Dread Keep's
-- monster_anim.lua (verified in-game), for one monster.
-- Include monster_rig.lua BEFORE this file. No #version line (included). Defines only globals:
--   MonsterPose(a, out)  fills out[partName] = Transform(centre, rot) = each part's .vox CENTRE and rotation in the
--                        monster ROOT frame (origin = ground point under the centre, +y up, +z forward, +x = the
--                        monster's left). Existing out[partName] transforms are UPDATED IN PLACE (no garbage per
--                        frame); give each monster visual its own out table.
--   a = {st, t, phase, speed, look, time, seed, headroom}:
--     st       "idle" | "walk" | "run" | "crouch" | "crawl" | "swing_l" | "swing_r" | "grab" | "hold" | "scream" |
--              "dead" (unknown -> idle). crouch = a low creep on its legs; crawl = the four-limbed crawl (~1.6 m)
--     t        seconds in the state (one-shots: swing_l / swing_r MONSTER_ANIM.swing s, grab MONSTER_ANIM.grab s,
--              scream MONSTER_ANIM.scream s; after that they hold their end pose = back near idle)
--     phase    gait phase (radians): phase = phase + distance / MonsterStride(speed, headroom) * 2 * pi
--              (crawl state: MONSTER_ANIM.crawlStride)
--     speed    m/s. walk and run are ONE speed-driven gait: the stalking walk (7 m/s) up to 7.5 m/s, the galloping
--              run (11 m/s) from 10.5 m/s, blended between; missing speed = the state's nominal speed. crouch and
--              crawl only creep while moving
--     look     head pitch offset (radians, > 0 = looking UP, like a camera pitch; clamped to +-60 deg)
--     time     GetTime() (breathing, twitches);  seed  int (desynchronises several monsters)
--     headroom metres of free space above the root (nil = unlimited). When the state's pose is taller, it blends
--              toward the crawl (hunch, bent knees, down onto the long arms) just enough to stay under it, down to
--              the full crawl at ~1.6 m; continuous in headroom (smooth it over time in the caller for big jumps).
--              In swing / grab / hold / scream only the body blends (the arms and head keep the action); never dead.
--              (The last blend weights are kept in out.__hre / out.__hra as a warm start for the next frame.)
--   MONSTER_STATES       the states MonsterPose poses
--   MONSTER_ANIM         {walkSpeed, runSpeed, blend0, blend1, walkStride, runStride, crawlStride, swing, grab,
--                        scream, standing, crawlTop}: speeds (m/s), metres per gait cycle, one-shot durations (s),
--                        standing and crawl heights (m)
--   MonsterStride(speed, headroom)  metres per gait cycle at that speed (advance a.phase with it)
-- Pure: math + the Vec / Quat / Transform constructors only; no engine state.
-- Conventions inside: a part's local rotation is in its PARENT's frame, about its own pivot.
--   pitch (deg) about +x: positive swings a hanging limb BACK and tips the face DOWN;
--   yaw about +y: positive turns toward +x (the monster's left); roll about +z: positive moves a hanging limb
--   toward +x. E(c, i, pitch, yaw, roll) appends Ry(yaw) * Rx(pitch) * Rz(roll) to the part's local rotation.

MONSTER_STATES = {"idle", "walk", "run", "crouch", "crawl", "swing_l", "swing_r", "grab", "hold", "scream", "dead"}
MONSTER_ANIM = {walkSpeed = 7.0, runSpeed = 11.0, blend0 = 7.5, blend1 = 10.5, walkStride = 3.6, runStride = 6.8,
	crawlStride = 1.6, swing = 0.6, grab = 0.5, scream = 1.2, standing = 3.6, crawlTop = 1.6}

-- metres travelled per gait cycle (2 * pi of a.phase) at this speed; under a low headroom the gait turns into the crawl.
-- Advance the phase with it: phase = phase + dist / MonsterStride(speed, headroom) * 2 * pi  (no foot sliding).
function MonsterStride(speed, headroom)
	local M = MONSTER_ANIM
	local v = speed or 0
	local x = (v - M.blend0) / (M.blend1 - M.blend0)
	x = x < 0 and 0 or (x > 1 and 1 or x)
	x = x * x * (3 - 2 * x)
	local k = v / M.walkSpeed
	k = k < 0 and 0 or (k > 1 and 1 or k)
	local s = M.walkStride * (0.45 + 0.55 * k)
	s = s + (M.runStride - s) * x
	if headroom and headroom < M.standing then
		local h = (M.standing - headroom) / (M.standing - M.crawlTop)
		h = h > 1 and 1 or h
		s = s + (M.crawlStride - s) * h
	end
	return s
end

do
	local sin, cos, abs, sqrt, floor, min, max, pi, exp = math.sin, math.cos, math.abs, math.sqrt, math.floor, math.min, math.max, math.pi, math.exp
	local RAD = pi / 180

	-- ---------------------------------------------------------------- scalar quaternion maths (no tables)
	local function qmul(ax, ay, az, aw, bx, by, bz, bw)
		return aw * bx + ax * bw + ay * bz - az * by,
			aw * by - ax * bz + ay * bw + az * bx,
			aw * bz + ax * by - ay * bx + az * bw,
			aw * bw - ax * bx - ay * by - az * bz
	end
	local function qaxis(x, y, z, deg)
		local h = deg * RAD * 0.5
		local s = sin(h)
		return x * s, y * s, z * s, cos(h)
	end
	local function qrot(qx, qy, qz, qw, vx, vy, vz)
		local tx = 2 * (qy * vz - qz * vy)
		local ty = 2 * (qz * vx - qx * vz)
		local tz = 2 * (qx * vy - qy * vx)
		return vx + qw * tx + (qy * tz - qz * ty), vy + qw * ty + (qz * tx - qx * tz), vz + qw * tz + (qx * ty - qy * tx)
	end
	local function qnlerp(ax, ay, az, aw, bx, by, bz, bw, k)
		if ax * bx + ay * by + az * bz + aw * bw < 0 then bx, by, bz, bw = -bx, -by, -bz, -bw end
		local x, y, z, w = ax + (bx - ax) * k, ay + (by - ay) * k, az + (bz - az) * k, aw + (bw - aw) * k
		local n = sqrt(x * x + y * y + z * z + w * w)
		if n < 1e-9 then return 0, 0, 0, 1 end
		return x / n, y / n, z / n, w / n
	end

	-- ---------------------------------------------------------------- curve helpers
	local function clamp(x, a, b) if x < a then return a elseif x > b then return b end return x end
	local function smooth(x) x = clamp(x, 0, 1) return x * x * (3 - 2 * x) end
	local function lerp(a, b, k) return a + (b - a) * k end
	local function hash(x) local s = sin(x * 12.9898 + 4.1414) * 43758.5453 return s - floor(s) end
	-- -1..1: holds still, then jerks to a new random value (rate = jerks per second)
	local function twitch(time, rate, seed)
		local u = time * rate + seed * 3.7
		local k = floor(u)
		local a0 = hash(k + seed) * 2 - 1
		local a1 = hash(k + 1 + seed) * 2 - 1
		if hash(k * 1.3 + seed) < 0.45 then a1 = a0 end
		return lerp(a0, a1, smooth((u - k) * 6 - 5))
	end
	-- 0 -> 1 over dur with an overshoot wobble (a spring)
	local function spring(t, dur)
		if t <= 0 then return 0 end
		local x = t / dur
		return 1 - exp(-4.5 * x) * cos(8 * x)
	end
	-- 0 -> 1 -> 0 over [t0, t1], fast rise
	local function pulse(t, t0, t1)
		if t <= t0 or t >= t1 then return 0 end
		return sin(pi * ((t - t0) / (t1 - t0)) ^ 0.6)
	end
	-- piecewise ease between keys: keys = {t0, v0, t1, v1, ...} (no garbage: keys are constant tables)
	local function keyed(t, k)
		if t <= k[1] then return k[2] end
		for i = 3, #k, 2 do
			if t <= k[i] then return lerp(k[i - 1], k[i + 1], smooth((t - k[i - 2]) / (k[i] - k[i - 2]))) end
		end
		return k[#k]
	end

	-- ---------------------------------------------------------------- rig cache (the one RIG of monster_rig.lua)
	local CACHE = {}
	local function rigFor(ty)
		local c = CACHE[ty]
		if c then return c end
		local rig = RIG
		if not rig then return nil end
		c = {ty = ty, n = #rig.parts, name = {}, idx = {}, par = {}, px = {}, py = {}, pz = {}, dx = {}, dy = {}, dz = {},
			foot = {}, fx = {}, fy = {}, fz = {}, hull = {}, sx = {}, sy = {}, sz = {},
			lx = {}, ly = {}, lz = {}, lw = {}, ox = {}, oy = {}, oz = {},
			wx = {}, wy = {}, wz = {}, ww = {}, ppx = {}, ppy = {}, ppz = {}, cx = {}, cy = {}, cz = {},
			ab = {}, abr = {}, abk = {}, abx = {}, aby = {}, abz = {}, abqx = {}, abqy = {}, abqz = {}, abqw = {},
			height = rig.height or 1}
		for i, p in ipairs(rig.parts) do
			c.name[i] = p.name
			c.idx[p.name] = i
		end
		for i, p in ipairs(rig.parts) do
			c.par[i] = p.parent and c.idx[p.parent] or 0
			c.px[i], c.py[i], c.pz[i] = p.pivot[1], p.pivot[2], p.pivot[3]
			c.dx[i], c.dy[i], c.dz[i] = p.center[1] - p.pivot[1], p.center[2] - p.pivot[2], p.center[3] - p.pivot[3]
			if p.foot then
				c.foot[i] = true
				c.fx[i], c.fy[i], c.fz[i] = p.foot[1] - p.center[1], p.foot[2] - p.center[2], p.foot[3] - p.center[3]
			end
			local h = p.hull or {0, 0, 0}
			c.hull[i] = h
			-- centre of the solid voxels relative to the box centre (from the hull's extremes)
			local x0, y0, z0, x1, y1, z1 = 1e9, 1e9, 1e9, -1e9, -1e9, -1e9
			for k = 1, #h, 3 do
				x0, x1 = min(x0, h[k]), max(x1, h[k])
				y0, y1 = min(y0, h[k + 1]), max(y1, h[k + 1])
				z0, z1 = min(z0, h[k + 2]), max(z1, h[k + 2])
			end
			c.sx[i], c.sy[i], c.sz[i] = (x0 + x1) / 2, (y0 + y1) / 2, (z0 + z1) / 2
		end
		CACHE[ty] = c
		return c
	end

	-- ---------------------------------------------------------------- pose building API
	local function reset(c)
		for i = 1, c.n do
			c.lx[i], c.ly[i], c.lz[i], c.lw[i] = 0, 0, 0, 1
			c.ox[i], c.oy[i], c.oz[i] = 0, 0, 0
			c.ab[i] = false
		end
		c.gx, c.gy, c.gz, c.gw = 0, 0, 0, 1
		c.gpx, c.gpy, c.gpz = 0, 0, 0
		c.gox, c.goy, c.goz = 0, 0, 0
		c.snap = nil
		c.lift = 0
		c.ikw = 0
	end
	local function post(c, i, ax, ay, az, deg)        -- local = local * R(axis, deg)
		if not i or deg == 0 then return end
		local bx, by, bz, bw = qaxis(ax, ay, az, deg)
		c.lx[i], c.ly[i], c.lz[i], c.lw[i] = qmul(c.lx[i], c.ly[i], c.lz[i], c.lw[i], bx, by, bz, bw)
	end
	local function E(c, i, p, y, r)                    -- local = local * Ry(y) * Rx(p) * Rz(r)
		if not i then return end
		post(c, i, 0, 1, 0, y or 0)
		post(c, i, 1, 0, 0, p or 0)
		post(c, i, 0, 0, 1, r or 0)
	end
	local function off(c, i, x, y, z)                  -- move a pivot (in the parent's rest frame)
		if not i then return end
		c.ox[i], c.oy[i], c.oz[i] = c.ox[i] + x, c.oy[i] + y, c.oz[i] + z
	end
	local function gpost(c, ax, ay, az, deg)           -- whole-body rotation about the global pivot (after the solve)
		if deg == 0 then return end
		local bx, by, bz, bw = qaxis(ax, ay, az, deg)
		c.gx, c.gy, c.gz, c.gw = qmul(c.gx, c.gy, c.gz, c.gw, bx, by, bz, bw)
	end
	local function gpivot(c, x, y, z) c.gpx, c.gpy, c.gpz = x, y, z end
	local function gmove(c, x, y, z) c.gox, c.goy, c.goz = c.gox + x, c.goy + y, c.goz + z end
	-- place a part's SOLID centre at (x, y, z) given in the REST frame of part r (r = nil: the root frame), rotated
	-- by E(p, yw, rl) relative to r; k = 0: placed, k = 1: the normal (jointed) pose, in between: blend (k may overshoot)
	local function place(c, i, r, x, y, z, p, yw, rl, k)
		if not i then return end
		c.ab[i] = true
		c.abr[i] = r or 0
		c.abk[i] = k or 0
		local qx, qy, qz, qw = qaxis(0, 1, 0, yw or 0)
		local bx, by, bz, bw = qaxis(1, 0, 0, p or 0)
		qx, qy, qz, qw = qmul(qx, qy, qz, qw, bx, by, bz, bw)
		bx, by, bz, bw = qaxis(0, 0, 1, rl or 0)
		qx, qy, qz, qw = qmul(qx, qy, qz, qw, bx, by, bz, bw)
		c.abqx[i], c.abqy[i], c.abqz[i], c.abqw[i] = qx, qy, qz, qw
		-- the box centre sits at target - R * (solid centre offset)
		local vx, vy, vz = qrot(qx, qy, qz, qw, c.sx[i], c.sy[i], c.sz[i])
		c.abx[i], c.aby[i], c.abz[i] = x - vx, y - vy, z - vz
	end

	local function solve(c)
		local n = c.n
		-- 1. forward kinematics: world rotation + pivot position of every part
		for i = 1, n do
			local p = c.par[i]
			if p == 0 then
				c.wx[i], c.wy[i], c.wz[i], c.ww[i] = c.lx[i], c.ly[i], c.lz[i], c.lw[i]
				c.ppx[i], c.ppy[i], c.ppz[i] = c.px[i] + c.ox[i], c.py[i] + c.oy[i], c.pz[i] + c.oz[i]
			else
				local Px, Py, Pz, Pw = c.wx[p], c.wy[p], c.wz[p], c.ww[p]
				c.wx[i], c.wy[i], c.wz[i], c.ww[i] = qmul(Px, Py, Pz, Pw, c.lx[i], c.ly[i], c.lz[i], c.lw[i])
				local vx, vy, vz = qrot(Px, Py, Pz, Pw, c.px[i] - c.px[p] + c.ox[i], c.py[i] - c.py[p] + c.oy[i], c.pz[i] - c.pz[p] + c.oz[i])
				c.ppx[i], c.ppy[i], c.ppz[i] = c.ppx[p] + vx, c.ppy[p] + vy, c.ppz[p] + vz
			end
		end
		-- 2. part centres (placed parts relative to their reference part); kept in cx.. and the rotation in abq..
		for i = 1, n do
			local vx, vy, vz = qrot(c.wx[i], c.wy[i], c.wz[i], c.ww[i], c.dx[i], c.dy[i], c.dz[i])
			c.cx[i], c.cy[i], c.cz[i] = c.ppx[i] + vx, c.ppy[i] + vy, c.ppz[i] + vz
		end
		for i = 1, n do
			if c.ab[i] then
				local r = c.abr[i]
				local x, y, z = c.abx[i], c.aby[i], c.abz[i]
				local qx, qy, qz, qw = c.abqx[i], c.abqy[i], c.abqz[i], c.abqw[i]
				if r > 0 then
					local Rx, Ry, Rz, Rw = c.wx[r], c.wy[r], c.wz[r], c.ww[r]
					local vx, vy, vz = qrot(Rx, Ry, Rz, Rw, x - c.px[r], y - c.py[r], z - c.pz[r])
					x, y, z = c.ppx[r] + vx, c.ppy[r] + vy, c.ppz[r] + vz
					qx, qy, qz, qw = qmul(Rx, Ry, Rz, Rw, qx, qy, qz, qw)
				end
				local k = c.abk[i]
				if k ~= 0 then
					x, y, z = lerp(x, c.cx[i], k), lerp(y, c.cy[i], k), lerp(z, c.cz[i], k)
					qx, qy, qz, qw = qnlerp(qx, qy, qz, qw, c.wx[i], c.wy[i], c.wz[i], c.ww[i], k)
				end
				c.cx[i], c.cy[i], c.cz[i] = x, y, z
				c.abqx[i], c.abqy[i], c.abqz[i], c.abqw[i] = qx, qy, qz, qw
			end
		end
		for i = 1, n do
			if c.ab[i] then c.wx[i], c.wy[i], c.wz[i], c.ww[i] = c.abqx[i], c.abqy[i], c.abqz[i], c.abqw[i] end
		end
		-- 3. whole-body rotation + move
		local gx, gy, gz, gw = c.gx, c.gy, c.gz, c.gw
		local glob = gw < 0.9999999
		for i = 1, n do
			local x, y, z = c.cx[i], c.cy[i], c.cz[i]
			if glob then
				local vx, vy, vz = qrot(gx, gy, gz, gw, x - c.gpx, y - c.gpy, z - c.gpz)
				x, y, z = c.gpx + vx, c.gpy + vy, c.gpz + vz
				c.wx[i], c.wy[i], c.wz[i], c.ww[i] = qmul(gx, gy, gz, gw, c.wx[i], c.wy[i], c.wz[i], c.ww[i])
			end
			c.cx[i], c.cy[i], c.cz[i] = x + c.gox, y + c.goy, z + c.goz
		end
		-- 4. ground snap: "feet" puts the lowest foot point at y = lift; "all" rests the lowest hull point there
		if c.snap then
			local lo = 1e9
			for i = 1, n do
				if c.snap == "all" and not c.ab[i] then
					local h = c.hull[i]
					for k = 1, #h, 3 do
						local _, vy = qrot(c.wx[i], c.wy[i], c.wz[i], c.ww[i], h[k], h[k + 1], h[k + 2])
						if c.cy[i] + vy < lo then lo = c.cy[i] + vy end
					end
				elseif c.snap == "feet" and c.foot[i] then
					local _, vy = qrot(c.wx[i], c.wy[i], c.wz[i], c.ww[i], c.fx[i], c.fy[i], c.fz[i])
					if c.cy[i] + vy < lo then lo = c.cy[i] + vy end
				end
			end
			if lo < 1e8 then
				local dy = c.lift - lo
				for i = 1, n do c.cy[i] = c.cy[i] + dy end
			end
		end
	end

	-- ================================================================ THE BLIND DEMON
	-- Parts: pelvis (root) > torso > neck > head > jaw; torso > arm_*_up > arm_*_low > hand_*; pelvis > leg_*_up >
	-- leg_*_low > foot_*. Rest pose: standing upright (~4.1 m; idle stands 3.6 m), arms hanging, maw facing +z.
	local SW, GR, SC = MONSTER_ANIM.swing, MONSTER_ANIM.grab, MONSTER_ANIM.scream

	-- the head: neck forward + head back up so the maw faces where it goes; look > 0 = looking UP (camera pitch)
	local function headLook(c, I, a, neckP, headP, yaw, roll)
		local lk = clamp((a.look or 0) / RAD, -60, 60)
		E(c, I.neck, neckP - lk * 0.35, yaw * 0.4, 0)
		E(c, I.head, headP - lk * 0.65, yaw * 0.6, roll or 0)
	end
	-- legs slightly bent on raised heels (digitigrade feel): thigh forward, shin back, foot tipped onto the ball
	local function stanceLegs(c, I, bend)
		E(c, I.leg_l_up, -bend, 0, 0); E(c, I.leg_r_up, -bend, 0, 0)
		E(c, I.leg_l_low, bend * 1.8, 0, 0); E(c, I.leg_r_low, bend * 1.8, 0, 0)
		E(c, I.foot_l, -bend * 0.8, 0, 0); E(c, I.foot_r, -bend * 0.8, 0, 0)
	end
	-- arms hanging (pitch relative to the torso: counter its hunch) with an extra forward reach
	local function hangArms(c, I, hunch, fwdL, fwdR, out)
		E(c, I.arm_l_up, -hunch - fwdL, 0, out or 4); E(c, I.arm_r_up, -hunch - fwdR, 0, -(out or 4))
	end
	-- whole-hand "finger" motion: the fingers are one part with the palm, so flexing = the hand curling / spreading
	local function flex(c, i, side, curl, spread)
		E(c, i, -curl, 0, side * spread)
	end

	-- the low four-limbed crawl (top ~1.6 m): legs folded under, the body near horizontal, the long arms planted
	-- ahead as front legs (elbows out), the head held up so the maw faces forward. mv = 0..1 (moving), diagonal gait
	-- (left arm with the right leg)
	local CR_A1, CR_A2, CR_OUT = -82, -14, 24
	local CRW = {0, 0, 0, 0}             -- the last crawl pose's arm WORLD pitches {a1l, a1r, a2l, a2r} (headroom blend)
	local function crawlPose(c, a, I, mv)
		local ph, time, seed = a.phase, a.time, a.seed
		local br = sin(time * 1.15 + seed)
		local s = sin(ph) * mv
		local k = cos(ph) * mv
		local hunch = 84
		local kl, kr = (k > 0 and k or 0), (k < 0 and -k or 0)
		E(c, I.leg_l_up, -86 - 16 * s - 10 * kl, 0, 3); E(c, I.leg_r_up, -86 + 16 * s - 10 * kr, 0, -3)
		E(c, I.leg_l_low, 128 + 14 * kl, 0, 0); E(c, I.leg_r_low, 128 + 14 * kr, 0, 0)
		E(c, I.foot_l, -40 + 8 * s, 0, 0); E(c, I.foot_r, -40 - 8 * s, 0, 0)
		E(c, I.torso, hunch + 2 * br, -7 * s, -3 * s)
		-- arms: the upper arm reaches forward and out (world pitch a1), the forearm comes back down (a2) to a hand
		-- flat on the floor (its local pitch cancels the forearm's, the finger fan turned flat)
		-- (the forearm angle follows the upper arm's swing so the planted hand stays on the floor; the swinging hand lifts)
		local a1l, a1r = CR_A1 + 12 * s, CR_A1 - 12 * s
		local a2l, a2r = CR_A2 + 30 * s, CR_A2 - 30 * s
		CRW[1], CRW[2], CRW[3], CRW[4] = a1l, a1r, a2l, a2r
		E(c, I.arm_l_up, a1l - hunch, 0, CR_OUT); E(c, I.arm_r_up, a1r - hunch, 0, -CR_OUT)
		E(c, I.arm_l_low, a2l - a1l, 0, 0); E(c, I.arm_r_low, a2r - a1r, 0, 0)
		E(c, I.hand_l, -90 - a2l, 0, -CR_OUT * 0.8); E(c, I.hand_r, -90 - a2r, 0, CR_OUT * 0.8)
		E(c, I.hand_l, 0, 90, 0); E(c, I.hand_r, 0, -90, 0)
		headLook(c, I, a, 6, -84 + 6 * twitch(time, 0.9, seed), 16 * twitch(time, 0.6, seed + 3), 0)
		E(c, I.jaw, 8 + 5 * br + 10 * mv * abs(s), 0, 0)
		c.lift = 0.14 * max(0, -s * k)                        -- (the planted foot sinks at this point of the gait)
	end

	-- ---------------------------------------------------------------- locomotion: stalking walk <-> galloping run
	-- walk (7 m/s): upright-ish, very long strides, head low and swaying, arms hanging and swinging loosely.
	-- run (11 m/s): a violent hunched gallop: torso pitched far forward, hind legs bounding together, the long arms
	-- reaching ahead and clawing the ground every stride, head thrust forward. Between MONSTER_ANIM.blend0 and .blend1
	-- m/s the two poses blend. Leg swing amplitudes come from the stride (no foot sliding: see MonsterStride).
	-- Legs (walk and run) and the run's arms are placed by 2-bone IK in the sagittal plane, so a planted foot moves
	-- back exactly as fast as the root moves on (phase advanced by distance / MonsterStride) and planted claws reach
	-- the ground.
	local W_D, W_DROP, W_LIFT = 0.5, 1.46, 0.5           -- walk: stance fraction, max hip-ankle drop (m), swing lift (m)
	local R_D, R_DROP, R_LIFT, R_FLY = 0.36, 1.3, 0.75, 0.16   -- run: the same + flight lift of the body (m)
	local R_AD, R_AREACH, R_ABACK = 0.36, 1.25, -0.25    -- run arms: stance fraction, claw plant ahead of / behind the
	                                                     -- shoulder (m, at the start / end of the arm's stance)
	local ATAN2 = math.atan2 or math.atan
	local function acos1(x) return math.acos(clamp(x, -1, 1)) end
	-- a limb's cycle: stance for the first D of the cycle (x goes 1 -> -1 at constant speed), then the swing (x
	-- eases back to 1, lifted by lift = sin)
	local function gaitFn(ph, D)
		local u = ph / (2 * pi)
		u = u - floor(u)
		if u < D then return 1 - 2 * u / D, 0 end
		local q = (u - D) / (1 - D)
		return -1 + 2 * smooth(q), sin(pi * q)
	end
	-- 2-bone IK in the sagittal plane: from joint A, segments L1 and L2 to reach (dz, ddown) (forward, down);
	-- bend = +1 puts the middle joint forward (knee), -1 back (elbow). Returns the two segment angles (deg from
	-- straight down, positive = forward)
	local function ik2(L1, L2, dz, ddown, bend)
		local d = sqrt(dz * dz + ddown * ddown)
		local dmax = (L1 + L2) * 0.999
		if d > dmax then dz, ddown, d = dz * dmax / d, ddown * dmax / d, dmax end
		if d < abs(L1 - L2) + 0.01 then d = abs(L1 - L2) + 0.01 end
		local phi = ATAN2(dz, ddown)
		local g = acos1((L1 * L1 + d * d - L2 * L2) / (2 * L1 * d))
		local a1 = phi + bend * g
		local mz, md = L1 * sin(a1), L1 * cos(a1)
		local a2 = ATAN2(dz - mz, ddown - md)
		return a1 / RAD, a2 / RAD
	end
	-- a leg on its cycle: the ankle x * T ahead of the hip, as low as the leg allows (max drop), lifted in the swing;
	-- the foot flat while planted, toes down in the swing
	local function legIK(c, I, up, low, foot, ph, D, S, dropMax, liftH)
		local x, lf = gaitFn(ph, D)
		local T = D * S * 0.5
		local L1, L2, a10, a20 = c.legL1, c.legL2, c.legA1, c.legA2
		local dz = x * T
		local drop = min(dropMax, sqrt(max(0.01, ((L1 + L2) * 0.985) ^ 2 - dz * dz))) - lf * liftH
		local a1, a2 = ik2(L1, L2, dz, drop, 1)
		local tw = -(a1 - a10)
		local sw = -(a2 - a20)
		E(c, up, tw, 0, 0)
		E(c, low, sw - tw, 0, 0)
		E(c, foot, -sw + lf * 30, 0, 0)
	end
	-- the body height that keeps the planted hind feet on the floor (root move dy); between stances (the run's
	-- flight) an arc from lift-off to touch-down. ph2 = the second leg's phase offset.
	local function bodyDy(c, I, ph, ph2, D, S, dropMax, fly)
		local T = D * S * 0.5
		local L = (c.legL1 + c.legL2) * 0.985
		local base = c.py[I.foot_l] - c.py[I.leg_l_up]
		local best
		for k = 1, 2 do
			local x, lf = gaitFn(k == 1 and ph or ph + ph2, D)
			if lf == 0 then
				local dz = x * T
				local dy = base + min(dropMax, sqrt(max(0.01, L * L - dz * dz)))
				if not best or dy > best then best = dy end
			end
		end
		if best then return best end
		local dyEnd = base + min(dropMax, sqrt(max(0.01, L * L - T * T)))
		local u = ph / (2 * pi)
		u = u - floor(u)
		local u0, u1 = D, 1 - ph2 / (2 * pi)                 -- the last lift-off .. the first touch-down
		local f = clamp((u - u0) / max(u1 - u0, 1e-3), 0, 1)
		return dyEnd + fly * sin(pi * f)
	end
	local function legGeom(c, I)
		if c.legL1 then return end
		local h, k, a = I.leg_l_up, I.leg_l_low, I.foot_l
		local dz1, dy1 = c.pz[k] - c.pz[h], c.py[h] - c.py[k]
		local dz2, dy2 = c.pz[a] - c.pz[k], c.py[k] - c.py[a]
		c.legL1, c.legL2 = sqrt(dz1 * dz1 + dy1 * dy1), sqrt(dz2 * dz2 + dy2 * dy2)
		c.legA1, c.legA2 = ATAN2(dz1, dy1) / RAD, ATAN2(dz2, dy2) / RAD
		local s, e, w = I.arm_l_up, I.arm_l_low, I.hand_l
		dz1, dy1 = c.pz[e] - c.pz[s], c.py[s] - c.py[e]
		dz2, dy2 = c.pz[w] - c.pz[e], c.py[e] - c.py[w]
		c.armL1, c.armL2 = sqrt(dz1 * dz1 + dy1 * dy1), sqrt(dz2 * dz2 + dy2 * dy2)
		c.armA1, c.armA2 = ATAN2(dz1, dy1) / RAD, ATAN2(dz2, dy2) / RAD
	end

	-- both hind legs on one cycle whose parameters blend from the walk (w = 0: alternating, half the cycle planted)
	-- to the run (w = 1: bounding together, a short stance and a flight); sets c.bodyDy (the root height)
	local function gaitLegs(c, I, ph, S, w)
		local D, off = lerp(W_D, R_D, w), lerp(pi, 0.4, w)
		local drop, liftH = lerp(W_DROP, R_DROP, w), lerp(W_LIFT, R_LIFT, w)
		legIK(c, I, I.leg_l_up, I.leg_l_low, I.foot_l, ph, D, S, drop, liftH)
		legIK(c, I, I.leg_r_up, I.leg_r_low, I.foot_r, ph + off, D, S, drop, liftH)
		c.bodyDy = bodyDy(c, I, ph, off, D, S, drop, R_FLY * w)
	end
	local function walkPose(c, a, I, v, legs)
		local ph, time, seed = a.phase, a.time, a.seed
		local S = MonsterStride(v)
		local k = clamp(v / MONSTER_ANIM.walkSpeed, 0, 1)
		local sp = sin(ph)
		local hunch = 12 + 6 * k
		legGeom(c, I)
		E(c, I.pelvis, 0, 6 * sp * k, 1.5 * sp * k)
		E(c, I.torso, hunch + 2 * sin(2 * ph), -7 * sp * k, -2 * sp * k)
		if legs ~= false then gaitLegs(c, I, ph, S, 0) end
		-- arms hang and swing loosely against the legs, the forearms lagging behind
		local sw = 22 * k + 6
		hangArms(c, I, hunch, 6 - sw * sp, 6 + sw * sp, 5)
		E(c, I.arm_l_low, -12 - 14 * cos(ph - 0.6), 0, 0); E(c, I.arm_r_low, -12 + 14 * cos(ph - 0.6), 0, 0)
		flex(c, I.hand_l, 1, 8 + 10 * sin(ph - 1), 6); flex(c, I.hand_r, -1, 8 - 10 * sin(ph - 1), 6)
		-- the head carried low and forward, swaying side to side with the stride
		headLook(c, I, a, 34, -hunch - 32 + 4 * sin(2 * ph), 12 * sin(ph) + 4 * twitch(time, 1.1, seed), 6 * sin(ph + 0.5))
		E(c, I.jaw, 8 + 6 * sin(time * 2.3 + seed), 0, 0)
		c.lift = 0
	end
	local function runPose(c, a, I, v, legs)
		local ph = a.phase
		local S = MonsterStride(v)
		local hunch = 62
		legGeom(c, I)
		-- hind legs bound almost together (the right one 0.4 rad behind), a short stance and a long flight
		if legs ~= false then gaitLegs(c, I, ph, S, 1) end
		E(c, I.torso, hunch + 6 * sin(2 * ph + 0.5), -4 * sin(ph), 0)
		-- the arms half a cycle off the legs: a first guess here (reach ahead, rake back), placed by IK after the
		-- body is solved (see armPass)
		for side = 1, 2 do
			local up, low, hand, sd = I.arm_l_up, I.arm_l_low, I.hand_l, 1
			local p = ph + pi
			if side == 2 then up, low, hand, sd, p = I.arm_r_up, I.arm_r_low, I.hand_r, -1, ph + pi + 0.4 end
			local x, lf = gaitFn(p, R_AD)
			E(c, up, -hunch - (40 + 42 * x) - lf * 25, 0, sd * 10)
			E(c, low, -30 * (1 - lf) - lf * 70, 0, 0)
			E(c, hand, 20 - 30 * x + lf * 30, 0, sd * 12)
		end
		headLook(c, I, a, 38, -hunch - 36, 3 * sin(ph), 0)
		E(c, I.jaw, 26 + 12 * sin(2 * ph), 0, 0)
		c.lift = 0
	end
	-- after the body is solved: the run's arms by IK. In the arm's stance the claws are planted on the floor,
	-- moving from R_AREACH ahead of the shoulder to R_ABACK behind it; in the swing the arm folds and reaches forward
	-- again, lifted. Blended with the pose's own arms by c.ikw (the walk -> run blend weight).
	local function armPass(c, a, I)
		local w = c.ikw
		local ph = a.phase
		for side = 1, 2 do
			local up, low, hand = I.arm_l_up, I.arm_l_low, I.hand_l
			local p = ph + pi
			if side == 2 then up, low, hand, p = I.arm_r_up, I.arm_r_low, I.hand_r, ph + pi + 0.4 end
			-- the shoulder pivot in the root frame (after the ground snap)
			local _, sy_, sz_ = qrot(c.wx[up], c.wy[up], c.wz[up], c.ww[up], c.dx[up], c.dy[up], c.dz[up])
			local shy, shz = c.cy[up] - sy_, c.cz[up] - sz_
			local x, lf = gaitFn(p, R_AD)
			local tz = shz + R_ABACK + (R_AREACH - R_ABACK) * (x + 1) * 0.5
			local ty = 0.72 + lf * 0.9                      -- wrist height: the claws (~0.5 below it) touch the floor
			local a1, a2 = ik2(c.armL1, c.armL2, tz - shz, shy - ty, -1)
			local ti = I.torso
			local tp = 2 * ATAN2(c.wx[ti], c.ww[ti]) / RAD        -- the torso's (mostly pitch) world angle
			local uw = -(a1 - c.armA1)
			local fw = -(a2 - c.armA2)
			local qx, qy, qz, qw = qaxis(1, 0, 0, uw - tp)
			local bx, by, bz, bw = qaxis(0, 0, 1, (side == 1 and 1 or -1) * 8)
			qx, qy, qz, qw = qmul(qx, qy, qz, qw, bx, by, bz, bw)
			c.lx[up], c.ly[up], c.lz[up], c.lw[up] = qnlerp(c.lx[up], c.ly[up], c.lz[up], c.lw[up], qx, qy, qz, qw, w)
			qx, qy, qz, qw = qaxis(1, 0, 0, fw - uw)
			c.lx[low], c.ly[low], c.lz[low], c.lw[low] = qnlerp(c.lx[low], c.ly[low], c.lz[low], c.lw[low], qx, qy, qz, qw, w)
			-- claws pointing forward-down when planted, curled back in the swing
			qx, qy, qz, qw = qaxis(1, 0, 0, -55 - fw + lf * 60)
			c.lx[hand], c.ly[hand], c.lz[hand], c.lw[hand] = qnlerp(c.lx[hand], c.ly[hand], c.lz[hand], c.lw[hand], qx, qy, qz, qw, w)
		end
	end
	local LA, LB = {}, {}
	local function saveTo(c, buf)
		for i = 1, c.n do
			local b = i * 8
			buf[b], buf[b + 1], buf[b + 2], buf[b + 3] = c.lx[i], c.ly[i], c.lz[i], c.lw[i]
			buf[b + 4], buf[b + 5], buf[b + 6] = c.ox[i], c.oy[i], c.oz[i]
		end
		buf[0] = c.lift
	end
	local function locomotion(c, a, I, v)
		local w = smooth((v - MONSTER_ANIM.blend0) / (MONSTER_ANIM.blend1 - MONSTER_ANIM.blend0))
		c.ikw = w
		if w <= 0 then walkPose(c, a, I, v) c.snap = nil gmove(c, 0, c.bodyDy, 0) return end
		if w >= 1 then runPose(c, a, I, v) c.ikw = 1 c.snap = nil gmove(c, 0, c.bodyDy, 0) return end
		walkPose(c, a, I, v, false); saveTo(c, LA)
		reset(c)
		runPose(c, a, I, v, false); saveTo(c, LB)
		c.ikw = w
		for i = 1, c.n do
			local b = i * 8
			c.lx[i], c.ly[i], c.lz[i], c.lw[i] = qnlerp(LA[b], LA[b + 1], LA[b + 2], LA[b + 3], LB[b], LB[b + 1], LB[b + 2], LB[b + 3], w)
			c.ox[i], c.oy[i], c.oz[i] = lerp(LA[b + 4], LB[b + 4], w), lerp(LA[b + 5], LB[b + 5], w), lerp(LA[b + 6], LB[b + 6], w)
		end
		gaitLegs(c, I, a.phase, MonsterStride(v), w)     -- (the legs were left at rest by both poses)
		c.lift = 0
		c.snap = nil
		gmove(c, 0, c.bodyDy, 0)
	end

	local function demon(c, a, I)
		local st, t, ph, time, seed = a.st, a.t, a.phase, a.time, a.seed
		c.snap = "feet"
		local br = sin(time * 1.15 + seed)                      -- slow breathing
		if st == "walk" or st == "run" then
			-- one speed-driven gait: the stalking walk up to 7.5 m/s, the gallop from 10.5, blended between
			local v = a.speed
			if v < 0 then v = (st == "run") and MONSTER_ANIM.runSpeed or MONSTER_ANIM.walkSpeed end
			locomotion(c, a, I, v)
		elseif st == "crawl" then
			crawlPose(c, a, I, clamp((a.speed or 0) / 1.0, 0, 1))
		elseif st == "crouch" then
			-- a low creep on its legs: knees deep, body bent far over, the long arms trailing to the floor
			local hunch = 58
			local mv = clamp((a.speed or 0) / 1.5, 0, 1)
			local s = sin(ph) * mv
			E(c, I.leg_l_up, -74 - 14 * s, 0, 4); E(c, I.leg_r_up, -74 + 14 * s, 0, -4)
			E(c, I.leg_l_low, 108 + 10 * s, 0, 0); E(c, I.leg_r_low, 108 - 10 * s, 0, 0)
			E(c, I.foot_l, -30, 0, 0); E(c, I.foot_r, -30, 0, 0)
			E(c, I.torso, hunch + 2 * br, -6 * s, 0)
			hangArms(c, I, hunch, 30 + 10 * s, 30 - 10 * s, 10)
			E(c, I.arm_l_low, -12 + 20 * s, 0, 0); E(c, I.arm_r_low, -12 - 20 * s, 0, 0)
			E(c, I.hand_l, -50, 0, 0); E(c, I.hand_r, -50, 0, 0)
			E(c, I.hand_l, 0, 90, 0); E(c, I.hand_r, 0, -90, 0)            -- claws trailing flat over the floor
			headLook(c, I, a, 26, -hunch - 32 + 6 * twitch(time, 1.0, seed), 14 * twitch(time, 0.7, seed + 2), 0)
			E(c, I.jaw, 6 + 4 * br, 0, 0)
		elseif st == "swing_l" or st == "swing_r" then
			-- a big claw swipe: wind up overhead and back (0 - 0.22 s), rake forward and down across the body
			-- (0.22 - 0.36), follow through and recover (0.36 - 0.6). sd = +1 for the left arm.
			local sd = st == "swing_l" and 1 or -1
			local up, low, hand = I.arm_l_up, I.arm_l_low, I.hand_l
			local oup, olow, ohand = I.arm_r_up, I.arm_r_low, I.hand_r
			if sd < 0 then up, low, hand, oup, olow, ohand = oup, olow, ohand, up, low, hand end
			local x = t / SW
			local wind = smooth(x / 0.36)                         -- 0 -> 1 over the wind-up
			local strike = smooth((x - 0.36) / 0.24)              -- the rake
			local rec = smooth((x - 0.62) / 0.38)                 -- recovery
			local hunch = 18 + 16 * strike - 14 * rec
			stanceLegs(c, I, 10 + 6 * strike)
			E(c, I.leg_l_up, -10 * sd * strike, 0, 0); E(c, I.leg_r_up, 10 * sd * strike, 0, 0)
			E(c, I.torso, hunch, (22 * wind - 50 * strike + 28 * rec) * sd, (-6 * wind + 10 * strike - 4 * rec) * sd)
			-- the swinging arm: pitch from hanging (0) to overhead (-175) then down across to -35, roll out then in
			local pit = -175 * wind + 140 * strike + 35 * rec
			local rol = (35 * wind - 55 * strike + 20 * rec) * sd
			E(c, up, -hunch + pit, (-20 * strike + 20 * rec) * sd, rol)
			E(c, low, -55 * wind + 45 * strike + 10 * rec, 0, 0)
			flex(c, hand, sd, -35 * wind + 60 * strike - 25 * rec, 20 * wind - 20 * rec)
			-- the other arm swings back for balance
			E(c, oup, -hunch + 30 * strike - 30 * rec, 0, -12 * sd)
			E(c, olow, -25, 0, 0)
			flex(c, ohand, -sd, 10, 8)
			headLook(c, I, a, 16, -hunch - 18 - 8 * strike, 20 * sd * strike, 0)
			E(c, I.jaw, 10 + 30 * strike * (1 - rec), 0, 0)
		elseif st == "grab" then
			-- both hands shoot forward (0 - 0.3 s), claws open, then close together (0.3 - 0.5)
			local x = t / GR
			local reach = smooth(x / 0.6)
			local close = smooth((x - 0.6) / 0.4)
			local hunch = 20 + 16 * reach
			stanceLegs(c, I, 10 + 8 * reach)
			E(c, I.leg_l_up, -14 * reach, 0, 0)
			E(c, I.torso, hunch, 0, 0)
			E(c, I.arm_l_up, -hunch - 80 * reach, 0, 14 * (1 - reach) - 4 * close)
			E(c, I.arm_r_up, -hunch - 80 * reach, 0, -14 * (1 - reach) + 4 * close)
			E(c, I.arm_l_up, 0, -24 * close, 0); E(c, I.arm_r_up, 0, 24 * close, 0)
			E(c, I.arm_l_low, -10 - 12 * close, 0, 0); E(c, I.arm_r_low, -10 - 12 * close, 0, 0)
			flex(c, I.hand_l, 1, -40 * reach + 95 * close, 20 * reach - 20 * close)
			flex(c, I.hand_r, -1, -40 * reach + 95 * close, 20 * reach - 20 * close)
			headLook(c, I, a, 18, -hunch - 18, 0, 0)
			E(c, I.jaw, 10 + 35 * reach - 20 * close, 0, 0)
		elseif st == "hold" then
			-- holding a victim at chest height about 1 m ahead: arms forward, claws closed round it from both
			-- sides; the maw works as if about to bite, the held thing struggles (slight shake)
			local hunch = 22
			local sh = 3 * sin(time * 9 + seed) * sin(time * 2.1)
			stanceLegs(c, I, 12)
			E(c, I.leg_r_up, -8, 0, 0)
			E(c, I.torso, hunch + br, sh * 0.5, 0)
			E(c, I.arm_l_up, -hunch - 36 + sh, -14, 6); E(c, I.arm_r_up, -hunch - 36 - sh, 14, -6)
			E(c, I.arm_l_low, -48, 0, 0); E(c, I.arm_r_low, -48, 0, 0)
			E(c, I.hand_l, 0, -40, 0); E(c, I.hand_r, 0, 40, 0)
			headLook(c, I, a, 14, -hunch - 8 + 6 * twitch(time, 1.5, seed), 8 * twitch(time, 0.9, seed + 1), 0)
			E(c, I.jaw, 25 + 20 * (0.5 + 0.5 * sin(time * 3.1 + seed)), 0, 0)
		elseif st == "scream" then
			-- the echolocation call (1.2 s): rears up, back arched, head thrown back, maw gaping up, arms flung out:
			-- the left arm wide and low, claws splayed, the right arm bent at the elbow, claws hooked; shaking
			local k = smooth(t / 0.28) - smooth((t - SC + 0.3) / 0.3)
			local sh = (t > 0.2 and t < SC - 0.2) and sin(time * 47 + seed) * k or 0
			stanceLegs(c, I, 8 + 4 * k)
			E(c, I.leg_l_up, -8 * k, 0, 3 * k); E(c, I.leg_r_up, 6 * k, 0, -3 * k)
			E(c, I.torso, 16 * (1 - k) - 8 * k, 8 * k, 3 * sh)
			E(c, I.neck, -18 * k + 2 * sh, 0, 0)
			E(c, I.head, -28 * k + 3 * sh, -6 * k, 5 * k)
			E(c, I.jaw, 8 + 54 * k + 4 * sh, 0, 0)
			E(c, I.arm_l_up, -16 * (1 - k) - 10 * k, 0, 27 * k + 4)
			E(c, I.arm_l_low, -14 * k, 0, 10 * k)
			flex(c, I.hand_l, 1, -24 * k, 26 * k)
			E(c, I.arm_r_up, -16 * (1 - k) + 4 * k, 0, -16 * k - 4)
			E(c, I.arm_r_low, -52 * k, 14 * k, 0)
			flex(c, I.hand_r, -1, 34 * k, 22 * k)
		elseif st == "dead" then
			-- knees buckle, then it pitches forward onto its face, arms flung out
			local k1 = smooth(t / 0.45)
			local k2 = smooth((t - 0.3) / 0.7)
			E(c, I.leg_l_up, -60 * k1, 0, 8 * k1); E(c, I.leg_r_up, -50 * k1, 0, -10 * k1)
			E(c, I.leg_l_low, 90 * k1, 0, 0); E(c, I.leg_r_low, 80 * k1, 0, 0)
			E(c, I.torso, 20 * k1, 0, 8 * k2)
			E(c, I.arm_l_up, -140 * k2, 0, 30 * k2); E(c, I.arm_r_up, -120 * k2, 0, -45 * k2)
			E(c, I.arm_l_low, -15 * k2, 0, 0); E(c, I.arm_r_low, -30 * k2, 0, 0)
			E(c, I.neck, 10 * k2, 30 * k2, 0)
			E(c, I.head, 0, 40 * k2, 0)
			E(c, I.jaw, 35 * k2, 0, 0)
			gpivot(c, 0, 0, 0.4)
			gpost(c, 1, 0, 0, 84 * k2)
			c.snap = "all"
		else
			-- idle: hunched, swaying slightly, slow breathing, the head twitching from sound to sound, fingers flexing
			local hunch = 20
			stanceLegs(c, I, 12)
			E(c, I.pelvis, 0, 3 * sin(time * 0.4 + seed), 1 * br)
			E(c, I.torso, hunch + 3 * br, 0, -1.5 * br)
			hangArms(c, I, hunch, 6 + 2 * br, 6 - 2 * br, 4)
			E(c, I.arm_l_low, -8, 0, 0); E(c, I.arm_r_low, -8, 0, 0)
			local f1, f2 = twitch(time, 1.4, seed + 5), twitch(time, 1.1, seed + 9)
			flex(c, I.hand_l, 1, 18 * f1, 10 + 8 * f2); flex(c, I.hand_r, -1, 18 * f2, 10 + 8 * f1)
			headLook(c, I, a, 24, -hunch - 24 + 12 * twitch(time, 0.9, seed),
				28 * twitch(time, 0.6, seed + 3), 18 * twitch(time, 0.5, seed + 4))
			E(c, I.jaw, 6 + 5 * (0.5 + 0.5 * br), 0, 0)
		end
	end

	-- ---------------------------------------------------------------- headroom: blend toward the crawl
	-- The state pose is solved first; if its top pokes above a.headroom, the pose is blended toward the crawl pose
	-- (same phase and speed) by the smallest weight e (0..1) that brings the top under the headroom (bisection, then
	-- a secant step so e varies continuously with the headroom). The arms then blend further toward the crawl's
	-- planted arms only if a hand goes through the floor or above the headroom (smallest weight that fixes it). In
	-- the one-shot states (swing / grab / hold / scream) the arms start from the action (weight 0) and the head and
	-- jaw always keep it.
	-- Below the crawl's own top (~1.6 m) the full crawl is used. Dead is never blended.
	local ACT = {swing_l = true, swing_r = true, grab = true, hold = true, scream = true}
	local ARMS = {arm_l_up = true, arm_l_low = true, hand_l = true, arm_r_up = true, arm_r_low = true, hand_r = true}
	local HEADS = {head = true, jaw = true}
	local SA, SB = {}, {}                -- saved local pose: [i*8 + 0..6] = lx, ly, lz, lw, ox, oy, oz; lift at [0]
	local function save(c, buf)
		for i = 1, c.n do
			local b = i * 8
			buf[b], buf[b + 1], buf[b + 2], buf[b + 3] = c.lx[i], c.ly[i], c.lz[i], c.lw[i]
			buf[b + 4], buf[b + 5], buf[b + 6] = c.ox[i], c.oy[i], c.oz[i]
		end
		buf[0] = c.lift
	end
	-- the crawl's arms rebuilt for the torso's CURRENT pitch tp (deg): the same world angles as in the crawl, so a
	-- partly lowered body gets arms angled down to the floor (never swung up) and the blend toward them is monotonic
	local function armTarget(nm, tp)
		local side = (nm == "arm_l_up" or nm == "arm_l_low" or nm == "hand_l") and 1 or -1
		local a1 = side > 0 and CRW[1] or CRW[2]
		local a2 = side > 0 and CRW[3] or CRW[4]
		local x, y, z, w
		if nm == "arm_l_up" or nm == "arm_r_up" then
			x, y, z, w = qaxis(1, 0, 0, a1 - tp)
			local bx, by, bz, bw = qaxis(0, 0, 1, side * CR_OUT)
			return qmul(x, y, z, w, bx, by, bz, bw)
		elseif nm == "arm_l_low" or nm == "arm_r_low" then
			return qaxis(1, 0, 0, a2 - a1)
		end
		x, y, z, w = qaxis(1, 0, 0, -90 - a2)
		local bx, by, bz, bw = qaxis(0, 0, 1, -side * CR_OUT * 0.8)
		x, y, z, w = qmul(x, y, z, w, bx, by, bz, bw)
		bx, by, bz, bw = qaxis(0, 1, 0, side * 90)
		return qmul(x, y, z, w, bx, by, bz, bw)
	end
	-- e: body weight; ea: arm weight; one-shot states keep their head and jaw
	local function blend(c, e, act, ea)
		local tp = 0
		for i = 1, c.n do
			local b = i * 8
			local nm = c.name[i]
			local w = e
			if ARMS[nm] then w = ea elseif act and HEADS[nm] then w = 0 end
			if ARMS[nm] and w > 0 then
				local tx, ty, tz, tw = armTarget(nm, tp)
				c.lx[i], c.ly[i], c.lz[i], c.lw[i] = qnlerp(SA[b], SA[b + 1], SA[b + 2], SA[b + 3], tx, ty, tz, tw, w)
			else
				c.lx[i], c.ly[i], c.lz[i], c.lw[i] = qnlerp(SA[b], SA[b + 1], SA[b + 2], SA[b + 3], SB[b], SB[b + 1], SB[b + 2], SB[b + 3], w)
			end
			if nm == "torso" then tp = 2 * math.atan2(c.lx[i], c.lw[i]) / RAD end      -- (mostly a pitch)
			c.ox[i], c.oy[i], c.oz[i] = lerp(SA[b + 4], SB[b + 4], w), lerp(SA[b + 5], SB[b + 5], w), lerp(SA[b + 6], SB[b + 6], w)
			c.ab[i] = false
		end
		c.lift = lerp(SA[0], SB[0], e)
		c.snap = "feet"
	end
	-- lowest and highest hull point of the solved pose
	local function extremes(c)
		local lo, hi = 1e9, -1e9
		for i = 1, c.n do
			local h = c.hull[i]
			for k = 1, #h, 3 do
				local _, vy = qrot(c.wx[i], c.wy[i], c.wz[i], c.ww[i], h[k], h[k + 1], h[k + 2])
				local y = c.cy[i] + vy
				if y > hi then hi = y end
				if y < lo then lo = y end
			end
		end
		return lo, hi
	end
	local function top(c)
		local _, hi = extremes(c)
		return hi
	end
	-- smallest w in [0, 1] with bad(w) <= 0 (bad decreasing in w, about linearly; bad(0) = b0 > 0 known): regula
	-- falsi (Illinois) for a few steps from a warm start w0 (last frame's answer, may be nil), then the safe end of
	-- the bracket if the last guess still misses by > 1 cm. Returns the w it left set.
	local function search(c, set, bad, b0, w0)
		local lo, hi, blo, bhi = 0, 1, b0, nil
		if w0 and w0 > 0.001 and w0 < 0.999 then
			set(w0)
			local bw = bad()
			if bw <= 0.01 and bw >= -0.01 then return w0 end
			if bw > 0 then lo, blo = w0, bw else hi, bhi = w0, bw end
		end
		if not bhi then
			set(1)
			bhi = bad()
			if bhi > 0 then                                -- even the full blend does not fix it: keep the better end
				if bhi >= b0 then set(0) return 0 end
				return 1
			end
		end
		local side = 0
		for _ = 1, 4 do
			local m = lo + (hi - lo) * clamp(blo / (blo - bhi), 0.02, 0.98)
			set(m)
			local bm = bad()
			if bm > 0.01 then
				lo, blo = m, bm
				if side == 1 then bhi = bhi * 0.5 end
				side = 1
			elseif bm < -0.01 then
				hi, bhi = m, bm
				if side == -1 then blo = blo * 0.5 end
				side = -1
			else
				return m                                   -- within 1 cm
			end
		end
		set(hi)
		return hi
	end
	local FLOOR = -0.05
	local fc, fact, fe, froom
	local function setBody(w) fe = w blend(fc, w, fact, fact and 0 or w) solve(fc) end
	local function setArms(w) blend(fc, fe, fact, fact and w or fe + (1 - fe) * w) solve(fc) end
	local function badTop() return top(fc) - froom end
	local function badBoth()
		local lo, hi = extremes(fc)
		return max(hi - froom - 0.03, FLOOR - lo)
	end
	local function fullCrawlTop(c)
		blend(c, 1, false, 1); solve(c)
		return top(c)
	end
	local function fitHeadroom(c, a, I, room, t0, out)
		fc, fact, froom = c, ACT[a.st] or false, room
		save(c, SA)
		reset(c)
		crawlPose(c, a, I, clamp((a.speed or 0) / 1.0, 0, 1))
		save(c, SB)
		if room < 2.2 then froom = max(room, fullCrawlTop(c) + 0.02) end   -- (a room below the crawl: the floor still counts)
		local e = search(c, setBody, badTop, t0 - froom, out.__hre)
		out.__hre = e
		local b0 = badBoth()                               -- a hand through the floor / above the room: arms follow
		local ea = 0
		if b0 > 0.005 then ea = search(c, setArms, badBoth, b0, out.__hra) end
		out.__hra = ea
	end

	-- ---------------------------------------------------------------- entry point
	local HAS = {}
	for _, s in ipairs(MONSTER_STATES) do HAS[s] = true end
	local A = {}
	function MonsterPose(a, out)
		local c = rigFor("demon")
		if not c then return out end
		A.st = a.st or "idle"
		if not HAS[A.st] then A.st = "idle" end
		A.t, A.phase, A.speed = a.t or 0, a.phase or 0, a.speed or -1     -- (-1: not given)
		A.look, A.time, A.seed = a.look or 0, a.time or 0, (a.seed or 0) % 97
		reset(c)
		demon(c, A, c.idx)
		solve(c)
		if c.ikw > 0 then armPass(c, A, c.idx) solve(c) end        -- the run's claws planted by IK
		local room = a.headroom
		if room and A.st ~= "dead" then
			local t0 = top(c)
			if t0 > room then fitHeadroom(c, A, c.idx, room, t0, out) end
		end
		for i = 1, c.n do
			local nm = c.name[i]
			local tr = out[nm]
			if tr and tr.pos and tr.rot then
				local p, q = tr.pos, tr.rot
				p[1], p[2], p[3] = c.cx[i], c.cy[i], c.cz[i]
				q[1], q[2], q[3], q[4] = c.wx[i], c.wy[i], c.wz[i], c.ww[i]
			else
				out[nm] = Transform(Vec(c.cx[i], c.cy[i], c.cz[i]), Quat(c.wx[i], c.wy[i], c.wz[i], c.ww[i]))
			end
		end
		return out
	end
end
