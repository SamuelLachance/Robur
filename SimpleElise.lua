if Player.CharName ~= "Elise" then return end

module("Simple Elise", package.seeall, log.setup)
clean.module("Simple Elise", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleElise", "1.0.0"
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
local BestCoveringRectangle = Geometry.BestCoveringRectangle
local next = next
local Elise = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Laneclear,None = false,false,false, false
local spiderGirl = false
local humanGirl = false
local humQcd ,humWcd , humEcd = 0,0,0
local spidQcd, spidWcd ,spidEcd = 0,0,0
local humQready , humWready , humEready = false,false,false
local spidQready , spidWready , spidEready = false,false,false

Elise.Q = SpellLib.Targeted({
  Slot = SpellSlots.Q,
  Range = 625,
  Key = "Q"
})

Elise.W = SpellLib.Skillshot({
  Slot = SpellSlots.W,
  Range = 950,
  Delay = 0.25,
  Radius = 100,
  Speed = 1000,
  Collisions = {Minions = true},
  Type = "Linear",
  Key = "W"
})

Elise.E = SpellLib.Skillshot({
  Slot = SpellSlots.E,
  Range = 1100,
  Delay = 0.25,
  Radius = 55,
  Speed = 1300,
  Collisions = {Minions = true, WindWall = true},
  Type = "Linear",
  Key = "E"
})

Elise.Q2 = SpellLib.Targeted({
  Slot = SpellSlots.Q,
  Range = 475,
  Key = "Q"
})

Elise.W2 = SpellLib.Active({
  Slot = SpellSlots.W,
  Key = "W"
})

Elise.E2 = SpellLib.Targeted({
  Slot = SpellSlots.E,
  Range = 750,
  Key = "E"
})

Elise.R = SpellLib.Active({
  Slot = SpellSlots.R,
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
  if Elise.Q:IsReady() then
    qMana = Elise.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if Elise.W:IsReady() then
    wMana = Elise.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if Elise.E:IsReady() then
    eMana = Elise.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if Elise.R:IsReady() then
    rMana = Elise.R:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    rMana = 0
  else
    rMana = 0
  end
  return false
end

function Utils.ValidUlt(target)
  local TargetAi = target.AsAI
  if TargetAi and TargetAi.IsValid then
    local KindredUlt = TargetAi:GetBuff("kindredrnodeathbuff")
    local TryndUlt = TargetAi:GetBuff("undyingrage") --idk if  HasUndyingBuff() do the same thing
    local KayleUlt = TargetAi:GetBuff("judicatorintervention") -- still this name ?
    local EliseUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or EliseUlt  or TargetAi.IsZombie or TargetAi.IsDead then
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

function Utils.GetPriorityMinion(pos, type, maxRange)
  local minionFocus = nil
  for k, v in pairs(ObjectManager.GetNearby(type, "minions")) do
    local minion = v.AsMinion
    if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and minion:Distance(pos) < maxRange then
      if minionFocus == nil then
        minionFocus = minion
      elseif minionFocus.IsEpicMinion then
        minionFocus = minion
      elseif not minionFocus.IsEpicMinion and minionFocus.IsEliteMinion then
        minionFocus = minion
      elseif not minionFocus.IsEpicMinion and not minionFocus.IsEliteMinion then
        if minion.Health > minionFocus.Health or minionFocus:Distance(pos) > minion:Distance(pos) then
          minionFocus = minion
        end
      end
    end
  end
  return minionFocus
end

function Utils.LinearCastMinionPos(pos, type, maxRange,spell,width)
  local minions = {}
  local res = {hitCount = 0, spellPos = Vector(0,0,0) }
  for k, v in pairs(ObjectManager.GetNearby(type, "minions")) do
    local minion = v.AsMinion
    if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and minion:Distance(pos) < maxRange then
      table.insert(minions, minion.Position)
    end
  end
  res.spellPos, res.hitCount = spell:GetBestLinearCastPos(minions,width)
  return res
end

function Utils.CircularCastMinionPos(pos, type, maxRange,spell,width)
  local minions = {}
  local res = {hitCount = 0, spellPos = Vector(0,0,0)}
  for k, v in pairs(ObjectManager.GetNearby(type, "minions")) do
    local minion = v.AsMinion
    if not minion.IsJunglePlant and minion.IsValid and not minion.IsDead and minion.IsTargetable and minion:Distance(pos) < maxRange then
      table.insert(minions, minion.Position)
    end
  end
  res.spellPos, res.hitCount = spell:GetBestCircularCastPos(minions,width)
  return res
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
  return Target and Target.IsAlive
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

function Utils.SearchHeroes(startPos, endPos, width, speed, delay, minResults, allyOrEnemy, handlesToIgnore)
  local res = {Result = false, Positions = {}, Objects = {}}
  if type(handlesToIgnore) ~= "table" then handlesToIgnore = {} end
  if type(allyOrEnemy) ~= "string" or allyOrEnemy ~= "ally" then allyOrEnemy = "enemy" end

  local dist = startPos:Distance(endPos)
  local spellPath = Geometry.Path(startPos, endPos)
  for k, obj in pairs(ObjectManager.Get(allyOrEnemy, "heroes")) do
    if not handlesToIgnore[k] then
      local hero = obj.AsHero
      local pos = hero:FastPrediction(delay/1000 + hero:EdgeDistance(startPos)/speed)

      if pos:Distance(startPos) < dist and hero.IsTargetable then
        local isOnSegment, pointSegment, pointLine = pos:ProjectOn(startPos, endPos)
        local lineDist = pointSegment:Distance(pos)
        if isOnSegment and lineDist < (hero.BoundingRadius + width*0.5 + 25) then
          table.insert(res.Positions, pos:Extended(pointSegment, lineDist):SetHeight(startPos.y))
          table.insert(res.Objects, hero)
          if #res.Positions < minResults then
            res.Result = false
          else
            res.Result = true
          end
        end
      end
    end
  end
  return res
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

function Utils.CanKill(target,delay,dmg)
  local predHp = HPred.GetHealthPrediction(target,delay,false)
  local incomingDamage = HPred.GetDamagePrediction(target,1,true)
  if incomingDamage > target.Health then return false end
  if predHp < dmg then
    return true
  end
  return false
end

function Elise.CountEnemiesInRangeDelay(pos,range,delay)
  local count = 0
  for k, enemy in pairs(ObjectManager.Get("enemy", "heroes")) do
    local target = enemy.AsHero
    if Utils.IsValidTarget(target) then
      local pred = target:FastPrediction(delay)
      if pos:Distance(pred) < range then
        count = count + 1
      end
    end
  end
  return count
end

function Elise.LogicQ()
  if humanGirl then
    if (Combo and Menu.Get("qCombo")) or (Harass and Menu.Get("qHarass")) then
      local target = TS:GetTarget(Elise.Q.Range)
      if TS:IsValidTarget(target,Elise.Q.Range) then
        if Elise.Q:CanCast(target) then
          if Elise.Q:Cast(target) then return true end
        end
      end
    end
  end
  if spiderGirl then
    if Combo and Menu.Get("qCombo.Spider") then
      local target = TS:GetTarget(Elise.Q2.Range)
      if TS:IsValidTarget(target,Elise.Q2.Range) then
        if Elise.Q2:Cast(target) then return true end
      end
    end
  end
  return false
end

function Elise.LogicW()
  if humanGirl then
    if (Combo and Menu.Get("wCombo")) or (Harass and Menu.Get("wHarass")) then
      for k, enemy in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
        local target = enemy.AsHero
        if (Utils.CanMove(target) and TS:IsValidTarget(target,Elise.Q.Range)) or (not Utils.CanMove(target) and TS:IsValidTarget(target,Elise.W.Range))  then
          local wPred = Elise.W:GetPrediction(target)
          if Elise.W:CanCast(target) and wPred and wPred.HitChanceEnum >= HitChanceEnum.Low then
            if Elise.W:Cast(wPred.CastPosition) then return true end
          end
        end
      end
    end
  end
  if spiderGirl then
    if Combo and Menu.Get("wCombo.Spider") then
      for k, enemy in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
        local target = enemy.AsHero
        if TS:IsValidTarget(target,Orbwalker.GetTrueAutoAttackRange(Player)+100) then
          if Elise.W2:Cast() then return true end
        end
      end
    end
  end
  return false
end

function Elise.LogicE()
  if humanGirl then
    if (Combo and Menu.Get("eCombo")) or (Harass and Menu.Get("eHarass")) then
      for k, enemy in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
        local target = enemy.AsHero
        if TS:IsValidTarget(target,Elise.E.Range) then
          local ePred = Elise.E:GetPrediction(target)
          if Elise.E:CanCast(target) and ePred and ePred.HitChanceEnum >= HitChanceEnum.Medium and not Player.IsWindingUp and not Player.Pathing.IsDashing then
            if Elise.E:Cast(ePred.CastPosition) then return true end
          end
        end
      end
    end
  end
  if spiderGirl then
    if Combo and (Menu.Get("eCombo.Spider") or Utils.HasBuff(Player,"EliseSpiderE")) then
      local target = TS:GetTarget(Elise.E.Range)
      if TS:IsValidTarget(target,Elise.E.Range) then
        printf(Elise.ReachTime(target))
        if Player:Distance(target.Position) <= Elise.E2.Range and Player:Distance(target.Position) > Elise.Q2.Range and (Elise.ReachTime(target) > 2.2 or target.HealthPercent < 10 or (not Elise.Q2:IsReady() and not Elise.W2:IsReady())) then
          if Elise.E2:Cast(target) then return true end
        end
      end
    end
  end
  return false
end

function Elise.LogicR()
  if humanGirl then
    if Combo and Menu.Get("rCombo") then
      if not Elise.Q:IsReady() and not Elise.W:IsReady() then
        if Elise.R:Cast() then return true end
      end
    end
  end
  if spiderGirl then
    if Combo and Menu.Get("rCombo") then
      if not Elise.Q:IsReady() and not Elise.W:IsReady() and (Utils.CountEnemiesInRange(Player.Position,Orbwalker.GetTrueAutoAttackRange(Player)+100) == 0 or humQready or humWready) then
        if Elise.R:Cast() then return true end
      end
    end
  end
  return false
end

function Elise.OnBuffGain(obj,buffInst)
  if obj.IsAlly then
    if printf(buffInst.Name) then return true end
  end
  return false
end

function Elise.ReachTime(target)
  local aaRange = Player.AttackRange + target.BoundingRadius
  local dist = Player:Distance(target.Position)
  local walkPos = Vector(0,0,0)
  if target.Pathing.IsMoving then
    local tPos = target.Position
    walkPos = tPos +(target.Pathing.EndPos - tPos) : Normalized() * 100
  end
  local tSpeed = 0
  if target.IsMoving and Player:Distance(walkPos) > dist then
    tSpeed = target.MoveSpeed
  end
  local msDif = 0
  if Player.MoveSpeed - tSpeed == 0 then
    msDif = 0.0001
  else
    msDif = Player.MoveSpeed - tSpeed
  end
  local tReach = (dist - aaRange) / msDif
  if tReach >= 0 then
    return tReach
  else
    return math_huge
  end
end

function Elise.Farm()
  if Laneclear then
    local monsters = Utils.CountMinionsInRange(Orbwalker.GetTrueAutoAttackRange(Player)+100, "neutral")
    local minions = Utils.CountMinionsInRange(Orbwalker.GetTrueAutoAttackRange(Player)+100, "enemy")
    if minions > monsters then
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "enemy",Orbwalker.GetTrueAutoAttackRange(Player)+100)
      if minionFocus == nil then return false end
      if humanGirl then
        if Elise.Q:IsReady() and Elise.Q:CanCast(minionFocus) and Menu.Get("qFarm") then
          if Elise.Q:Cast(minionFocus) then return true end
        end
        if Elise.W:IsReady() and Elise.W:CanCast(minionFocus) and Menu.Get("wFarm") then
          if Elise.W:Cast(minionFocus.Position) then return true end
        end
      end
      if spiderGirl then
        if Elise.Q2:IsReady() and Menu.Get("qFarm.Spider") then
          if Elise.Q2:Cast(minionFocus) then return true end
        end
        if Elise.W2:IsReady() and Menu.Get("wFarm.Spider") then
          if Elise.W2:Cast() then return true end
        end
      end
    else
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "neutral", Orbwalker.GetTrueAutoAttackRange(Player)+100)
      if minionFocus == nil then return false end
      -- if not Player.IsWindingUp then
      -- TS:ForceTarget(minionFocus)
      -- end
      if humanGirl then
        if minionFocus.IsScuttler and Elise.E:IsReady() and Menu.Get("eFarm") then
          local ePred = Elise.E:GetPrediction(minionFocus)
          if ePred and ePred.HitChanceEnum >= HitChanceEnum.Medium then
            if Elise.E:Cast(ePred.CastPosition) then return true end
          end
        end
        if Elise.Q:IsReady() and Elise.Q:CanCast(minionFocus) and Menu.Get("qFarm") then
          if Elise.Q:Cast(minionFocus) then return true end
        end
        if Elise.W:IsReady() and Elise.W:CanCast(minionFocus) and Menu.Get("wFarm") then
          if Elise.W:Cast(minionFocus.Position) then return true end
        end
        if Elise.R:IsReady() and not Elise.Q:IsReady() and not Elise.W:IsReady() and Menu.Get("autoswitch") then
          if Elise.R:Cast() then return true end
        end
      end
      if spiderGirl then
        if Elise.Q2:IsReady() and Menu.Get("qFarm.Spider") then
          if Elise.Q2:Cast(minionFocus) then return true end
        end
        if Elise.W2:IsReady() and Menu.Get("wFarm.Spider") then
          if Elise.W2:Cast() then return true end
        end
        if Elise.R:IsReady() and not Elise.Q2:IsReady() and not Elise.W2:IsReady() and Menu.Get("autoswitch") then
          if Elise.R:Cast() then return true end
        end
      end
    end
  end
  return false
end

function Elise.OnGapclose(source,dash)
  if source.IsEnemy and not source.IsHero and Menu.Get("anti-gap") then
    local paths = dash:GetPaths()
    local endPos = paths[#paths].EndPos
    local startPos = paths[#paths].StartPos
    if Player:Distance(endPos) <= 100 and Elise.E2:IsReady() then
      if Elise.E2:Cast(endPos) then return true end
    end
  end
  return false
end

function Elise.KillSteal()
  local spiderQKs = Menu.Get("spiderQKS")
  local humanQKS = Menu.Get("humanQKS")
  for k, enemy in pairs(ObjectManager.GetNearby("enemy", "heroes")) do
    local target = enemy.AsHero
    if humanGirl then
      if TS:IsValidTarget(target,Elise.Q.Range) and humanQKS and Elise.Q:GetKillstealHealth(target) <= Elise.Q:GetDamage(target) then
        if Elise.Q:CanCast(target) then
          if Elise.Q:Cast(target) then return true end
        end
      end
    end
    if spiderGirl then
      if TS:IsValidTarget(target,Elise.Q2.Range) and spiderQKs and Elise.Q2:GetKillstealHealth(target) <= Elise.Q2:GetDamage(target) then
        if Elise.Q2:CanCast(target) then
          if Elise.Q2:Cast(target) then return true end
        end
      end
    end
  end
end

function Elise.SpiderCheck()
  if Player:GetSpell(SpellSlots.Q).Name == "EliseHumanQ" then
    spiderGirl = false
    humanGirl = true
  end
  if Player:GetSpell(SpellSlots.Q).Name == "EliseSpiderQCast" then
    spiderGirl = true
    humanGirl = false
  end
end

function Elise.GetCd()
  if humanGirl then
    if Player:GetSpell(SpellSlots.Q).Name == "EliseHumanQ" then
      humQcd = Player:GetSpell(SpellSlots.Q).CooldownExpireTime
    end
    if Player:GetSpell(SpellSlots.W).Name == "EliseHumanW" then
      humWcd = Player:GetSpell(SpellSlots.W).CooldownExpireTime
    end
    if Player:GetSpell(SpellSlots.E).Name == "EliseHumanE" then
      humEcd = Player:GetSpell(SpellSlots.E).CooldownExpireTime
    end
  else
    if Player:GetSpell(SpellSlots.Q).Name == "EliseSpiderQCast" then
      spidQcd = Player:GetSpell(SpellSlots.Q).CooldownExpireTime
    end
    if Player:GetSpell(SpellSlots.W).Name == "EliseSpiderW" then
      spidWcd = Player:GetSpell(SpellSlots.W).CooldownExpireTime
    end
    if Player:GetSpell(SpellSlots.E).Name == "EliseSpiderEInitial" then
      spidEcd = Player:GetSpell(SpellSlots.E).CooldownExpireTime
    end
  end
end

function Elise.CoolDowns()
  if humQcd - Game.GetTime() >= 0 then
    humQready = true
  else
    humQready = false
  end
  if humWcd - Game.GetTime() >= 0 then
    humWready = true
  else
    humWready = false
  end
  if humEcd - Game.GetTime() >= 0 then
    humEready = true
  else
    humEready = false
  end
  if spidQcd - Game.GetTime() >= 0 then
    spidQready = true
  else
    spidQready = false
  end
  if spidWcd - Game.GetTime() >= 0 then
    spidWready = true
  else
    spidWready = false
  end
  if spidEcd - Game.GetTime() >= 0 then
    spidEready = true
  else
    spidEready = false
  end
end

function Elise.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  Elise.SpiderCheck()
  Elise.GetCd()
  Elise.CoolDowns()
  Elise.KillSteal()

  if Utils.NoLag(0)  then
    if Elise.Farm() then return true end
  end
  if Utils.NoLag(1) and Elise.Q:IsReady() then
    if Elise.LogicQ() then return true end
  end
  if Utils.NoLag(2) and Elise.E:IsReady()  then
    if Elise.LogicE() then return true end
  end
  if Utils.NoLag(3) and Elise.W:IsReady() then
    if Elise.LogicW() then return true end
  end
  if Utils.NoLag(4) and Elise.R:IsReady() then
    if Elise.LogicR() then return true end
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
  if OrbwalkerMode == "Waveclear" or OrbwalkerMode == "Lasthit"  then
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
function Elise.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Elise.E2}
    for k, v in pairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  local status, color
  local p = Player.Position:ToScreen()
  if Menu.Get("eCombo.Spider") then
    status, color = "Rappel: Enabled", 0x00FF00FF
    p.x = p.x - 63
    p.y = p.y + 33
  else
    status, color = "Rappel: Disabled", 0xFF0000FF
    p.x = p.x - 66
    p.y = p.y + 33
  end
  Renderer.DrawText(p, {x=500,y=500}, status, color)
  return false
end
function Elise.LoadMenu()
  local function EliseMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("> Q", 0xB65A94FF, true)
    Menu.Checkbox("qCombo", "Q Human Combo", true)
    Menu.Checkbox("qCombo.Spider", "Q Spider Combo", true)
    Menu.Checkbox("qHarass", "Q Human Harass", true)
    Menu.ColoredText("> W", 0x118AB2FF, true)
    Menu.Checkbox("wCombo", "W Human Combo", true)
    Menu.Checkbox("wCombo.Spider", "W Spider Combo", true)
    Menu.Checkbox("wHarass", "W Human Harass", true)
    Menu.ColoredText("> E", 0xB65A94FF, true)
    Menu.Checkbox("eCombo", "E Human Combo", true)
    Menu.Keybind("eCombo.Spider", "Toggle E Spider Combo", string.byte('T'), true,true)
    Menu.Checkbox("eHarass", "E Human Harass", true)
    Menu.ColoredText("> R", 0xB65B94FF, true)
    Menu.Checkbox("rCombo", "Auto Switch Form Combo", true)
    Menu.ColoredText("KillSteal", 0xB65A91FF, true)
    Menu.Checkbox("humanQKS", "Q Human Ks", true)
    Menu.Checkbox("spiderQKS", "Q Spider Ks", true)
    Menu.ColoredText("Farm", 0xB65A97FF, true)
    Menu.Checkbox("qFarm", "Q Farm Human", true)
    Menu.Checkbox("wFarm", "W Farm Human", true)
    Menu.Checkbox("eFarm", "E Farm Human Scuttler", true)
    Menu.Checkbox("qFarm.Spider", "Q Farm Spider", true)
    Menu.Checkbox("wFarm.Spider", "W Farm Spider", true)
    Menu.Checkbox("autoswitch", "Auto Switch", false)
    Menu.ColoredText("Misc", 0xB65B97FF, true)
    Menu.Checkbox("anti-gap", "Anti-gapcloser Spider E", true)
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("Drawing.E.Enabled",   "Draw Rappel Range",true)
    Menu.ColorPicker("Drawing.E.Color", "Draw Rappel Color", 0x118AB2FF)
    Menu.Separator()
    end)
  end
  if Menu.RegisterMenu("Simple Elise", "Simple Elise", EliseMenu) then return true end
  return false
end

function OnLoad()
  Elise.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Elise[EventName] then
      EventManager.RegisterCallback(EventId, Elise[EventName])
    end
  end
  return true
end
