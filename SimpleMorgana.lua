if Player.CharName ~= "Morgana" then return end

module("Simple Morgana", package.seeall, log.setup)
clean.module("Simple Morgana", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleMorgana", "1.0.0"
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
local Morgana = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Laneclear,None = false,false,false, false
local spellslist = {}

Morgana.Q = SpellLib.Skillshot({
  Slot = SpellSlots.Q,
  Range = 1300,
  Delay = 0.250,
  Speed = 1200,
  Radius = 140,
  Collisions = { Minions = true, WindWall = true },
  Type = "Linear",
  UseHitbox = true,
  Key = "Q"
})

Morgana.W = SpellLib.Skillshot({
  Slot = SpellSlots.W,
  Range = 1000,
  Delay = 0.500,
  Radius = 275,
  Type = "Circular",
  Key = "W"
})

Morgana.E = SpellLib.Targeted({
  Slot = SpellSlots.E,
  Range = 800,
  Key = "E"
})

Morgana.R = SpellLib.Active({
  Slot = SpellSlots.R,
  Range = 600,
  Delay = 0.350,
  Key = "R"
})

local Utils = {}
function Utils.IsGameAvailable()
  return not (
  Game.IsChatOpen()  or
  Game.IsMinimized() or
  Player.IsDead
  )
end

function Utils.SetMana()
  if Morgana.Q:IsReady() then
    qMana = Morgana.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if Morgana.W:IsReady() then
    wMana = Morgana.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if Morgana.E:IsReady() then
    eMana = Morgana.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if Morgana.R:IsReady() then
    rMana = Morgana.R:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    rMana = 0
  else
    rMana = 0
  end
  return false
end

function Utils.GetTargets(Spell)
  return TS:GetTargets(Spell.Range,true)
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
    local MorganaUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or MorganaUlt  or TargetAi.IsZombie or TargetAi.IsDead then
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

function Morgana.LogicQ()
  local target = TS:GetTarget(Morgana.Q.Range,false)
  if (Combo or Harass) and Utils.IsValidTarget(target) then
    local qPred = Morgana.Q:GetPrediction(target)
    if qPred and qPred.HitChanceEnum >= HitChanceEnum.VeryHigh then
      if Morgana.Q:Cast(qPred.CastPosition) then return true end
    end
  end
  for _, v in pairs(ObjectManager.GetNearby("enemy","heroes")) do
    local enemy = v.AsHero
    if Utils.IsValidTarget(enemy) and not Utils.CanMove(enemy) and Player:Distance(enemy.Position) < Morgana.Q.Range then
      local qPred = Morgana.Q:GetPrediction(enemy)
      if qPred and qPred.HitChanceEnum >= HitChanceEnum.VeryHigh then
        if Morgana.Q:Cast(enemy.Position) then return true end
      end
    end
  end
  return false
end

function Morgana.LogicW()
  local target = TS:GetTarget(Morgana.W.Range)
  if Utils.IsValidTarget(target) then
    local predW = Morgana.W:GetPrediction(target)
    if (Combo or Harass) and predW and Player.Mana > qMana + wMana + eMana + rMana and predW.HitChanceEnum >= HitChanceEnum.VeryHigh and not target.IsZombie then
      if Morgana.W:Cast(predW.CastPosition) then return true end
    end
  end
  for _, v in pairs(ObjectManager.GetNearby("enemy","heroes")) do
    local enemy = v.AsHero
    if Utils.IsValidTarget(enemy) and not Utils.CanMove(enemy) and Player:Distance(enemy.Position) < Morgana.W.Range then
      local wPred = Morgana.W:GetPrediction(enemy)
      if wPred and wPred.HitChanceEnum >= HitChanceEnum.VeryHigh then
        if Morgana.W:Cast(enemy.Position) then return true end
      end
    end
  end
  return false
end

function Morgana.LogicE()
  for _, v in pairs(ObjectManager.GetNearby("ally","heroes")) do
    local ally = v.AsHero
    if Menu.Get("1" .. ally.CharName) and Player:Distance(ally.Position) < Morgana.E.Range and Utils.HasBuffType(ally,24) then
      if Morgana.E:Cast(ally) then return true end
    end
  end
  return false
end

function Morgana.LogicR()
  for _, v in pairs(ObjectManager.GetNearby("enemy","heroes")) do
    local enemy = v.AsHero
    if Player:Distance(enemy.Position) < Morgana.R.Range and not enemy.IsZombie then
      local predH = HPred.GetHealthPrediction(enemy,1,true)
      if Morgana.R:GetDamage(enemy)*3 >= predH and enemy.Health > enemy.Level * 15 and Menu.Get("AutoRks") then
        if Morgana.R:Cast() then return true end
      end
      if Utils.Count(Morgana.R) >= Menu.Get("autoR.hitCount") and Combo then
        if Morgana.R:Cast() then return true end
      end
    end
  end
  return false
end

function Morgana.OnProcessSpell(sender,spell)
  if sender.IsHero and sender.IsEnemy and Menu.Get("autoE") and Player.Mana > eMana and Morgana.E:IsReady() and (not spell.IsBasicAttack or spell.IsSpecialAttack)  then
    for _, v in pairs(ObjectManager.GetNearby("ally","heroes")) do
      local ally = v.AsHero
      if Menu.Get("1" .. ally.CharName) and Morgana.E:IsInRange(ally) and Player:Distance(spell.EndPos) <= Morgana.E.Range and Utils.hasValue(spellslist,spell.Name) then
        if Utils.CanHit(ally,spell) then
          if Morgana.E:Cast(ally) then return true end
        end
      end
      if spell.Target and spell.Target.IsHero and spell.Target.IsAlly and Morgana.E:IsInRange(spell.Target.AsHero) and Menu.Get("1" .. spell.Target.AsHero.CharName) and Utils.hasValue(spellslist,spell.Name) then
        if Morgana.E:Cast(spell.Target.AsHero) then return true end
      end
    end
  end
  return false
end

function Morgana.OnGapclose(source,dash)
  if source.IsEnemy and source.IsHero  and not dash.IsBlink then
    local paths = dash:GetPaths()
    local endPos = paths[#paths].EndPos
    local qPred = Morgana.Q:GetPrediction(source)
    if Player:Distance(endPos) <= 400 and Menu.Get("AutoQG") and Morgana.Q:IsReady() and qPred.HitChanceEnum == HitChanceEnum.Dashing then
      for _, v in pairs(ObjectManager.GetNearby("enemy","heroes")) do
        local enemy = v.AsHero
        if enemy.CharName == source.AsHero.CharName then
          local qPred2 = Morgana.Q:GetPrediction(enemy)
          if qPred2 and qPred.HitChanceEnum == HitChanceEnum.Dashing then
            if Morgana.Q:Cast(enemy.Position) then return true end
          end
        end
      end
    end
    if Player:Distance(source.Position) < Morgana.R.Range and Menu.Get("AutoRg") and Morgana.R:IsReady() then
      if Morgana.R:Cast() then return true end
    end
  end
  return false
end

function Morgana.OnBuffGain(obj,buffInst)
  if not obj.IsHero or not obj.IsAlly then return false end
  if (Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Stun) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Snare) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Knockup) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Charm) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Fear) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Knockback) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Taunt) or Utils.HasBuffType(obj.AsHero,Enums.BuffTypes.Suppression)) and Menu.Get("1" .. obj.AsHero.CharName) and Morgana.E:IsReady() and Morgana.E:IsInRange(obj.AsHero) then
    if Morgana.E:Cast(obj.AsHero)  then return true end
  end
  return false
end

function Morgana.OnInterruptibleSpell(source, spell, danger, endT, canMove)
  if source.IsEnemy and Menu.Get("AutoRI") and Morgana.R:IsReady() and danger > 2 and Player:Distance(source.Position) <= Morgana.R.Range then
    if Morgana.R:Cast() then return true end
  end
  return false
end

function Morgana.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Morgana.Q}
    for k, v in ipairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  return false
end

function Morgana.OnDrawDamage(target, dmgList)
  if Menu.Get("DrawDmg") then
    table.insert(dmgList, Morgana.Q:GetDamage(target))
    table.insert(dmgList, Morgana.W:GetDamage(target)*3)
    if Morgana.R:IsReady() then
      table.insert(dmgList, Morgana.R:GetDamage(target))
    end
  end
end

function Morgana.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  if Utils.NoLag(0) then
    if Utils.SetMana() then return true end
  end
  if Utils.NoLag(1) and Morgana.R:IsReady() and Menu.Get("autoR") then
    if Morgana.LogicR() then return true end
  end
  if Utils.NoLag(2) and Morgana.Q:IsReady() and Menu.Get("autoQ") and not Orbwalker.IsWindingUp() then
    if Morgana.LogicQ() then return true end
  end
  if Utils.NoLag(3) and Morgana.W:IsReady() and Menu.Get("autoW") and not Orbwalker.IsWindingUp() then
    if Morgana.LogicW() then return true end
  end
  if Utils.NoLag(4) and Morgana.E:IsReady() and Menu.Get("autoE") and Player.Mana > eMana then
    if Morgana.LogicE() then return true end
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
  if OrbwalkerMode == "Waveclear" or OrbwalkerMode == "Lasthit" or OrbwalkerMode == "Harass" then
    Laneclear = true
  else
    Laneclear = false
  end
  if OrbwalkerMode == "nil" then
    None = true
  else
    None = false
  end
  iTick = iTick + 1
  if iTick > 4 then
    iTick = 0
  end
  return false
end

function Morgana.LoadMenu()
  local function MorganaMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("> Q", 0xB65A94FF, true)
    Menu.Checkbox("autoQ", "Auto Q", true)
    Menu.Checkbox("AutoQG", "Auto Q Gapclose", true)
    Menu.ColoredText("> W", 0x118AB2FF, true)
    Menu.Checkbox("autoW", "Auto W", true)
    Menu.ColoredText("> E", 0x0066CCFF, true)
    Menu.Checkbox("autoE", "Auto E", true)
    Menu.NewTree("EList","E ally whitelist", function()
    Menu.ColoredText("E Whitelist", 0x06D6A0FF, true)
    for _, Object in pairs(ObjectManager.Get("ally", "heroes")) do
      local Name = Object.AsHero.CharName
      Menu.Checkbox("1" .. Name, "Use on " .. Name, true)
    end
    end)
    Menu.NewTree("EListSpells","E spells whitelist", function()
    Menu.ColoredText("E SpellsWhitelist", 0x06D6A0FF, true)
    for _, Object in pairs(ObjectManager.Get("enemy", "heroes")) do
      local hero = Object.AsHero
      local Name = Object.AsHero.CharName
      Menu.NewTree(Name,Name, function()
      Menu.Checkbox("Q" .. Name, "Use for " .. Name .. "Q", true)
      Menu.Checkbox("W" .. Name, "Use for " .. Name .. "W", true)
      Menu.Checkbox("E" .. Name, "Use for " .. Name .. "E", true)
      Menu.Checkbox("R" .. Name, "Use for " .. Name .. "R", true)
      end)
      local spellQName = hero:GetSpell(SpellSlots.Q).Name
      local spellWName = hero:GetSpell(SpellSlots.W).Name
      local spellEName = hero:GetSpell(SpellSlots.E).Name
      local spellRName = hero:GetSpell(SpellSlots.R).Name
      if Menu.Get("Q"..Name) then
        table.insert(spellslist,spellQName)
      elseif not Menu.Get("Q"..Name) and Utils.hasValue(spellslist,spellQName) then
        table.remove(spellslist,Utils.tablefind(spellslist,spellQName))
      end
      if Menu.Get("W"..Name) then
        table.insert(spellslist,spellWName)
      elseif not Menu.Get("W"..Name) and Utils.hasValue(spellslist,spellWName) then
        table.remove(spellslist,Utils.tablefind(spellslist,spellWName))
      end
      if Menu.Get("E"..Name) then
        table.insert(spellslist,spellEName)
      elseif not Menu.Get("E"..Name) and Utils.hasValue(spellslist,spellEName) then
        table.remove(spellslist,Utils.tablefind(spellslist,spellEName))
      end
      if Menu.Get("R"..Name) then
        table.insert(spellslist,spellRName)
      elseif not Menu.Get("R"..Name) and Utils.hasValue(spellslist,spellRName) then
        table.remove(spellslist,Utils.tablefind(spellslist,spellRName))
      end
    end
    end)
    Menu.ColoredText("> R", 0xB65A94FF, true)
    Menu.Checkbox("autoR", "Auto R Combo", true)
    Menu.Slider("autoR.hitCount", "[R] HitCount", 2, 1, 5)
    Menu.Checkbox("AutoRg", "Auto R Gapclose", true)
    Menu.Checkbox("AutoRI", "Auto R Interupt", true)
    Menu.Checkbox("AutoRks", "Auto R KS", true)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("Drawing.Q.Enabled","Draw [Q] Range",true)
    Menu.ColorPicker("Drawing.Q.Color", "Draw [Q] Color", 0x118AB2FF)
    Menu.Checkbox("DrawDmg", "Draw Damage", true)
    end)
  end
  if Menu.RegisterMenu("Simple Morgana", "Simple Morgana", MorganaMenu) then return true end
  return false
end

function OnLoad()
  Morgana.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Morgana[EventName] then
      EventManager.RegisterCallback(EventId, Morgana[EventName])
    end
  end
  return true
end
