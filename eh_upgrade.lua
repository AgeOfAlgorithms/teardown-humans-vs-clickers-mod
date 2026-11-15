-- Humans vs Clickers: the clickers' upgrades, bought with the McPuppet Inventory System's gold (the user, 2026-11-15).
-- Only while the host runs that mod (inventory.present). A clicker opens its own upgrade screen with the inventory's
-- key (inventory.key.open, "i") - in the lobby once on the Clickers team, and in a round as a clicker - and buys:
--   stamina   600 a level, +10 % of its bar each, up to 5 (+50 %)         (eh_monster.lua ehStaminaMax)
--   attack    600 a level, +5 damage a strike (of a human's 100) each, up to 5 (+25)   (eh_combat.lua hurtHuman)
--   djump    1200, a second jump in mid-air, its wings flap                (eh_monster.lua monsterMove)
--   laser    2500, hold LMB 2 s and let go: a beam from its maw            (eh_combat.lua, eh_laser.lua)
--   echo      600 a level, its echolocation cooldown -1 s after a miss and -2 s after a hit, up to 5 (eh_monster.lua)
-- They show on its body (monster_visual.lua): attack power thicker arms and shoulders, the double jump wings, the
-- laser a glowing maw; stamina shows nothing (the user, 2026-11-15).
-- Paid through the inventory's all-or-nothing spend (inventory.spend.<p> "token:n:reason", answered in
-- inventory.spent.<token> = "ok" / "no"). Kept by player name in savegame.mod.eh.up, as long as the inventory keeps
-- its gold: cleared whenever inventory.session changes (its NEW SESSION, or every map with its "Reset every map").
-- Published as shared.ehUp[p] = {stamina, attack, djump, laser, echo} (ehUpLevel in eh_monster.lua reads it).
--   server: ehUpServerTick(); server.ehUpBuy(p, id) (ServerCall from the screen)
--   client: ehUpClientTick(); ehUpDraw()   (ehUpOpen(): the screen is up)

UPGRADES = {
	{id = "stamina", name = "Stamina", price = 600, max = 5, info = "+10 % stamina per level, up to +50 %."},
	{id = "attack", name = "Attack power", price = 600, max = 5, info = "+5 damage per strike per level, up to +25. Thicker arms and shoulders."},
	{id = "djump", name = "Double jump", price = 1200, max = 1, info = "Jump again in mid-air. Grows wings."},
	{id = "laser", name = "Laser beam", price = 2500, max = 1, info = "Hold LMB 2 s, let go: a beam from your maw. Takes all your stamina."},
	{id = "echo", name = "Faster echolocation", price = 600, max = 5, info = "Echolocation cooldown per level: -1 s after a miss, -2 s after a hit."},
}
local UPBY = {}
for _, u in ipairs(UPGRADES) do UPBY[u.id] = u end

local UP_SAVE = "savegame.mod.eh.up"

-- may player p shop now (any machine): the inventory runs, and p is a clicker in a round or on the Clickers team
function ehUpMayShop(p)
	if not GetBool("inventory.present") then return false end
	local e = shared.eh
	if e and (e.phase == "hide" or e.phase == "hunt") then return ehIsMonster(p) == true end
	return teamsGetTeamId ~= nil and teamsGetTeamId(p) == TEAM_MONSTER
end

----- server -----

local US = {pend = {}, n = 0, pubKey = nil, msg = {}, msgN = 0}

local function nameKey(p)
	return UP_SAVE .. ".p." .. (GetPlayerName(p):gsub("[^%w]", function(c) return string.format("_%02x", c:byte()) end))
end

local function level(p, id) return GetInt(nameKey(p) .. "." .. id) end

local function tell(p, text)
	US.msgN = US.msgN + 1
	US.msg[p] = {n = US.msgN, text = text}
	local c = {}
	for k, v in pairs(US.msg) do c[k] = v end
	shared.ehUpMsg = c
end

-- (ServerCall from a clicker's screen) buy one level of upgrade id for player p
function server.ehUpBuy(p, id)
	local u = UPBY[id]
	if not u or not IsPlayerValid(p) or not ehUpMayShop(p) then return end
	if level(p, id) >= u.max then return end
	for _, q in pairs(US.pend) do if q.p == p then return end end  -- (one purchase at a time)
	US.n = US.n + 1
	local token = string.format("ehup%d_%d", p, US.n)
	local k = "inventory.spend." .. p
	local entry = string.format("%s:%d:%s", token, u.price, (u.name:gsub(" ", "_")))
	local was = GetString(k)
	SetString(k, was == "" and entry or (was .. " " .. entry))
	US.pend[token] = {p = p, id = id, t = GetTime()}
end

-- (ServerCall) p's upgrade screen opened / closed: its clicks are not attacks meanwhile (echohunt.shop.<p>, read by
-- eh_combat.lua)
function server.ehUpShop(p, open)
	if IsPlayerValid(p) then SetBool("echohunt.shop." .. p, open == true) end
end

-- every frame: answers to purchases; the session the upgrades belong to; what everyone owns, published on change
function ehUpServerTick()
	local now = GetTime()
	local present = GetBool("inventory.present")
	local sess = GetString("inventory.session")
	if present and sess ~= "" and GetString(UP_SAVE .. ".session") ~= sess then   -- (a new inventory session: all reset)
		ClearKey(UP_SAVE .. ".p")
		SetString(UP_SAVE .. ".session", sess)
	end
	for token, q in pairs(US.pend) do
		local r = GetString("inventory.spent." .. token)
		if r == "ok" or r == "no" or now - q.t > 5 then
			ClearKey("inventory.spent." .. token)
			US.pend[token] = nil
			if r == "ok" and IsPlayerValid(q.p) then
				local k = nameKey(q.p) .. "." .. q.id
				SetInt(k, math.min(UPBY[q.id].max, GetInt(k) + 1))
				tell(q.p, "Bought " .. UPBY[q.id].name)
			elseif IsPlayerValid(q.p) then
				tell(q.p, r == "no" and "Not enough gold" or "The inventory didn't answer")
			end
		end
	end
	local t, key = {}, ""
	if present then
		for p in Players() do
			local l = {}
			for _, u in ipairs(UPGRADES) do l[u.id] = level(p, u.id); key = key .. l[u.id] end
			t[p] = l
			key = key .. "/" .. p .. ";"
		end
	end
	if key ~= US.pubKey then US.pubKey = key; shared.ehUp = t end
end

----- client -----

local UC = {open = false, msgN = nil, msg = "", msgT = -100}

function ehUpOpen() return UC.open end

function ehUpClientTick()
	local me = GetLocalPlayer()
	if not ehUpMayShop(me) then
		UC.open = false
		if UC.sent then UC.sent = false; ServerCall("server.ehUpShop", me, false) end
		return
	end
	local key = GetString("inventory.key.open")
	if key == "" then key = "i" end
	if InputPressed(key) or (UC.open and InputPressed("esc")) then UC.open = not UC.open and not InputPressed("esc") end
	if UC.sent ~= UC.open then UC.sent = UC.open; ServerCall("server.ehUpShop", me, UC.open) end
	local m = type(shared.ehUpMsg) == "table" and shared.ehUpMsg[me] or nil
	if UC.msgN == nil then UC.msgN = m and m.n or 0 end
	if m and m.n ~= UC.msgN then UC.msgN, UC.msg, UC.msgT = m.n, m.text, GetTime() end
end

-- the screen (client.draw): its gold, every upgrade with its level, price and a Buy button
function ehUpDraw()
	local me = GetLocalPlayer()
	if not UC.open or not ehUpMayShop(me) then
		if ehUpMayShop(me) and type(shared.eh) == "table" and (shared.eh.phase == "hide" or shared.eh.phase == "hunt") then
			UiPush()                                               -- (a reminder in a corner)
			UiTranslate(UiWidth() - 40, UiHeight() - 40)
			UiAlign("right middle")
			UiFont("regular.ttf", 20)
			UiColor(1, 0.85, 0.6, 0.7)
			UiText(string.upper(GetString("inventory.key.open") ~= "" and GetString("inventory.key.open") or "i") .. ": upgrades")
			UiPop()
		end
		return
	end
	UiMakeInteractive()
	local gold = GetInt("inventory.gold." .. me)
	local W, H = 760, 120 + 92 * #UPGRADES
	UiPush()
	UiTranslate(UiCenter() - W / 2, UiMiddle() - H / 2)
	UiColor(0.05, 0.03, 0.03, 0.88)
	UiRect(W, H)
	UiTranslate(24, 20)
	UiAlign("left top")
	UiFont("bold.ttf", 34)
	UiColor(1, 0.35, 0.3, 1)
	UiText("CLICKER UPGRADES")
	UiPush()
	UiTranslate(W - 48, 6)
	UiAlign("right top")
	UiFont("bold.ttf", 28)
	UiColor(1, 0.82, 0.3, 1)
	UiText(gold .. " gold")
	UiPop()
	UiTranslate(0, 62)
	for _, u in ipairs(UPGRADES) do
		local lvl = ehUpLevel(me, u.id)
		UiPush()
		UiFont("bold.ttf", 26)
		UiColor(1, 1, 1, 1)
		UiText(u.name .. (u.max > 1 and string.format("   %d / %d", lvl, u.max) or (lvl > 0 and "   owned" or "")))
		UiTranslate(0, 32)
		UiFont("regular.ttf", 20)
		UiColor(0.8, 0.8, 0.8, 1)
		UiText(u.info)
		UiPop()
		UiPush()
		UiTranslate(W - 48 - 190, 6)
		local maxed = lvl >= u.max
		local can = not maxed and gold >= u.price
		UiColor(can and 0.55 or 0.25, can and 0.12 or 0.12, can and 0.1 or 0.12, 1)
		UiRect(190, 54)
		UiColor(1, can and 1 or 0.6, can and 1 or 0.6, 1)
		UiFont("bold.ttf", 22)
		UiAlign("center middle")
		UiTranslate(95, 27)
		if maxed then UiText("MAX")
		elseif UiTextButton(string.format("Buy  %d", u.price), 190, 54) and can then ServerCall("server.ehUpBuy", me, u.id) end
		UiPop()
		UiTranslate(0, 92)
	end
	UiFont("regular.ttf", 22)
	if GetTime() - UC.msgT < 4 then UiColor(1, 0.85, 0.5, 1); UiText(UC.msg)
	else UiColor(0.7, 0.7, 0.7, 1); UiText("Gold: +120 a round won, +10 a human caught, -80 a round lost. " ..
		string.upper(GetString("inventory.key.open") ~= "" and GetString("inventory.key.open") or "i") .. " or Esc closes.") end
	UiPop()
end
