if Player.CharName ~= "Karma" then return end

module("Simple Karma", package.seeall, log.setup)
clean.module("Simple Karma", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleKarma", "1.0.0"
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

local next = next
local Karma = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Waveclear = false,false,false
Karma.Q = SpellLib.Skillshot({
  Slot = SpellSlots.Q,
  Range = 950,
  Delay = 0.25,
  Speed = 1700,
  Radius = 60,
  Collisions = {Minions = true, WindWall = true },
  UseHitbox = true ,
  Type = "Linear",
  Key = "Q"
})
Karma.Q2 = SpellLib.Skillshot({
  Slot = SpellSlots.Q,
  Range = 1150,
  Delay = 0.25,
  Speed = 1700,
  Radius = 80,
  EffectRadius = 280,
  Collisions = {Minions = true, WindWall = true },
  UseHitbox = true ,
  Type = "Linear",
  Key = "Q"
})
Karma.W = SpellLib.Targeted({
  Slot = SpellSlots.W,
  Range = 675,
  Key = "W"
})

Karma.E = SpellLib.Targeted({
  Slot = SpellSlots.E,
  Range = 800,
  Key = "E"
})

Karma.R = SpellLib.Active({
  Slot = SpellSlots.R,
  Range = 0,
  Key = "R"
})

Karma.TargetSelector = nil
Karma.Logic = {}

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
  if Karma.Q:IsReady() then
    qMana = Karma.Q:GetManaCost()
  else
    qMana = 0
  end
  if Karma.W:IsReady() then
    wMana = Karma.W:GetManaCost()
  else
    wMana = 0
  end
  if Karma.E:IsReady() then
    eMana = Karma.E:GetManaCost()
  else
    eMana = 0
  end
  if Karma.R:IsReady() then
    rMana = Karma.R:GetManaCost()
  else
    rMana = 0
  end
  return false
end

function Utils.GetTargets(Spell)
  return {TS:GetTarget(Spell.Range,false)}
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

function Utils.NoLag(tick)
  if (iTick == tick) then
    return true
  else
    return false
  end
end

function Karma.OnGapclose(source,dash)
  if source.IsEnemy and source.IsHero  and not dash.IsBlink then
    local paths = dash:GetPaths()
    local endPos = paths[#paths].EndPos
    if Player:Distance(endPos) <= 600 and Menu.Get("Misc.GapcloseW") and Karma.W:IsReady()  then
      if Karma.W:Cast(source) then return true end
    end
  end
  return false
end

function Karma.OnProcessSpell(sender,spell)
  if sender.IsHero and sender.IsEnemy and Menu.Get("autoE") and Player.Mana > eMana and Karma.E:IsReady() then
    for _, v in pairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      if Menu.Get("1" .. ally.CharName) and Karma.E:IsInRange(ally) and Player:Distance(spell.EndPos) <= Karma.E.Range then
        if  Utils.CanHit(ally,spell) then
          if Karma.E:Cast(ally) then return true end
        end
      end
      if spell.Target and spell.Target.IsHero and spell.Target.IsAlly and Karma.E:IsInRange(spell.Target.AsHero) and Menu.Get("1" .. spell.Target.AsHero.CharName) then
        if Karma.E:Cast(spell.Target.AsHero) then return true end
      end
    end
  end
  return false
end

function Karma.LogicQ()
  if (Combo and Menu.Get("Combo.Q") and Player.Mana > qMana) or (Harass and Menu.Get("Harass.Q") and Player.Mana > (eMana + qMana + wMana+rMana)) then
    local target = TS:GetTarget(Karma.Q.Range)
    local target2 = TS:GetTarget(Karma.Q2.Range)
    if Utils.IsValidTarget(target) and not Utils.HasBuff(Player,"KarmaMantra") and (not Karma.R:IsReady() or not Menu.Get("Combo.R")) then
      local qPred = Karma.Q:GetPrediction(target)
      if qPred then
        if qPred.HitChanceEnum >= HitChanceEnum.VeryHigh then
          if Karma.Q:Cast(qPred.CastPosition) then return true end
        else
          local fc = Karma.Q:GetFirstCollision(Player.Position,qPred.CastPosition,"enemy").Positions
          for _, v in pairs(fc) do
            if v:Distance(target.Position) < 280 then
              if Karma.Q:Cast(qPred.CastPosition) then return true end
            end
          end
        end
      end
    elseif Utils.IsValidTarget(target2) and Utils.HasBuff(Player,"KarmaMantra") and Utils.CountHeroes(Player.Position,800, "Enemy") < 4 then
      local qPred2 = Karma.Q2:GetPrediction(target2)
      if qPred2 then
        if qPred2.HitChanceEnum >= HitChanceEnum.High then
          if Karma.Q2:Cast(qPred2.CastPosition) then return true end
        else
          local fc = Karma.Q2:GetFirstCollision(Player.Position,qPred2.CastPosition,"enemy").Positions
          for _, v in pairs(fc) do
            if v:Distance(target2.Position) <= 280 then
              if Karma.Q2:Cast(qPred2.CastPosition) then return true end
            end
          end
        end
      end
    end
  end
  if Waveclear and Menu.Get("WaveClear.Q") and Player.Mana > (eMana + qMana + wMana)*3 then
    local minionsQ = {}
    for k, v in pairs(ObjectManager.GetNearby("enemy", "minions")) do
      local minion = v.AsAI
      local minionInRange = minion and minion.MaxHealth > 6 and Karma.Q:IsInRange(minion)
      local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
      if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
        table.insert(minionsQ, minion)
        table.sort(minionsQ, function(a, b) return a.MaxHealth > b.MaxHealth end)
      end
    end
    for k, minion in pairs(minionsQ) do
      local qPred = Prediction.GetPredictedPosition(minion, Karma.Q, Player.Position)
      if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.Low and Player:Distance(minion.Position) >= Orbwalker.GetTrueAutoAttackRange() then
        local delay = (Player:Distance(minion.Position)/ Karma.Q.Speed + Karma.Q.Delay)*1000
        local hpPred = HPred.GetHealthPrediction(minion,delay,false)
        if hpPred > 0 and minion.Health < Karma.Q:GetDamage(minion) then
          if Karma.Q:Cast(qPred.CastPosition) then return true end
        end
      end
      if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.Low and not Orbwalker.CanAttack() then
        local delay = (Player:Distance(minion.Position)/ Karma.Q.Speed + Karma.Q.Delay)*1000
        local hpPred = HPred.GetHealthPrediction(minion,delay,false)
        local qPredPos , qHitCount = Karma.Q2:GetBestLinearCastPos(minionsQ,120)
        if hpPred > 20 then
          if minion.Health < Karma.Q:GetDamage(minion) then
            if Karma.Q:Cast(qPred.CastPosition) then return true end
          elseif (minion.Health/minion.MaxHealth)*100 > 80 and hpPred > Karma.Q:GetDamage(minion) then
            if Menu.Get("WaveClear.R") and Player.Mana > qMana and qHitCount >= 2 and Karma.R:IsReady() then
              if Karma.R:Cast() then return true end
            end
            if Utils.HasBuff(Player,"KarmaMantra") then
              if Karma.Q2:Cast(qPredPos) then return true end
            else
              if Karma.Q:Cast(qPred.CastPosition) then return true end
            end
          end
        end
      end
    end
    if Waveclear and Menu.Get("JungleClear.Q") and Player.Mana > qMana then
      local monstersQ = {}
      for k, v in pairs(ObjectManager.GetNearby("neutral", "minions")) do
        local minion = v.AsAI
        local minionInRange = minion and minion.MaxHealth > 6 and Karma.Q:IsInRange(minion)
        local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
        if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
          table.insert(monstersQ, minion)
          table.sort(monstersQ, function(a, b) return a.MaxHealth < b.MaxHealth end)
        end
      end
      for k, minion in pairs(monstersQ) do
        local qPred = Prediction.GetPredictedPosition(minion, Karma.Q, Player.Position)
        if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.Low then
          if Menu.Get("JungleClear.R") and Player.Mana > qMana  then
            if Karma.R:Cast() then return true end
          end
          if Karma.Q:Cast(qPred.CastPosition) then return true end
        end
      end
    end
  end
  return false
end

function Karma.LogicW()
  if (Combo and Menu.Get("Combo.W") and Player.Mana > qMana+wMana) or (Harass and Menu.Get("Harass.W") and Player.Mana > (eMana + qMana + wMana)*4) then
    for k, enemy in ipairs(Utils.GetTargets(Karma.W)) do
      if not Utils.HasBuff(Player,"KarmaMantra") or ((Player.Health/Player.MaxHealth) * 100 < 20 and  Utils.CountHeroes(Player.Position,800, "Ally") < 2) and Player:Distance(enemy) < 600 then
        if Karma.W:Cast(enemy) then return true end
      end
    end
  end
  return false
end

function Karma.LogicE()
  if (Combo and Menu.Get("Combo.E") and Player.Mana > eMana+qMana) or (Harass and Menu.Get("Harass.E") and Player.Mana > (eMana + qMana + wMana)*4) then
    for k, enemy in ipairs(Utils.GetTargets(Karma.Q)) do
      if Menu.Get("1" .. Player.CharName) and (Utils.HasBuff(enemy,"KarmaSpiritBind") and not Utils.HasBuff(Player,"KarmaMantra")) or (Utils.HasBuff(Player,"KarmaMantra") and (Utils.CountHeroes(Player.Position,800, "Enemy") >= 3 or Utils.CountHeroes(Player,700,"ally") >= 3)) then
        if Karma.E:Cast(Player) then return true end
      end
    end
  end
  if Menu.Get("autoE") and Karma.E:IsReady() and Player.Mana > eMana then
    for _, v in ipairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      local incomingDamage = HPred.GetDamagePrediction(ally,0.5,false)
      if Karma.E:IsInRange(ally) and Menu.Get("1" .. ally.CharName) and incomingDamage >= ally.Health * 0.15 then
        if Karma.E:Cast(ally) then return true end
      end
      for k, enemy in ipairs(ObjectManager.GetNearby("enemy", "heroes")) do
        if Utils.IsValidTarget(enemy) and Karma.E:IsInRange(ally) and Menu.Get("1" .. ally.CharName) and ally:Distance(enemy.AsHero.Position) < 100 and enemy.IsVisible then
          if Karma.E:Cast(ally) then return true end
        end
      end
    end
  end
  return false
end

function Karma.LogicR()
  if (Combo and Menu.Get("Combo.R") and Player.Mana > qMana) or (Harass and Menu.Get("Harass.R") and Player.Mana > (eMana + qMana + wMana)*4) or (Waveclear and Menu.Get("WaveClear.R") and Player.Mana > (eMana + qMana + wMana)*3) then
    for k, enemy in ipairs(Utils.GetTargets(Karma.Q)) do
      local qPred = Karma.Q2:GetPrediction(enemy)
      if Utils.HasBuff(enemy,"KarmaSpiritBind") or (Karma.Q:IsReady() and qPred and qPred.HitChanceEnum >= HitChanceEnum.Low) then
        if Karma.R:Cast() then return true end
      end
    end
  end
  return false
end

function Karma.OnPreAttack(args)
  if Utils.HasBuff(args.Target,"KarmaSpiritBind") then
    args.Process = false
    if args.Process == false then return true end
  end
  return false
end

function Karma.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Karma.Q,Karma.W,Karma.E,Karma.R}
    for k, v in ipairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  return false
end

function Karma.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  if Utils.NoLag(0) then
    if Utils.SetMana() then return true end
  end
  if Utils.NoLag(1) and Karma.R:IsReady() then
    if Karma.LogicR() then return true end
  end
  if Utils.NoLag(2) and Karma.E:IsReady() then
    if Karma.LogicE() then return true end
  end
  if Utils.NoLag(3) and Karma.Q:IsReady() then
    if Karma.LogicQ() then return true end
  end
  if Utils.NoLag(4) and Karma.W:IsReady() then
    if Karma.LogicW() then return true end
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

function Karma.LoadMenu()
  local function KarmaMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("Combo", 0xB65A94FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Combo.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Combo.W", "Use W", true)
    Menu.ColoredText("> E", 0x0066CCFF, false)
    Menu.Checkbox("Combo.E", "Use E", true)
    Menu.ColoredText("> R", 0x0066CCFF, false)
    Menu.Checkbox("Combo.R", "Use R", true)
    Menu.ColoredText("Harass", 0x118AB2FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Harass.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Harass.W", "Use W", true)
    Menu.ColoredText("> E", 0x0066CCFF, false)
    Menu.Checkbox("Harass.E", "Use E", true)
    Menu.ColoredText("> R", 0x0066CCFF, false)
    Menu.Checkbox("Harass.R", "Use R", true)
    Menu.ColoredText("WaveClear", 0xEF476FFF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("WaveClear.Q", "Use Q", true)
    Menu.ColoredText("> R", 0x0066CCFF, false)
    Menu.Checkbox("WaveClear.R", "Use R", true)
    Menu.ColoredText("JungleClear", 0xEF472FEF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("JungleClear.Q", "Use Q", true)
    Menu.ColoredText("> R", 0x0066CCFF, false)
    Menu.Checkbox("JungleClear.R", "Use R", true)
    Menu.ColoredText("Misc", 0xB65A94FF, true)
    Menu.Checkbox("autoE", "Auto E Shield", true)
    Menu.NewTree("EList","E ally whitelist", function()
    Menu.ColoredText("E Whitelist", 0x06D6A0FF, true)
    for _, Object in pairs(ObjectManager.Get("ally", "heroes")) do
      local Name = Object.AsHero.CharName
      Menu.Checkbox("1" .. Name, "Use on " .. Name, true)
    end
    end)
    Menu.Checkbox("Misc.GapcloseW", "Auto W Gapclose", true)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("Drawing.Status",   "Draw Harass Status",true)
    Menu.Checkbox("Drawing.Q.Enabled",   "Draw [Q] Range",true)
    Menu.ColorPicker("Drawing.Q.Color", "Draw [Q] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.E.Enabled",   "Draw [E] Range",false)
    Menu.ColorPicker("Drawing.E.Color", "Draw [E] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.W.Enabled",   "Draw [W] Range",false)
    Menu.ColorPicker("Drawing.W.Color", "Draw [W] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.R.Enabled",   "Draw [R] Range",false)
    Menu.ColorPicker("Drawing.R.Color", "Draw [R] Color", 0x118AB2FF)
    end)
  end
  if Menu.RegisterMenu("Simple Karma", "Simple Karma", KarmaMenu) then return true end
  return false
end

function OnLoad()
  Karma.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Karma[EventName] then
      EventManager.RegisterCallback(EventId, Karma[EventName])
    end
  end
  return true
end
