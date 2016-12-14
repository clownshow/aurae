local _G, _M = getfenv(0), {}
setfenv(1, setmetatable(_M, {__index=_G}))

do
	local f = CreateFrame'Frame'
	f:SetScript('OnEvent', function()
		_M[event](this)
	end)
	for _, event in {
		'ADDON_LOADED',
		'UNIT_COMBAT',
		'CHAT_MSG_COMBAT_HONOR_GAIN', 'CHAT_MSG_COMBAT_HOSTILE_DEATH', 'PLAYER_REGEN_ENABLED',
		'CHAT_MSG_SPELL_AURA_GONE_OTHER', 'CHAT_MSG_SPELL_BREAK_AURA',
		'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE', 'CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS',
		'SPELLCAST_STOP', 'SPELLCAST_INTERRUPTED', 'CHAT_MSG_SPELL_SELF_DAMAGE', 'CHAT_MSG_SPELL_FAILED_LOCALPLAYER',
		'PLAYER_TARGET_CHANGED', 'UPDATE_BATTLEFIELD_SCORE',
	} do f:RegisterEvent(event) end
end

CreateFrame('GameTooltip', 'aurae_Tooltip', nil, 'GameTooltipTemplate')

function Print(msg)
	DEFAULT_CHAT_FRAME:AddMessage('<aurae> ' .. msg)
end

_G.aurae_settings = {}

_G.aurae = {}
aurae.EFFECTS = {}

local WIDTH = 170
local HEIGHT = 16
local MAXBARS = 10

local COMBO = 0

local DR_CLASS = {
	["Bash"] = 1,
	["Hammer of Justice"] = 1,
	["Cheap Shot"] = 1,
	["Charge Stun"] = 1,
	["Intercept Stun"] = 1,
	["Concussion Blow"] = 1,

	["Fear"] = 2,
	["Howl of Terror"] = 2,
	["Seduction"] = 2,
	["Intimidating Shout"] = 2,
	["Psychic Scream"] = 2,

	["Polymorph"] = 3,
	["Sap"] = 3,
	["Gouge"] = 3,

	["Entangling Roots"] = 4,
	["Frost Nova"] = 4,

	["Freezing Trap"] = 5,
	["Wyvern String"] = 5,

	["Blind"] = 6,

	["Hibernate"] = 7,

	["Mind Control"] = 8,

	["Kidney Shot"] = 9,

	["Death Coil"] = 10,

	["Frost Shock"] = 11,
}

local GROUPS, timers = {}, {}

function CreateBar()

	local texture = [[Interface\Addons\aurae\bar]]
	local font, _, style = GameFontHighlight:GetFont()
	local fontsize = 11

	local f = CreateFrame('Frame', nil, UIParent)

	f.fadetime = .5

	f:SetHeight(HEIGHT)

	f.icon = f:CreateTexture()
	f.icon:SetWidth(HEIGHT)
	f.icon:SetPoint('TOPLEFT', 0, 0)
	f.icon:SetPoint('BOTTOMLEFT', 0, 0)
	f.icon:SetTexture[[Interface\Icons\INV_Misc_QuestionMark]]
	f.icon:SetTexCoord(.08, .92, .08, .92)

	f.statusbar = CreateFrame('StatusBar', nil, f)
	f.statusbar:SetPoint('TOPLEFT', f.icon, 'TOPRIGHT', 0, 0)
	f.statusbar:SetPoint('BOTTOMRIGHT', 0, 0)
	f.statusbar:SetStatusBarTexture(texture)
	f.statusbar:SetStatusBarColor(.5, .5, .5, 1)
	f.statusbar:SetMinMaxValues(0, 1)
	f.statusbar:SetValue(1)
	f.statusbar:SetBackdrop{bgFile=texture}
	f.statusbar:SetBackdropColor(.5, .5, .5, .3)

	f.spark = f.statusbar:CreateTexture(nil, 'OVERLAY')
	f.spark:SetTexture[[Interface\CastingBar\UI-CastingBar-Spark]]
	f.spark:SetWidth(16)
	f.spark:SetHeight(HEIGHT + 25)
	f.spark:SetBlendMode'ADD'

	f.text = f.statusbar:CreateFontString(nil, 'OVERLAY')
--	f.text:SetFontObject(GameFontHighlightSmallOutline)
	f.text:SetFontObject(GameFontHighlight)
	f.text:SetFont(font, fontsize, style)
	f.text:SetPoint('TOPLEFT', 2, 0)
	f.text:SetPoint('BOTTOMRIGHT', -2, 0)
	f.text:SetJustifyH'LEFT'
	f.text:SetText''

	f.timertext = f.statusbar:CreateFontString(nil, 'OVERLAY')
--	f.text:SetFontObject(GameFontHighlightSmallOutline)
	f.timertext:SetFontObject(GameFontHighlight)
	f.timertext:SetFont(font, fontsize, style)
	f.timertext:SetPoint('TOPLEFT', 2, 0)
	f.timertext:SetPoint('BOTTOMRIGHT', -2, 0)
	f.timertext:SetJustifyH'RIGHT'
	f.timertext:SetText''

	return f
end

function FadeBar(bar)
	if bar.fadeelapsed > bar.fadetime then
		bar:SetAlpha(0)
	else
		local t = bar.fadetime - bar.fadeelapsed
		local a = t / bar.fadetime * (bar.TIMER.UNIT == TARGET_ID and 1 or .7) * aurae_settings.alpha
		bar:SetAlpha(a)
	end
end

function UpdateBars()
	for _, group in GROUPS do
		for i = 1, MAXBARS do
			UpdateBar(group[i])
		end
	end
end

do
	local function formatTime(t)
		local h = floor(t / 3600)
		local m = floor((t - h * 3600) / 60)
		local s = t - (h * 3600 + m * 60)
		if h > 0 then
			return format('%d:%02d:02d', h, m, s)
		elseif m > 0 then
			return format('%d:%02d', m, s)
		elseif s < 10 then
			return format('%.1f', s)
		else
			return format('%.0f', s)
		end
	end

	function UpdateBar(bar)
		if not LOCKED then
			return
		end

		local timer = bar.TIMER

		if timer.stopped then
			if bar:GetAlpha() > 0 then
				bar.spark:Hide()
				bar.fadeelapsed = GetTime() - timer.stopped
				FadeBar(bar)
			end
		else
			bar:SetAlpha((timer.UNIT == TARGET_ID and 1 or .7) * aurae_settings.alpha)
			bar.icon:SetTexture([[Interface\Icons\]] .. (aurae.EFFECTS[timer.EFFECT].ICON or 'INV_Misc_QuestionMark'))
			bar.text:SetText(gsub(timer.UNIT, ':.*', ''))

			local fraction
			if timer.START then
				local duration = timer.END - timer.START
				local remaining = timer.END - GetTime()
				fraction = remaining / duration

				local invert = aurae_settings.invert and not timer.DR
				
				bar.statusbar:SetValue( invert and 1 - fraction or fraction)

				local sparkPosition = WIDTH * fraction
				bar.spark:Show()
				bar.spark:SetPoint('CENTER', bar.statusbar, invert and 'RIGHT' or 'LEFT', invert and -sparkPosition or sparkPosition, 0)

				bar.timertext:SetText(formatTime(remaining))
			else
				fraction = 1
				bar.statusbar:SetValue(1)
				bar.spark:Hide()
				bar.timertext:SetText()
			end
			local r, g, b
			if timer.DR == 1 then
				r, g, b = 1, 1, .3
			elseif timer.DR == 2 then
				r, g, b = 1, .6, 0
			elseif timer.DR == 3 then
				r, g, b = 1, .3, .3
			else
				r, g, b = .3, 1, .3
			end
			if timer.UNIT ~= TARGET_ID then
				r, g, b = .5 * r + .2, .5 * g + .2, .5 * b + .2
			end
			bar.statusbar:SetStatusBarColor(r, g, b)
			bar.statusbar:SetBackdropColor(r, g, b, .3)
		end
	end
end

function UnlockBars()
	LOCKED = false
	for etype, group in GROUPS do
		group:EnableMouse(1)
		for i = 1, MAXBARS do
			local f = group[i]
			f:SetAlpha(aurae_settings.alpha)
			f.statusbar:SetStatusBarColor(1, 1, 1)
			f.statusbar:SetValue(1)
			f.icon:SetTexture[[Interface\Icons\INV_Misc_QuestionMark]]
			f.text:SetText('aurae ' .. strlower(etype))
			f.timertext:SetText((aurae_settings.growth == 'up' and i or MAXBARS - i + 1))
			f.spark:Hide()
		end
	end
end

function LockBars()
	LOCKED = true
	for _, group in GROUPS do
		group:EnableMouse(0)
		for i = 1, MAXBARS do
			group[i]:SetAlpha(0)
		end
	end
end

do
	local factor = {1, 1/2, 1/4, 0}

	function DiminishedDuration(unit, effect, full_duration)
		local class = DR_CLASS[effect]
		if class then
			StartDR(effect, unit)
			return full_duration * factor[timers[class .. '@' .. unit].DR]
		else
			return full_duration
		end
	end
end

function UnitDebuffs(unit)
	local debuffs = {}
	local i = 1
	while UnitDebuff(unit, i) do
		aurae_Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
		aurae_Tooltip:SetUnitDebuff(unit, i)
		debuffs[aurae_TooltipTextLeft1:GetText()] = true
		i = i + 1
	end
	return debuffs
end

function SetActionRank(name, rank)
	local _, _, rank = strfind(rank or '', 'Rank (%d+)')
	if rank and aurae_RANKS[name] then
		aurae.EFFECTS[aurae_RANKS[name].EFFECT or name].DURATION = aurae_RANKS[name].DURATION[tonumber(rank)]
	end
end

do
	local casting = {}
	local last_cast
	local pending = {}

	do
		local orig = UseAction
		function _G.UseAction(slot, clicked, onself)
			if HasAction(slot) and not GetActionText(slot) then
				aurae_Tooltip:SetOwner(UIParent, 'ANCHOR_NONE')
				aurae_TooltipTextRight1:SetText()
				aurae_Tooltip:SetAction(slot)
				local name = aurae_TooltipTextLeft1:GetText()
				casting[name] = TARGET_ID
				SetActionRank(name, aurae_TooltipTextRight1:GetText())
			end
			return orig(slot, clicked, onself)
		end
	end

	do
		local orig = CastSpell
		function _G.CastSpell(index, booktype)
			local name, rank = GetSpellName(index, booktype)
			casting[name] = TARGET_ID
			SetActionRank(name, rank)
			return orig(index, booktype)
		end
	end

	do
		local orig = CastSpellByName
		function _G.CastSpellByName(text, onself)
			if not onself then
				casting[text] = TARGET_ID
			end
			return orig(text, onself)
		end
	end

	function CHAT_MSG_SPELL_FAILED_LOCALPLAYER()
		for effect in string.gfind(arg1, 'You fail to %a+ (.*):.*') do
			casting[effect] = nil
		end
	end

	function SPELLCAST_STOP()
		for effect, target in casting do
			if aurae.EFFECTS[effect] and aurae.EFFECTS[effect].ETYPE ~= 'BUFF' and (not IsPlayer(target) or EffectActive(effect, target)) then
				if pending[effect] then
					last_cast = nil
				else
					pending[effect] = {target=target, time=GetTime() + (aurae_RANKS[effect] and aurae_DELAYS[effect] or 0)}
					last_cast = effect
				end
			end
		end
		casting = {}
	end

	CreateFrame'Frame':SetScript('OnUpdate', function()
		for effect, info in pending do
			if GetTime() >= info.time + .5 then
				if (IsPlayer(info.target) or TARGET_ID ~= info.target or UnitDebuffs'target'[effect]) then
					StartTimer(effect, info.target, info.time)
				end
				pending[effect] = nil
			end
		end
	end)

	function AbortCast(effect, unit)
		for k, v in pending do
			if k == effect and v.target == unit then
				pending[k] = nil
			end
		end
	end

	function AbortUnitCasts(unit)
		for k, v in pending do
			if v.target == unit or not unit and not IsPlayer(v.target) then
				pending[k] = nil
			end
		end
	end

	function SPELLCAST_INTERRUPTED()
		if last_cast then
			pending[last_cast] = nil
		end
	end

	do
		local patterns = {
			'is immune to your (.*)%.',
			'Your (.*) missed',
			'Your (.*) was resisted',
			'Your (.*) was evaded',
			'Your (.*) was dodged',
			'Your (.*) was deflected',
			'Your (.*) is reflected',
			'Your (.*) is parried'
		}
		function CHAT_MSG_SPELL_SELF_DAMAGE()
			for _, pattern in patterns do
				local _, _, effect = strfind(arg1, pattern)
				if effect then
					pending[effect] = nil
					return
				end
			end
		end
	end
end

function CHAT_MSG_SPELL_AURA_GONE_OTHER()
	for effect, unit in string.gfind(arg1, '(.+) fades from (.+)%.') do
		AuraGone(unit, effect)
	end
end

function CHAT_MSG_SPELL_BREAK_AURA()
	for unit, effect in string.gfind(arg1, "(.+)'s (.+) is removed%.") do
		AuraGone(unit, effect)
	end
end

function ActivateDRTimer(effect, unit)
	for k, v in DR_CLASS do
		if v == DR_CLASS[effect] and EffectActive(k, unit) then
			return
		end
	end
	local timer = timers[DR_CLASS[effect] .. '@' .. unit]
	if timer then
		timer.START = GetTime()
		timer.END = timer.START + 15
	end
end

function AuraGone(unit, effect)
	if aurae.EFFECTS[effect] then
		if IsPlayer(unit) then
			AbortCast(effect, unit)
			StopTimer(effect .. '@' .. unit)
			if DR_CLASS[effect] then
				ActivateDRTimer(effect, unit)
			end
		elseif unit == UnitName'target' then
			-- TODO pet target (in other places too)
			local unit = TARGET_ID
			local debuffs = UnitDebuffs'target'
			for k, timer in timers do
				if timer.UNIT == unit and not debuffs[timer.EFFECT] then
					StopTimer(timer.EFFECT .. '@' .. timer.UNIT)
				end
			end
		end
	end
end

function CHAT_MSG_COMBAT_HOSTILE_DEATH()
	for unit in string.gfind(arg1, '(.+) dies') do -- TODO does not work when xp is gained
		if IsPlayer(unit) then
			UnitDied(unit)
		elseif unit == UnitName'target' and UnitIsDead'target' then
			UnitDied(TARGET_ID)
		end
	end
end

function CHAT_MSG_COMBAT_HONOR_GAIN()
	for unit in string.gfind(arg1, '(.+) dies') do
		UnitDied(unit)
	end
end

function UNIT_COMBAT()
	if GetComboPoints() > 0 then
		COMBO = GetComboPoints()
	end
end

function PlaceTimers()
	for _, timer in timers do
		if timer.shown and not timer.visible then
			local group = GROUPS[aurae.EFFECTS[timer.EFFECT].ETYPE]
			local up = aurae_settings.growth == 'up'
			for i = (up and 1 or MAXBARS), (up and MAXBARS or 1), (up and 1 or -1) do
				if group[i].TIMER.stopped then
					group[i].TIMER = timer
					timer.visible = true
					break
				end
			end
		end
	end
end

function UpdateTimers()
	local t = GetTime()
	for k, timer in timers do
		if timer.END and t > timer.END then
			StopTimer(k)
			if DR_CLASS[timer.EFFECT] and not timer.DR then
				ActivateDRTimer(timer.EFFECT, timer.UNIT)
			end
		end
	end
end

function EffectActive(effect, unit)
	return timers[effect .. '@' .. unit] and true or false
end

function StartTimer(effect, unit, start)
	local key = effect .. '@' .. unit
	local timer = timers[key] or {}
	timers[key] = timer

	timer.EFFECT = effect
	timer.UNIT = unit
	timer.START = start
	timer.shown = IsShown(unit)
	timer.END = timer.START

	local duration = aurae.EFFECTS[effect].DURATION + (bonuses[effect] and bonuses[effect](aurae.EFFECTS[effect].DURATION) or 0)

	if IsPlayer(unit) then
		timer.END = timer.END + DiminishedDuration(unit, effect, aurae.EFFECTS[effect].PVP_DURATION or duration)
	else
		timer.END = timer.END + duration
	end

	if aurae.EFFECTS[effect].COMBO then
		timer.END = timer.END + aurae.EFFECTS[effect].A * COMBO
	end

	timer.stopped = nil
	PlaceTimers()
end

function StartDR(effect, unit)

	local key = DR_CLASS[effect] .. '@' .. unit
	local timer = timers[key] or {}

	if not timer.DR or timer.DR < 3 then
		timers[key] = timer

		timer.EFFECT = effect
		timer.UNIT = unit
		timer.START = nil
		timer.END = nil
		timer.shown = timer.shown or IsShown(unit)
		timer.DR = min(3, (timer.DR or 0) + 1)

		PlaceTimers()
	end
end

function PLAYER_REGEN_ENABLED()
	AbortUnitCasts()
	for k, timer in timers do
		if not IsPlayer(timer.UNIT) then
			StopTimer(k)
		end
	end
end

function StopTimer(key)
	if timers[key] then
		timers[key].stopped = GetTime()
		timers[key] = nil
		PlaceTimers()
	end
end

function UnitDied(unit)
	AbortUnitCasts(unit)
	for k, timer in timers do
		if timer.UNIT == unit then
			StopTimer(k)
		end
	end
	PlaceTimers()
end

CreateFrame'Frame':SetScript('OnUpdate', RequestBattlefieldScoreData)

do
	local player, recent = {}, {}

	local function hostilePlayer(msg)
		local _, _, name = strfind(arg1, "^([^%s']*)")
		return name
	end

	local function addRecent(unit)
		local t = GetTime()

		recent[unit] = t

		for k, v in recent do
			if t - v > 30 then
				recent[k] = nil
			end
		end

		for _, timer in timers do
			if timer.UNIT == unit then
				timer.shown = true
			end
		end
		PlaceTimers()
	end

	function CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_BUFFS()
		if player[hostilePlayer(arg1)] == nil then player[hostilePlayer(arg1)] = true end -- wrong for pets
		for unit, effect in string.gfind(arg1, '(.+) gains (.+)%.') do
			if IsPlayer(unit) and aurae.EFFECTS[effect] then
				StartTimer(effect, unit, GetTime())
			end
		end
	end

	function CHAT_MSG_SPELL_PERIODIC_HOSTILEPLAYER_DAMAGE()
		if player[hostilePlayer(arg1)] == nil then player[hostilePlayer(arg1)] = true end -- wrong for pets
		for unit, effect in string.gfind(arg1, '(.+) is afflicted by (.+)%.') do
			if IsPlayer(unit) and aurae.EFFECTS[effect] then
				StartTimer(effect, unit, GetTime())
			end
		end
	end

	do
		local current
		function PLAYER_TARGET_CHANGED()
			local unit = UnitName'target'
			TARGET_ID = unit and (UnitIsPlayer'target' and unit or unit .. ':' .. UnitLevel'target' .. ':' .. UnitSex'target')
			if unit then
				player[unit] = UnitIsPlayer'target' and true or false
				if current and player[current] then
					addRecent(current)
				end
				current = unit
			end
		end
	end

	function UPDATE_BATTLEFIELD_SCORE()
		for i = 1, GetNumBattlefieldScores() do
			player[GetBattlefieldScore(i)] = true
		end
	end

	function IsShown(unit)
		return not player[unit]
				or UnitName'target' == unit
				or recent[unit] and GetTime() - recent[unit] <= 10
	end

	function IsPlayer(unit)
		return player[unit]
	end
end

CreateFrame'Frame':SetScript('OnUpdate', function()
	UpdateTimers()
	if not LOCKED then
		return
	end
	UpdateBars()
end)

do
	local defaultSettings = {
		invert = false,
		growth = 'up',
		scale = 1,
		alpha = .85,
		arcanist = false,
	}

	function ADDON_LOADED()
		if arg1 ~= 'aurae' then return end

		for k, v in defaultSettings do
			if aurae_settings[k] == nil then
				aurae_settings[k] = v
			end
		end
		
		local dummyTimer = {stopped=0}
		for i, etype in ipairs{'DEBUFF', 'CC', 'BUFF'} do
			local height = HEIGHT * MAXBARS + 4 * (MAXBARS - 1)
			local f = CreateFrame('Frame', 'aurae_' .. etype, UIParent)
			GROUPS[strupper(etype)] = f
			f:SetWidth(WIDTH + HEIGHT)
			f:SetHeight(height)
			f:SetMovable(true)
			f:SetUserPlaced(true)
			f:SetClampedToScreen(true)
			f:RegisterForDrag('LeftButton')
			f:SetScript('OnDragStart', function()
				this:StartMoving()
			end)
			f:SetScript('OnDragStop', function()
				this:StopMovingOrSizing()
			end)
			f:SetPoint('CENTER', -210 + (i - 1) * 210, 150)
			for i = 1, MAXBARS do
				local bar = CreateBar()
				bar:SetParent(f)
				bar:SetAlpha(aurae_settings.alpha)
				local offset = 20 * (i - 1)
				bar:SetPoint('BOTTOMLEFT', 0, offset)
				bar:SetPoint('BOTTOMRIGHT', 0, offset)
				bar.TIMER = dummyTimer
				tinsert(f, bar)
			end
		end

		for _, group in GROUPS do
			group:SetScale(aurae_settings.scale)
		end

		_G.SLASH_AURAE1 = '/aurae'
		SlashCmdList.AURAE = SlashCommandHandler

		LockBars()
	end

	Print('aurae loaded - /aurae')
end

do
	local function tokenize(str)
		local tokens = {}
		for token in string.gfind(str, '%S+') do tinsert(tokens, token) end
		return tokens
	end

	function SlashCommandHandler(msg)
		if msg then
			local args = tokenize(msg)
			local command = strlower(msg)
			if command == 'unlock' then
				UnlockBars()
				Print('Bars unlocked.')
			elseif command == 'lock' then
				LockBars()
				Print('Bars locked.')
			elseif command == 'invert' then
				aurae_settings.invert = not aurae_settings.invert
				if aurae_settings.invert then
					Print('Bar inversion on.')
				else
					Print('Bar inversion off.')
				end
			elseif args[1] == 'growth' and (args[2] == 'up' or args[2] == 'down') then
				aurae_settings.growth = args[2]
				Print('Growth: ' .. args[2])
				if not LOCKED then UnlockBars() end
			elseif strsub(command, 1, 5) == 'scale' then
				local scale = tonumber(strsub(command, 7))
				if scale then
					scale = max(.5, min(3, scale))
					aurae_settings.scale = scale
					for _, group in GROUPS do
						group:SetScale(scale)
					end
					Print('Scale: ' .. scale)
				else
					Usage()
				end
			elseif strsub(command, 1, 5) == 'alpha' then
				local alpha = tonumber(strsub(command, 7))
				if alpha then
					alpha = max(0, min(1, alpha))
					aurae_settings.alpha = alpha
					if not LOCKED then UnlockBars() end
					Print('Alpha: ' .. alpha)
				else
					Usage()
				end
			elseif command == 'clear' then
				aurae_settings = nil
				LoadVariables()
			elseif command == 'arcanist' then
				aurae_settings.arcanist = not aurae_settings.arcanist
				Print('Arcanist ' .. (aurae_settings.arcanist and 'on.' or 'off.'))
			else
				Usage()
			end
		end
	end
end

function Usage()
	Print("Usage:")
	Print("  lock | unlock")
	Print("  invert")
	Print("  growth (up | down)")
	Print("  scale [0.5,3]")
	Print("  alpha [0,1]")
	Print("  arcanist")
end

do
	local function rank(i, j)
		local _, _, _, _, rank = GetTalentInfo(i, j)
		return rank
	end

	local _, class = UnitClass'player'
	if class == 'ROGUE' then
		bonuses = {
			["Gouge"] = function()
				return rank(2, 1) * .5
			end,
			["Garrote"] = function()
				return rank(3, 8) * 3
			end,
		}
	elseif class == "WARLOCK" then
		bonuses = {
			["Shadow Word: Pain"] = function()
				return rank(2, 7) * 1.5
			end,
		}
	elseif class == 'HUNTER' then
		bonuses = {
			["Freezing Trap Effect"] = function(t)
				return t * rank(3, 7) * .15
			end,
		}
	elseif class == 'PRIEST' then
		bonuses = {
			["Shadow Word: Pain"] = function()
				return rank(3, 4) * 3
			end,
		}
	elseif class == 'MAGE' then
		bonuses = {
			["Cone of Cold"] = function()
				return min(1, rank(3, 2)) * .5 + rank(3, 2) * .5
			end,
			["Frostbolt"] = function()
				return min(1, rank(3, 2)) * .5 + rank(3, 2) * .5
			end,
			["Polymorph"] = function()
				if aurae_settings.arcanist then
					return 15
				end
			end,
		}
	elseif class == 'DRUID' then
		bonuses = {
			["Pounce"] = function()
				return rank(2, 4) * .5
			end,
			["Bash"] = function()
				return rank(2, 4) * .5
			end,
		}
	else
		bonuses = {}
	end
end


-- UnitFrames Timer Module by Renew: https://github.com/Voidmenull/ --
----------------------------------------------------------------------

-- AUF = Aurae Unit Frames
-- damn you Bit and your setfenv -_-

local AUF = CreateFrame("Frame")
AUF.Debuff = CreateFrame("Frame")
AUF.Buff = CreateFrame("Frame",nil,UIParent)
AUF.DR = CreateFrame("Frame",nil,UIParent)
AUF:RegisterEvent("PLAYER_TARGET_CHANGED")
AUF.UnitDebuff = UnitDebuff
AUF.UnitBuff = UnitBuff


AUF.DebuffAnchor = "TargetFrameDebuff"
AUF.BuffAnchor = "TargetFrameBuff"

-- get unitframes
if getglobal("LunaLUFUnittargetDebuffFrame1") then AUF.DebuffAnchor = "LunaLUFUnittargetDebuffFrame"; AUF.BuffAnchor = "LunaLUFUnittargetBuffFrame" -- luna x2.x
elseif getglobal("XPerl_Target_BuffFrame") then AUF.DebuffAnchor = "XPerl_Target_BuffFrame_DeBuff"; AUF.BuffAnchor = "XPerl_Target_BuffFrame_Buff" -- xperl
elseif getglobal("DUF_TargetFrame_Debuffs_1") then AUF.DebuffAnchor = "DUF_TargetFrame_Debuffs_"; AUF.BuffAnchor = "DUF_TargetFrame_Buffs_" -- DUF
elseif getglobal("pfUITargetDebuff1") then AUF.DebuffAnchor = "pfUITargetDebuff"; AUF.BuffAnchor = "pfUITargetBuff" -- pfUI
end

function AUF.Debuff:Build()
	for i=1,16 do
		AUF.Debuff[i] = CreateFrame("Model", "AUFDebuff"..i, nil, "CooldownFrameTemplate")
		AUF.Debuff[i].parent = CreateFrame("Frame", "AUFDebuff"..i.."Cooldown", getglobal(AUF.DebuffAnchor..i))
		AUF.Debuff[i].parent:SetPoint("CENTER",getglobal(AUF.DebuffAnchor..i),"CENTER", 0, 0)
		AUF.Debuff[i].parent:SetWidth(100)
		AUF.Debuff[i].parent:SetHeight(100)
		--AUF.Debuff[i].parent:SetFrameStrata("DIALOG")
		if getglobal(AUF.DebuffAnchor..i) then AUF.Debuff[i].parent:SetFrameLevel(getglobal(AUF.DebuffAnchor..i):GetFrameLevel() + 1) end
		AUF.Debuff[i]:SetParent(AUF.Debuff[i].parent)
		AUF.Debuff[i]:SetAllPoints(AUF.Debuff[i].parent)
		AUF.Debuff[i].parent:SetScript("OnUpdate",nil)
		
		AUF.Debuff[i].Font = AUF.Debuff[i]:CreateFontString(nil, "OVERLAY")
		AUF.Debuff[i].Font:SetPoint("CENTER", 0, 0)
		AUF.Debuff[i].Font:SetFont("Fonts\\ARIALN.TTF", 20, "OUTLINE")
		if getglobal("pfUITargetDebuff1") then AUF.Debuff[i].Font:SetFont("Interface\\AddOns\\pfUI\\fonts\\homespun.ttf", 20, "OUTLINE") end
		AUF.Debuff[i].Font:SetJustifyH("CENTER")
		AUF.Debuff[i].Font:SetTextColor(1,1,1)
		AUF.Debuff[i].Font:SetText("")
		
	end
end
AUF.Debuff:Build()

function AUF.Buff:Build()
	for i=1,16 do
		AUF.Buff[i] = CreateFrame("Model", "AUFBuff"..i, nil, "CooldownFrameTemplate")
		AUF.Buff[i].parent = CreateFrame("Frame", "AUFBuff"..i.."Cooldown", getglobal(AUF.BuffAnchor..i))
		AUF.Buff[i].parent:SetPoint("CENTER",getglobal(AUF.BuffAnchor..i),"CENTER", 0, 0)
		AUF.Buff[i].parent:SetWidth(100)
		AUF.Buff[i].parent:SetHeight(100)
		--AUF.Buff[i].parent:SetFrameStrata("DIALOG")
		if getglobal(AUF.BuffAnchor..i) then AUF.Buff[i].parent:SetFrameLevel(getglobal(AUF.BuffAnchor..i):GetFrameLevel() + 1) end
		AUF.Buff[i]:SetParent(AUF.Buff[i].parent)
		AUF.Buff[i]:SetAllPoints(AUF.Buff[i].parent)
		AUF.Buff[i].parent:SetScript("OnUpdate",nil)
		
		AUF.Buff[i].Font = AUF.Buff[i]:CreateFontString(nil, "OVERLAY")
		AUF.Buff[i].Font:SetPoint("CENTER", 0, 0)
		AUF.Buff[i].Font:SetFont("Fonts\\ARIALN.TTF", 20, "OUTLINE")
		if getglobal("pfUITargetBuff1") then AUF.Buff[i].Font:SetFont("Interface\\AddOns\\pfUI\\fonts\\homespun.ttf", 20, "OUTLINE") end
		AUF.Buff[i].Font:SetJustifyH("CENTER")
		AUF.Buff[i].Font:SetTextColor(1,1,1)
		AUF.Buff[i].Font:SetText("")
		
	end
end
AUF.Buff:Build()

function AUF:UpdateFont(button,start,duration,style)
	if style == "Debuff" then
		AUF.Debuff[button].Duation = duration
		AUF.Debuff[button].parent:SetScript("OnUpdate",function()
			AUF.Debuff[button].Duation = AUF.Debuff[button].Duation - arg1
			
			if AUF.Debuff[button].Duation > 0 then
				AUF.Debuff[button].Font:SetText(floor(AUF.Debuff[button].Duation+0.5))
				if AUF.Debuff[button].Duation > 3 then
					AUF.Debuff[button].Font:SetTextColor(1,1,1)
				else AUF.Debuff[button].Font:SetTextColor(1,0.4,0.4) end
					
			else
				AUF.Debuff[button].parent:SetScript("OnUpdate",nil)
			end

		end)
	elseif style == "Buff" then
		AUF.Buff[button].Duation = duration
		AUF.Buff[button].parent:SetScript("OnUpdate",function()
			AUF.Buff[button].Duation = AUF.Buff[button].Duation - arg1
			
			if AUF.Buff[button].Duation > 0 then
				AUF.Buff[button].Font:SetText(floor(AUF.Buff[button].Duation+0.5))
				if AUF.Buff[button].Duation > 3 then
					AUF.Buff[button].Font:SetTextColor(1,1,1)
				else AUF.Buff[button].Font:SetTextColor(1,0.4,0.4) end
					
			else
				AUF.Buff[button].parent:SetScript("OnUpdate",nil)
			end

		end)
	end
end

function AUF:OnEvent()
	if event == "PLAYER_TARGET_CHANGED" then
		AUF:OnTarget()
	elseif event == "UNIT_AURA" and arg1 == "target" then
		AUF:UpdateDebuffs()
	end
end
AUF:SetScript("OnEvent", AUF.OnEvent)

function AUF:OnTarget()
	if UnitExists("target") then
		AUF:RegisterEvent("UNIT_AURA")
		AUF:UpdateDebuffs()
	else
		AUF:UnregisterEvent("UNIT_AURA")
		for i=1,16 do -- xperl problem
			AUF.Debuff[i].parent:Hide()
			AUF.Buff[i].parent:Hide()
		end
	end
end

function AUF:UpdateDebuffs()
	-- close old animations
	for i=1,16 do
		CooldownFrame_SetTimer(AUF.Debuff[i],0,0,0)
		CooldownFrame_SetTimer(AUF.Buff[i],0,0,0)
	end
	
	if UnitExists("target") then
		for _, timer in timers do
			if not timer.DR and TARGET_ID == timer.UNIT then
				for i=1,16 do
					if AUF.UnitDebuff("target",i) == "Interface\\Icons\\"..aurae.EFFECTS[timer.EFFECT].ICON and getglobal(AUF.DebuffAnchor..i) then
						
						-- xper exception
						if  getglobal("XPerl_Target_BuffFrame") then
							AUF.Debuff[i].parent:SetWidth(getglobal(AUF.DebuffAnchor..i):GetWidth()*0.7)
							AUF.Debuff[i].parent:SetHeight(getglobal(AUF.DebuffAnchor..i):GetHeight()*0.7)
							AUF.Debuff[i]:SetScale(getglobal(AUF.DebuffAnchor..i):GetHeight()/36*0.7)
						else
							AUF.Debuff[i].parent:SetWidth(getglobal(AUF.DebuffAnchor..i):GetWidth())
							AUF.Debuff[i].parent:SetHeight(getglobal(AUF.DebuffAnchor..i):GetHeight())
							AUF.Debuff[i]:SetScale(getglobal(AUF.DebuffAnchor..i):GetHeight()/36)
						end
						
						AUF.Debuff[i].parent:SetPoint("CENTER",getglobal(AUF.DebuffAnchor..i),"CENTER",0,0)
						AUF.Debuff[i].parent:Show()
						
						if pfCooldownFrame_SetTimer then pfCooldownFrame_SetTimer(AUF.Debuff[i],timer.START, timer.END-timer.START,1)
						else CooldownFrame_SetTimer(AUF.Debuff[i],timer.START, timer.END-timer.START,1) end
						AUF:UpdateFont(i,timer.START,timer.END-GetTime(),"Debuff")
					end
					
					if AUF.UnitBuff("target",i) == "Interface\\Icons\\"..aurae.EFFECTS[timer.EFFECT].ICON and getglobal(AUF.BuffAnchor..i) then
						
						if  getglobal("XPerl_Target_BuffFrame") then
							AUF.Buff[i].parent:SetWidth(getglobal(AUF.BuffAnchor..i):GetWidth()*0.7)
							AUF.Buff[i].parent:SetHeight(getglobal(AUF.BuffAnchor..i):GetHeight()*0.7)
							AUF.Buff[i]:SetScale(getglobal(AUF.BuffAnchor..i):GetHeight()/36*0.7)
						else
							AUF.Buff[i].parent:SetWidth(getglobal(AUF.BuffAnchor..i):GetWidth())
							AUF.Buff[i].parent:SetHeight(getglobal(AUF.BuffAnchor..i):GetHeight())
							AUF.Buff[i]:SetScale(getglobal(AUF.BuffAnchor..i):GetHeight()/36)
						end
						AUF.Buff[i].parent:SetPoint("CENTER",getglobal(AUF.BuffAnchor..i),"CENTER",0,0)
						AUF.Buff[i].parent:Show()
						
						if pfCooldownFrame_SetTimer then pfCooldownFrame_SetTimer(AUF.Buff[i],timer.START, timer.END-timer.START,1)
						else CooldownFrame_SetTimer(AUF.Buff[i],timer.START, timer.END-timer.START,1) end
						AUF:UpdateFont(i,timer.START,timer.END-GetTime(),"Buff")
					end
				end
			end
		end
	end
end

StartTimer_old = StartTimer
function StartTimer(effect, unit, start)
	StartTimer_old(effect, unit, start)
	AUF:UpdateDebuffs()
end