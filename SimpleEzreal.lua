if Player.CharName ~= "Ezreal" then return end

module("Simple Ezreal", package.seeall, log.setup)
clean.module("Simple Ezreal", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleEzreal", "1.0.0"
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
local Ezreal = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Waveclear,Lasthit = false,false,false,false
local overkill = 0

Ezreal.Q = SpellLib.Skillshot({
  Slot = SpellSlots.Q,
  Range = 1200,
  Delay = 0.25,
  Speed = 2000,
  Radius = 120,
  Collisions = {Minions = true, WindWall = true },
  UseHitbox = true,
  Type = "Linear",
  Key = "Q"
})

Ezreal.W = SpellLib.Skillshot({
  Slot = SpellSlots.W,
  Range = 1200,
  Delay = 0.25,
  Speed = 1700,
  Radius = 160,
  Collisions = {Heroes = true, WindWall = true },
  Type = "Linear",
  UseHitbox = true,
  Key = "W"
})

Ezreal.E = SpellLib.Skillshot({
  Slot = SpellSlots.E,
  Range = 475,
  Delay = 0.25,
  Key = "E"
})

Ezreal.R = SpellLib.Skillshot({
  Slot = SpellSlots.R,
  Range = 3000,
  Delay = 1.1,
  Radius = 160,
  Speed = 2000,
  Type = "Linear",
  Collisions = {WindWall = true },
  UseHitbox = true,
  Key = "R"
})

Ezreal.TargetSelector = nil
Ezreal.Logic = {}

local Utils = {}

function Utils.IsGameAvailable()
  return not (
  Game.IsChatOpen()  or
  Game.IsMinimized() or
  Player.IsDead
  )
end

function Utils.SetMana()
  if Ezreal.Q:IsReady() then
    qMana = Ezreal.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if Ezreal.W:IsReady() then
    wMana = Ezreal.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if Ezreal.E:IsReady() then
    eMana = Ezreal.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if Ezreal.R:IsReady() then
    rMana = Ezreal.R:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    rMana = 0
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
    local EzrealUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or EzrealUlt  or TargetAi.IsZombie or TargetAi.IsDead then
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

function Utils.CountHeroes(pos,Range,type)
  local num = 0
  for k, v in ipairs(ObjectManager.Get(type, "heroes")) do
    local hero = v.AsHero
    if hero and hero.IsTargetable and hero:Distance(pos.Position) < Range then
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
      local powCalc = (spell.LineWidth + hero.BoundingRadius)^2
      if (pred:LineDistance(spell.StartPos,spell.EndPos,true) <= powCalc) or (target.Position:LineDistance(spell.StartPos,spell.EndPos,true) <= powCalc) then
        return true
      end
    elseif target:Distance(spell.EndPos) < 50 + target.BoundingRadius or pred:Distance(spell.EndPos) < 50 + target.BoundingRadius then
      return true
    end
  end
  return false
end

function Utils.Sqrd(num)
  return num*num
end

function Utils.IsUnderTurret(target)
  local TurretRange = 562500
  local turrets = ObjectManager.GetNearby("enemy", "turrets")
  for _, turret in ipairs(turrets) do
    if turret.IsDead then return false end
    if target.Position:DistanceSqr(turret) < TurretRange + Utils.Sqrd(target.BoundingRadius) / 2 then
      return true
    end
  end
  return false
end
function Utils.CanMove(target)
  if Utils.HasBuffType(target,BuffTypes.Charm) or Utils.HasBuffType(target,BuffTypes.Snare) or Utils.HasBuffType(target,BuffTypes.Stun) or Utils.HasBuffType(target,BuffTypes.Suppression) or Utils.HasBuffType(target,BuffTypes.Taunt) or Utils.HasBuffType(target,BuffTypes.Fear) or Utils.HasBuffType(target,BuffTypes.Knockup) or Utils.HasBuffType(target,BuffTypes.Knockback) then
    return false
  else
    return true
  end
end
function Utils.NoLag(tick)
  if (iTick == tick) then
    return true
  else
    return false
  end
end

function Ezreal.CanCastW(target)
  if Ezreal.W:IsReady() then
    local wPred = Ezreal.W:GetPrediction(target)
    if wPred and wPred.HitChanceEnum >= HitChanceEnum.VeryHigh and Player:Distance(target.Position)	<= 1100 then
      return true
    end
  end
  return false
end

function Ezreal.LogicQ()
  local target = TS:GetTarget(Ezreal.Q.Range,false)
  if Utils.IsValidTarget(target) then
    if (Combo and Menu.Get("Combo.Q") and Player.Mana > qMana + rMana and (not Ezreal.CanCastW(target) or Menu.Get("Combo.W"))) or (Harass or Waveclear and Menu.Get("Harass.Q") and Player.Mana > eMana + qMana + wMana+rMana or (Menu.Get("HarassOn") and Menu.Get("Harass.Q")) and (not Ezreal.CanCastW(target) or Menu.Get("Harass.W"))) then
      if not Ezreal.CanCastW(target) or target.Health < Ezreal.Q:GetDamage(target) then
        local qPred = Ezreal.Q:GetPrediction(target)
        if qPred and qPred.HitChanceEnum >= HitChanceEnum.High then
          if Ezreal.Q:Cast(qPred.CastPosition) then return true end
        end
      end
    end
  end
  local minionsQ = {}
  local monstersQ = {}
  for k, v in pairs(ObjectManager.GetNearby("enemy", "minions")) do
    local minion = v.AsAI
    local minionInRange = minion and minion.MaxHealth > 6 and Ezreal.Q:IsInRange(minion)
    local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
    if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
      table.insert(minionsQ, minion)
      table.sort(minionsQ, function(a, b) return a.MaxHealth > b.MaxHealth end)
    end
  end
  for k, v in pairs(ObjectManager.GetNearby("neutral", "minions")) do
    local minion = v.AsAI
    local minionInRange = minion and minion.MaxHealth > 6 and Ezreal.Q:IsInRange(minion)
    local shouldIgnoreMinion = minion and (Orbwalker.IsLasthitMinion(minion) or Orbwalker.IsIgnoringMinion(minion))
    if minionInRange and not shouldIgnoreMinion and minion.IsTargetable  and Utils.IsValidTarget(minion) then
      table.insert(monstersQ, minion)
      table.sort(monstersQ, function(a, b) return a.MaxHealth < b.MaxHealth end)
    end
  end
  if Waveclear and Player.Mana > eMana + qMana + wMana+rMana and Menu.Get("WaveClear.Q") then
    for k, minion in pairs(monstersQ) do
      if not minion.IsAI then return false end
      local qPred = Prediction.GetPredictedPosition(minion, Ezreal.Q, Player.Position)
      if qPred ~= nil then
        if Ezreal.Q:Cast(minion.Position) then return true end
      end
    end
    for k, minion in pairs(minionsQ) do
      local qPred = Prediction.GetPredictedPosition(minion, Ezreal.Q, Player.Position)
      if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.High then
        local delay = (Player:Distance(minion.Position)/ Ezreal.Q.Speed + Ezreal.Q.Delay)
        local hpPred = HPred.GetHealthPrediction(minion,delay,false)
        if hpPred > 20 then
          if hpPred < Ezreal.Q:GetDamage(minion) and Player:Distance(minion.Position) <= Orbwalker.GetTrueAutoAttackRange() and not Player.IsWindingUp then
            if Ezreal.Q:Cast(qPred.CastPosition) then return true end
          elseif (minion.Health/minion.MaxHealth)*100 > 80 and Menu.Get("WaveClear.Qpush") and not Player.IsWindingUp then
            if Ezreal.Q:Cast(qPred.CastPosition) then return true end
          end
        end
      end
    end
  end
  if Player.Mana > eMana + qMana + wMana+rMana and Menu.Get("WaveClear.Q") and Menu.Get("WaveClear.Ql") and (Waveclear or Lasthit or Harass) then
    for k, minion in pairs(minionsQ) do
      local qPred = Prediction.GetPredictedPosition(minion, Ezreal.Q, Player.Position)
      if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.High and Player:Distance(minion.Position) > Orbwalker.GetTrueAutoAttackRange() then
        local delay = (Player:Distance(minion.Position)/ Ezreal.Q.Speed + Ezreal.Q.Delay)
        local hpPred = HPred.GetHealthPrediction(minion,delay,false)
        if hpPred > 0 and minion.Health < Ezreal.Q:GetDamage(minion) then
          if Ezreal.Q:Cast(qPred.CastPosition) then return true end
        end
      end
    end
  end
  return false
end

function Ezreal.LogicW()
  if (Combo and Menu.Get("Combo.W") and Player.Mana > eMana+wMana+rMana) or (Harass and Menu.Get("Harass.W") and Player.Mana > eMana + rMana + wMana+qMana or (Menu.Get("HarassOn") and Menu.Get("Harass.W"))) then
    local target = TS:GetTarget(Ezreal.W.Range,false)
    if Utils.IsValidTarget(target) then
      local wPred = Ezreal.W:GetPrediction(target)
      local qPred = Ezreal.Q:GetPrediction(target)
      if wPred ~= nil and not Utils.CanMove(target) then
        if Ezreal.W:Cast(target.Position) then return true end
      elseif wPred ~= nil and wPred.HitChanceEnum >= HitChanceEnum.High then
        if Harass or (Menu.Get("HarassOn") and Menu.Get("Harass.W")) and qPred and CollisionLib.SearchMinions(Player.Position,qPred.CastPosition,60,1600,0.25,1,"enemy").Result then return false end
        if Ezreal.W:Cast(wPred.CastPosition) then return true end
      end
    end
  end
  return false
end

function Ezreal.LogicE()
  if Combo and Menu.Get("Combo.E") and Ezreal.E:IsReady() and not Utils.IsUnderTurret(Player) and Game.GetTime() - overkill > 0.3 then
    for k, enemy in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
      if Utils.IsValidTarget(enemy) and enemy:Distance(Renderer.GetMousePos()) + 300 < Player:Distance(enemy.Position) and Player:Distance(enemy.Position) > Orbwalker.GetTrueAutoAttackRange() and Player:Distance(enemy.Position) <= 1300 then
        local dashPos = Player.Position:Extended(Renderer.GetMousePos(),Ezreal.E.Range)
        if Utils.CountEnemiesInRange(dashPos, 900) < 3 then
          local dmg = 0
          if Player:Distance(enemy.Position) <= 950 then
            dmg = DamageLib.GetAutoAttackDamage(enemy) + Ezreal.E:GetDamage(enemy)
          end
          if Ezreal.Q:IsReady() and Player.Mana > qMana + eMana then
            local qPred = Ezreal.Q:GetPrediction(enemy)
            if qPred ~= nil and qPred.HitChanceEnum >= HitChanceEnum.High then
              dmg = Ezreal.Q:GetDamage(enemy)
            end
          end
          if Ezreal.W:IsReady() and Player.Mana > qMana + eMana + wMana then
            dmg = dmg + Ezreal.W:GetDamage(enemy)
          end
          if dmg > enemy.Health and Utils.ValidUlt(enemy) then
            overkill = Game.GetTime()
            if Ezreal.E:Cast(dashPos) then return true end
          end
        end
      end
    end
  end
  return false
end

function Ezreal.LogicR()
  for k, enemy in pairs(Utils.GetTargetsRange(4000)) do
    local target = enemy.AsAI
    if Menu.Get("CastR") and Ezreal.R:IsReady() and Player.Mana > rMana then
      local rPred = Ezreal.R:GetPrediction(target)
      if rPred ~= nil and Utils.IsValidTarget(target) then
        if Ezreal.R:Cast(rPred.CastPosition) then return true end
      end
    end
    if Menu.Get("AutoR") and Ezreal.R:IsReady() and Player.Mana > rMana and Utils.CountHeroes(Player,800,"enemy") == 0  and Game.GetTime() - overkill > 0.3  and not Utils.IsUnderTurret(Player) then
      local delay = (Player:Distance(target.Position)/ Ezreal.R.Speed + Ezreal.R.Delay)*1000
      local hpPred = HPred.GetHealthPrediction(target,delay,false)
      local rPred = Ezreal.R:GetPrediction(target)
      if rPred ~= nil and rPred.HitChanceEnum >= HitChanceEnum.Medium and hpPred < Ezreal.R:GetDamage(target) and Utils.CountHeroes(target,500,"ally") == 0 and Utils.IsValidTarget(target) and Utils.ValidUlt(target) then
        if Ezreal.R:Cast(rPred.CastPosition) then return true end
      end
    end
    if Menu.Get("AutoRcc") and Ezreal.R:IsReady() and Player.Mana > rMana and not Utils.IsUnderTurret(Player) then
      if not Utils.CanMove(target) and Player:Distance(target.Position) <= 2000 and Utils.IsValidTarget(target) and Utils.CountHeroes(Player,800,"enemy") == 0 then
        if Ezreal.R:Cast(target.Position) then return true end
      end
    end
  end
  if Menu.Get("AutoRhit") and Ezreal.R:IsReady() and Player.Mana > rMana and not Utils.IsUnderTurret(Player) then
    local enemies = {}
    for k, enemy in pairs(ObjectManager.Get("enemy", "heroes")) do
      local target = enemy.AsHero
      local pos = target:FastPrediction(Game.GetLatency() + Ezreal.R.Delay)
      if Utils.IsValidTarget(target) and Player:Distance(target.Position) <= 3000 then
        table.insert(enemies, target.Position)
      end
    end
    local rCastPos, hitCount = Ezreal.R:GetBestLinearCastPos(enemies,Ezreal.R.Radius)
    if rCastPos ~= nil and hitCount >= Menu.Get("HitcountR") and Utils.CountHeroes(Player,1200,"enemy") == 0 then
      if Ezreal.R:Cast(rCastPos) then return true end
    end
  end
  return false
end
function Ezreal.Logic.Auto()
  for k, hero in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
    local enemy = hero.AsAI
    if Player.Mana > qMana and Ezreal.Q:IsInRange(enemy) then
      local delay = (Player:Distance(enemy.Position)/ Ezreal.Q.Speed + Ezreal.Q.Delay)*1000
      local hpPred = HPred.GetHealthPrediction(enemy,delay,false)
      if hpPred < Ezreal.Q:GetDamage(enemy) + Ezreal.W:GetDamage(enemy) and Utils.IsValidTarget(enemy) then
        overkill = Game.GetTime()
      end
    end
  end
  for k, enemy in ipairs(Utils.GetTargets(Ezreal.W)) do
    if Player.Mana > wMana and Ezreal.W:IsInRange(enemy) then
      local delay = (Player:Distance(enemy.Position)/ Ezreal.W.Speed + Ezreal.W.Delay)*1000
      local hpPred = HPred.GetHealthPrediction(enemy,delay,false)
      if hpPred < Ezreal.W:GetDamage(enemy) and Utils.IsValidTarget(enemy) then
        overkill = Game.GetTime()
      end
    end
  end
end

function Ezreal.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Ezreal.Q,Ezreal.W,Ezreal.E,Ezreal.R}
    for k, v in ipairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
    if Menu.Get("Drawing.Status") then
      local status, color
      local p = Player.Position:ToScreen()
      if Menu.Get("HarassOn") then
        status, color = "Harass: Enabled", 0x00FF00FF
        p.x = p.x - 63
        p.y = p.y + 33
      else
        status, color = "Harass: Disabled", 0xFF0000FF
        p.x = p.x - 66
        p.y = p.y + 33
      end
      Renderer.DrawText(p, {x=500,y=500}, status, color)
    end
  end
  return false
end
function Ezreal.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  if Utils.NoLag(0) then
    Ezreal.Logic.Auto()
    if Utils.SetMana() then return true end
  end
  if Utils.NoLag(1) and Ezreal.E:IsReady() then
    if Ezreal.LogicE() then return true end
  end
  if Utils.NoLag(2) and Ezreal.W:IsReady() then
    if Ezreal.LogicW() then return true end
  end
  if Utils.NoLag(3) and Ezreal.Q:IsReady() then
    if Ezreal.LogicQ() then return true end
  end
  if Utils.NoLag(4) and Ezreal.R:IsReady() then
    if Ezreal.LogicR() then return true end
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
  if OrbwalkerMode == "Lasthit" then
    Lasthit = true
  else
    Lasthit = false
  end
  iTick = iTick + 1
  if iTick > 4 then
    iTick = 0
  end
  return false
end

function Ezreal.LoadMenu()
  local function EzrealMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("Combo", 0xB65A94FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Combo.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Combo.W", "Use W", true)
    Menu.ColoredText("> E", 0x0066CCFF, false)
    Menu.Checkbox("Combo.E", "Use E KS", true)
    Menu.Keybind("CastR", "Semi [R] Cast", string.byte('T'))
    Menu.ColoredText("Harass", 0x118AB2FF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("Harass.Q", "Use Q", true)
    Menu.ColoredText("> W", 0x0066CCFF, false)
    Menu.Checkbox("Harass.W", "Use W", true)
    Menu.Keybind("HarassOn", "Toggle Auto Harass", string.byte('L'), true,true)
    Menu.ColoredText("WaveClear/JungleClear", 0xEF476FFF, true)
    Menu.ColoredText("> Q", 0x0066CCFF, false)
    Menu.Checkbox("WaveClear.Q", "Use Q", true)
    Menu.Checkbox("WaveClear.Qpush", "Use Q to push", false)
    Menu.Checkbox("WaveClear.Ql", "Use Q lasthit", true)
    Menu.ColoredText("Misc", 0xB65A94FF, true)
    Menu.ColoredText("> R", 0x0066CCFF, false)
    Menu.Checkbox("AutoR", "Auto R KS", true)
    Menu.Checkbox("AutoRcc", "Auto R cc", true)
    Menu.Checkbox("AutoRhit", "Auto R HitCount", true)
    Menu.Slider("HitcountR", "HitCount", 4, 1, 5)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("Drawing.Status",   "Draw Harass Status",true)
    Menu.Checkbox("Drawing.Q.Enabled",   "Draw [Q] Range",true)
    Menu.ColorPicker("Drawing.Q.Color", "Draw [Q] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.E.Enabled",   "Draw [E] Range",false)
    Menu.ColorPicker("Drawing.E.Color", "Draw [E] Color", 0x118AB2FF)
    Menu.Checkbox("Drawing.R.Enabled",   "Draw [R] Range",false)
    Menu.ColorPicker("Drawing.R.Color", "Draw [R] Color", 0x118AB2FF)
    end)
  end
  if Menu.RegisterMenu("Simple Ezreal", "Simple Ezreal", EzrealMenu) then return true end
  return false
end

function OnLoad()
  Ezreal.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Ezreal[EventName] then
      EventManager.RegisterCallback(EventId, Ezreal[EventName])
    end
  end
  return true
end
