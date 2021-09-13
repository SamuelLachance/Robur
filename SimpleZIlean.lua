if Player.CharName ~= "Zilean" then return end

module("Simple Zilean", package.seeall, log.setup)
clean.module("Simple Zilean", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleZilean", "1.0.0"
--CoreEx.AutoUpdate("https://github.com/SamuelLachance/Robur/" .. ScriptName ..".lua", Version)
local Menu = Libs.NewMenu
local Prediction = Libs.Prediction
local Orbwalker = Libs.Orbwalker
local CollisionLib = Libs.CollisionLib
local DamageLib = Libs.DamageLib
local ImmobileLib = Libs.ImmobileLib
local SpellLib = Libs.Spell
local TargetSelector = Libs.TargetSelector
local TS = Libs.TargetSelector()
local HPred = Libs.HealthPred
local DashLib = Libs.DashLib
local os_clock = _G.os.clock
local math_abs = _G.math.abs
local math_huge = _G.math.huge
local math_min = _G.math.min
local math_deg = _G.math.deg
local math_sin = _G.math.sin
local math_cos = _G.math.cos
local math_acos = _G.math.acos
local math_pi = _G.math.pi
local math_pi2 = 0.01745329251
local ObjectManager = CoreEx.ObjectManager
local EventManager = CoreEx.EventManager
local Input = CoreEx.Input
local Enums = CoreEx.Enums
local Game = CoreEx.Game
local Geometry = CoreEx.Geometry
local Renderer = CoreEx.Renderer
local Vector = CoreEx.Geometry.Vector
local SpellSlots = Enums.SpellSlots
local SpellStates = Enums.SpellStates
local BuffTypes = Enums.BuffTypes
local Events = Enums.Events
local HitChanceEnum = Enums.HitChance
local Nav = CoreEx.Nav

local willGetHit = false
local next = next
local Zilean = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Waveclear = false,false,false
local incomingDamage = {}
local Qobj = {}
Zilean.Q = SpellLib.Skillshot({
  Slot = Enums.SpellSlots.Q,
  Range = 900,
  Speed = 2000,
  Radius = 140,
  Type = "Circular",
  Collisions = {WindWall = true},
  Delay = 0.25,
  UseHitbox = true,
  Key = "Q"
})

Zilean.W = SpellLib.Active({
  Slot = Enums.SpellSlots.W,
  Key = "W"
})

Zilean.E = SpellLib.Targeted({
  Slot = Enums.SpellSlots.E,
  Range = 550,
  Key = "E",
})

Zilean.R = SpellLib.Targeted({
  Slot = Enums.SpellSlots.R,
  Range = 900,
  Key = "R"
})

Zilean.TargetSelector = nil
Zilean.Logic = {}

local Utils = {}
local IsInTurret = false

function Utils.IsGameAvailable()
  return not (
  Game.IsChatOpen()  or
  Game.IsMinimized() or
  Player.IsDead
  )
end

function Utils.SetMana()
  if Zilean.Q:IsReady() then
    qMana = Zilean.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if Zilean.W:IsReady() then
    wMana = Zilean.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if Zilean.E:IsReady() then
    eMana = Zilean.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if Zilean.R:IsReady() then
    rMana = Zilean.R:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    rMana = 0
  else
    rMana = 0
  end
  return false
end

function Utils.GetTargets(Spell)
  return {TS:GetTarget(Spell.Range,true)}
end

function Utils.GetTargetsRange(Range)
  return TS:GetTargets(Range,false)
end

function Utils.ValidUlt(target)
  local TargetAi = target.AsAI
  if TargetAi and TargetAi.IsValid then
    local KindredUlt = TargetAi:GetBuff("kindredrnodeathbuff")
    local TryndUlt = TargetAi:GetBuff("undyingrage") --idk if  HasUndyingBuff() do the same thing
    local KayleUlt = TargetAi:GetBuff("judicatorintervention") -- still this name ?
    local ZileanUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or ZileanUlt  or TargetAi.IsZombie or TargetAi.IsDead then
      return false
    end
  end
  return true
end

function Utils.HasBuffType(unit,buffType)
  local ai = unit.AsAI
  if ai.IsValid then
    for i = 0, ai.BuffCount do
      local buff = ai:GetBuff(i)
      if buff and buff.IsValid and buff.BuffType == buffType then
        return true
      end
    end
  end
  return false
end

function Utils.Count(spell)
  local num = 0
  for k, v in ipairs(ObjectManager.GetNearby("enemy", "heroes")) do
    local hero = v.AsHero
    if hero and hero.IsTargetable and hero:Distance(Player.Position) < spell.Range then
      num = num + 1
    end
  end
  return num
end

function Utils.hasValue(tab,val)
  for index, value in ipairs(tab) do
    if value == val then
      return true
    end
  end
  return false
end

function Utils.tablefind(tab,el)
  for index, value in pairs(tab) do
    if value == el then
      return index
    end
  end
end

function Utils.CountMinionsInRange(range, type)
  local amount = 0
  for k, v in ipairs(ObjectManager.GetNearby(type, "minions")) do
    local minion = v.AsMinion
    if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and
    Player:Distance(minion) < range then
      amount = amount + 1
    end
  end
  return amount
end

function Utils.CountEnemiesInRange(pos, range, t)
  local res = 0
  for k, v in ipairs(t or ObjectManager.Get("enemy", "heroes")) do
    local hero = v.AsHero
    if hero and hero.IsTargetable and hero:Distance(pos) < range then
      res = res + 1
    end
  end
  return res
end

function Utils.CountHeroes(pos,range,team)
  local num = 0
  for k, v in pairs(ObjectManager.Get(team, "heroes")) do
    local hero = v.AsHero
    if hero.IsValid and not hero.IsDead and hero.IsTargetable and hero:Distance(pos) < range then
      num = num + 1
    end
  end
  return num
end
function Utils.IsValidTarget(Target)
  return Target and Target.IsTargetable and Target.IsAlive
end

function Utils.GetAngle(v1, v2)
  return math_deg(math_acos(v1 * v2 / (v1:Len() * v2:Len())))
end

function Utils.IsFacing(p1,p2)
  local v = p1.Position - p2.Position
  local dir = p1.AsAI.Direction
  local angle = 180 - Utils.GetAngle(v, dir)
  if math_abs(angle) < 80 then
    return true
  end
  return false
end

function Utils.HasQZileanBuff(target)
  local TargetAi = target.AsAI
  if TargetAi and TargetAi.IsValid then
    local ZileanBomb = TargetAi:GetBuff("zileanqenemybomb")
    local ZileanBombAlly = TargetAi:GetBuff("zileanqallybomb")
    if ZileanBomb or ZileanBombAlly then
      return true
    end
  end
  return false
end

function Utils.HasBuff(target,buffname)
  local TargetAi = target.AsAI
  if TargetAi and TargetAi.IsValid then
    local hBuff= TargetAi:GetBuff(buffname)
    if hBuff then
      return true
    end
  end
  return false
end

function Utils.CanHit(target,spell)
  if Utils.IsValidTarget(target) then
    local pred = target:FastPrediction(spell.CastDelay)
    if pred == nil then return false end
    if spell.LineWidth > 0 then
      local powCalc = (spell.LineWidth + target.BoundingRadius)^2
      if (pred:LineDistance(spell.StartPos,spell.EndPos,true) <= powCalc) or (target.Position:LineDistance(spell.StartPos,spell.EndPos,true) <= powCalc) then
        return true
      end
    elseif target:Distance(spell.EndPos) < 50 + target.BoundingRadius or pred:Distance(spell.EndPos) < 50 + target.BoundingRadius then
      return true
    end
  end
  return false
end

function Utils.NoLag(tick)
  if (iTick == tick) then
    return true
  else
    return false
  end
end

function Zilean.OnGapclose(source,dash)
  if source.IsEnemy and source.IsHero  and not dash.IsBlink then
    local paths = dash:GetPaths()
    local endPos = paths[#paths].EndPos
    if Player:Distance(endPos) <= 600 and Menu.Get("Misc.GapcloseE") and Zilean.E:IsReady()  then
      if Zilean.E:Cast(source) then return true end
    end
  end
  return false
end

function Zilean.LogicQ()
  if (Combo and Menu.Get("Combo.Q") and Player.Mana > qMana) or (Harass and Menu.Get("Harass.Q") and Player.Mana > (eMana + qMana + wMana+rMana)*2) then
    local target = TS:GetTarget(Zilean.Q.Range,false)
    if Utils.IsValidTarget(target) then
      local qPred = Zilean.Q:GetPrediction(target)
      if qPred and qPred.HitChanceEnum >= HitChanceEnum.High then
        if Zilean.Q:Cast(qPred.CastPosition) then return true end
      end
    end
  end
  if Waveclear and Menu.Get("WaveClear.Q") and Player.Mana > (eMana + qMana + wMana)*3 then
    local minionsQ = {}
    local monstersQ = {}
    for k, v in pairs(ObjectManager.GetNearby("enemy", "minions")) do
      local minion = v.AsAI
      local minionInRange = minion and minion.MaxHealth > 6 and Zilean.Q:IsInRange(minion)
      local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
      if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
        table.insert(minionsQ, minion)
        table.sort(minionsQ, function(a, b) return a.MaxHealth < b.MaxHealth end)
      end
    end
    for k, v in pairs(ObjectManager.GetNearby("neutral", "minions")) do
      local minion = v.AsAI
      local minionInRange = minion and minion.MaxHealth > 6 and Zilean.Q:IsInRange(minion)
      local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
      if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
        table.insert(monstersQ, minion)
        table.sort(monstersQ, function(a, b) return a.MaxHealth < b.MaxHealth end)
      end
    end
    local qPos1, hitCount1 = Zilean.Q:GetBestCircularCastPos(minionsQ, 300)
    local qPos2, hitCount2 = Zilean.Q:GetBestCircularCastPos(monstersQ, 300)
    if qPos1 ~= nil and hitCount1 >= 3 then
      if Zilean.Q:Cast(qPos1) then return true end
    end
    if qPos2 ~= nil and hitCount2 >= 1 then
      if Zilean.Q:Cast(qPos2) then return true end
    end
  end
  return false
end

function Zilean.LogicW()
  if not Zilean.Q:IsReady() and (Combo and Menu.Get("Combo.W") and Player.Mana > qMana) or (Harass and Menu.Get("Harass.W") and Player.Mana > (eMana + qMana + wMana + rMana)*2) then
    for k, hero in ipairs(ObjectManager.GetNearby("all", "heroes")) do
      if Utils.HasQZileanBuff(hero) then
        if Zilean.W:Cast() then return true end
      end
    end
    for k,v in ipairs(ObjectManager.GetNearby("all", "minions")) do
      if Utils.HasQZileanBuff(v) then
        if Zilean.W:Cast() then return true end
      end
    end
  end
  if not Zilean.Q:IsReady() and Waveclear and Menu.Get("WaveClear.W") and Player.Mana > (eMana + qMana + wMana+rMana)*3 then
    for k, enemy in ipairs(ObjectManager.GetNearby("enemy", "minions")) do
      if Utils.HasQZileanBuff(enemy) then
        if Zilean.W:Cast() then return true end
      end
    end
    for k, enemy in ipairs(ObjectManager.GetNearby("neutral", "minions")) do
      if Utils.HasQZileanBuff(enemy) then
        if Zilean.W:Cast() then return true end
      end
    end
  end
  return false
end

function Zilean.LogicE()
  if (Combo and Menu.Get("Combo.E") and Player.Mana > qMana+eMana+wMana+rMana) or (Harass and Menu.Get("Harass.E") and Player.Mana > (eMana + qMana + wMana+rMana)*2) then
    for k, enemy in ipairs(Utils.GetTargets(Zilean.E)) do
      if Utils.HasQZileanBuff(enemy) or Zilean.Q:IsReady() then
        if Zilean.E:Cast(enemy) then return true end
      end
    end
  end
  if Menu.Get("Misc.AutoE") and Player.Mana > eMana then
    for _, v in ipairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      local incomingDamage = HPred.GetDamagePrediction(ally,0.5,false)
      if Zilean.E:IsInRange(ally) and Menu.Get("1" .. ally.CharName) and incomingDamage >= ally.Health * 0.15 then
        if Zilean.E:Cast(ally) then return true end
      end
      for k, enemy in ipairs(ObjectManager.GetNearby("enemy", "heroes")) do
        if Zilean.E:IsInRange(ally) and Menu.Get("1" .. ally.CharName) and ally:Distance(enemy.AsHero.Position) < 400 and enemy.IsVisible then
          if Zilean.E:Cast(ally) then return true end
        end
      end
    end
  end
  return false
end

function Zilean.LogicR()
  if Menu.Get("Misc.AutoR") and Player.Mana > rMana then
    for k, v in pairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      local incomingDamage = HPred.GetDamagePrediction(ally,1,false)
      local enemies = Utils.CountHeroes(ally.Position,700,"enemy")
      if Zilean.R:IsInRange(ally) and Menu.Get("1" .. ally.CharName) and ally.Health - incomingDamage < enemies * ally.Level * 25 and Utils.ValidUlt(ally) then
        if Zilean.R:Cast(ally) then return true end
      end
    end
  end
  return false
end

function Zilean.OnProcessSpell(sender,spell)
  if sender.IsHero and sender.IsEnemy and Menu.Get("Misc.AutoE") and not spell.IsBasicAttack then
    for _, v in pairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      if Zilean.E:IsInRange(ally) and Player:Distance(spell.EndPos) <= Zilean.E.Range  then
        if Utils.CanHit(Player,spell) then
          willGetHit = true
          if willGetHit then return true end
        end
        if  Utils.CanHit(ally,spell) and Player.Mana > eMana+qMana+rMana+wMana and Zilean.E:IsReady() then
          if Zilean.E:Cast(ally) then return true end
        end
      end
    end
  end
  willGetHit = false
  return false
end

function Zilean.OnPreAttack(args)
  if Player.Mana > qMana and Zilean.Q:IsReady() and args.Target.IsHero then
    args.Process = false
    if args.Process == false then return true end
  end
  return false
end

function Zilean.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Zilean.Q,Zilean.W,Zilean.E,Zilean.R}
    for k, v in ipairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  return false
end
function Zilean.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  if Utils.NoLag(0) then
    if Utils.SetMana() then return true end
  end
  if Utils.NoLag(1) and Zilean.R:IsReady() then
    if Zilean.LogicR() then return true end
  end
  if Utils.NoLag(2) and Zilean.Q:IsReady() and not Orbwalker.IsWindingUp() and not willGetHit then
    if Zilean.LogicQ() then return true end
  end
  if Utils.NoLag(3) and Zilean.W:IsReady() then
    if Zilean.LogicW() then return true end
  end
  if Utils.NoLag(4) and Zilean.E:IsReady() then
    if Zilean.LogicE() then return true end
  end
  local OrbwalkerMode = Orbwalker.GetMode()
  if OrbwalkerMode == "Combo" then
    Combo = true
  else
    Combo = false
  end
  if OrbwalkerMode == "Harass" then
    Harass = true
  else
    Harass = false
  end
  if OrbwalkerMode == "Waveclear" then
    Waveclear = true
  else
    Waveclear = false
  end
  iTick = iTick + 1
  if iTick > 4 then
    iTick = 0
  end
  return false
end

function Zilean.LoadMenu()
  local function ZileanMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("Combo", 0xB65A94FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Combo.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Combo.W", "Reset Bomb with W", true)
    Menu.ColoredText("> E", 0x0066CCFF, false)
    Menu.Checkbox("Combo.E", "Use E", true)
    Menu.ColoredText("Harass", 0x118AB2FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Harass.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Harass.W", "Reset Bomb with W", true)
    Menu.ColoredText("> E", 0x0066CCFF, false)
    Menu.Checkbox("Harass.E", "Use E", true)
    Menu.ColoredText("WaveClear/JungleClear", 0xEF476FFF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("WaveClear.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("WaveClear.W", "Reset Bomb with W", true)
    Menu.NextColumn()
    Menu.ColoredText("Misc", 0xB65A94FF, true)
    Menu.Checkbox("Misc.AutoR", "Auto R", true)
    Menu.NewTree("Rlist","R Whitelist", function()
    Menu.ColoredText("R Whitelist", 0x06D6A0FF, true)
    for _, Object in pairs(ObjectManager.Get("ally", "heroes")) do
      local Name = Object.AsHero.CharName
      Menu.Checkbox("1" .. Name, "Use on " .. Name, true)
    end
    end)
    Menu.Checkbox("Misc.GapcloseE",   "Use [E] on gapclose", true)
    Menu.Checkbox("Misc.AutoE",   "Auto E", true)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("Drawing.Q.Enabled",   "Draw [Q] Range",true)
    Menu.ColorPicker("Drawing.Q.Color", "Draw [Q] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.E.Enabled",   "Draw [E] Range",false)
    Menu.ColorPicker("Drawing.E.Color", "Draw [E] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.R.Enabled",   "Draw [R] Range",false)
    Menu.ColorPicker("Drawing.R.Color", "Draw [R] Color", 0x118AB2FF)
    end)
  end
  if Menu.RegisterMenu("Simple Zilean", "Simple Zilean", ZileanMenu) then return true end
  return false
end

function OnLoad()
  Zilean.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Zilean[EventName] then
      EventManager.RegisterCallback(EventId, Zilean[EventName])
    end
  end
  return true
end
