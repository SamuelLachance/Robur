if Player.CharName ~= "Khazix" then return end
module("Simple KhaZix", package.seeall, log.setup)
clean.module("Simple KhaZix", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleKhaZix", "1.0.0"
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
local KhaZix = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Laneclear,None = false,false,false, false
local target = nil
local qRange = 0
local eRange = 0
if Player:GetSpell(SpellSlots.Q).Name == "khazixqlong" then
  qRange = 375
else
  qRange = 325
end

if Player:GetSpell(SpellSlots.E).Name == "khazixelong" then
  eRange = 900
else
  eRange = 700
end

KhaZix.Q = SpellLib.Targeted({
  Slot = SpellSlots.Q,
  Range = qRange,
  Key = "Q"
})

KhaZix.W = SpellLib.Skillshot({
  Slot = SpellSlots.W,
  Range = 1000,
  Delay = 0.25,
  Speed = 1700,
  Radius = 140,
  Type = "Linear",
  Key = "W"
})

KhaZix.E = SpellLib.Skillshot({
  Slot = SpellSlots.E,
  Range = eRange,
  Radius = 300,
  Speed = 1000,
  Delay = 0.25,
  Type = "Circular",
  Key = "E"
})

KhaZix.R = SpellLib.Active({
  Slot = SpellSlots.R,
  Key = "R"
})

local Utils = {}
local lastQ = 0

function Utils.IsGameAvailable()
  return not (
  Game.IsChatOpen()  or
  Game.IsMinimized() or
  Player.IsDead
  )
end

function Utils.SetMana()
  if KhaZix.Q:IsReady() then
    qMana = KhaZix.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if KhaZix.W:IsReady() then
    wMana = KhaZix.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if KhaZix.E:IsReady() then
    eMana = KhaZix.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if KhaZix.R:IsReady() then
    rMana = KhaZix.R:GetManaCost()
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
    local KhaZixUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or KhaZixUlt  or TargetAi.IsZombie or TargetAi.IsDead then
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
        if minion.Health > minionFocus.Health then
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
  if predHp < dmg then
    return true
  end
  return false
end

function Utils.IsInSpellRange(target,spell)
  local tB = target.BoundingRadius*0.9
  local dist = target.Position:DistanceSqr(Player.Position)
  if dist < (tB + spell.Range)*(tB + spell.Range) then
    return true
  end
  return false
end

function KhaZix.LogicQ()
  if Combo then
    if Utils.IsInSpellRange(target,KhaZix.Q) then
      if KhaZix.Q:Cast(target) then return true end
    end
  end
  return false
end

function KhaZix.LogicW()
  if Combo then
    local wPred = KhaZix.W:GetPrediction(target)
    if wPred and wPred.HitChanceEnum >= HitChanceEnum.High and Utils.IsInSpellRange(target,KhaZix.W) then
      if KhaZix.W:Cast(wPred.CastPosition) then return true end
    end
  end
  return false
end

function KhaZix.LogicE1()
  if KhaZix.ReachTime(target) < 0.3 then return false end
  if Combo then
    local ePred = KhaZix.E:GetPrediction(target)
    if ePred and ePred.HitChanceEnum >= HitChanceEnum.High and Player:Distance(target.Position) > KhaZix.Q.Range then
      if KhaZix.E:Cast(ePred.CastPosition) then return true end
    end
  end
  return false
end

function KhaZix.LogicE2()
  local aaRange = Player.AttackRange + target.BoundingRadius
  local eRange = KhaZix.E.Range + target.BoundingRadius
  local dist = Player:Distance(target.Position)
  local timeToReach = KhaZix.ReachTime(target)
  if dist > aaRange and dist < eRange then
    if timeToReach > 2.2 then
      if KhaZix.LogicE1() then return true end
    end
  end
  return false
end

function KhaZix.LogicR()
  local dist = Player:Distance(target.Position)
  if Combo then
    if Utils.CountHeroes(Player.Position,600,"enemy") > 2 or not Utils.HasBuff(Player,"khazixpdamage") or (KhaZix.ReachTime(target) > 1 and Utils.CanKill(target,0,KhaZix.ComboDMG(target))) then
      if dist < 375 and (not KhaZix.Q:IsReady() or KhaZix.E:IsReady()) and (dist > KhaZix.Q.Range or not KhaZix.Q:IsReady()) then
        if KhaZix.R:Cast() then return true end
      end
    end
  end
  return false
end

function KhaZix.ReachTime(target)
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

function KhaZix.GetBestRange()
  if KhaZix.E:IsReady() then
    return KhaZix.E.Range + Orbwalker.GetTrueAutoAttackRange(Player)
  end
  if KhaZix.W:IsReady() then
    return KhaZix.W.Range
  end
  return KhaZix.Q.Range
end

function KhaZix.Jungle()
  if Laneclear then
    local monsters = Utils.CountMinionsInRange(KhaZix.W.Range, "neutral")
    local minions = Utils.CountMinionsInRange(KhaZix.W.Range, "enemy")
    if minions > monsters then
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "enemy",KhaZix.Q.Range)
      if minionFocus == nil then return false end
      if KhaZix.Q:IsReady() and Menu.Get("qFarm")and Player.Mana > qMana + wMana + eMana then
        if KhaZix.Q:Cast(minionFocus) then return true end
      end
      if Player.Mana > qMana + wMana + eMana and KhaZix.W:IsReady() and Menu.Get("wFarm") then
        local hitCount = Utils.LinearCastMinionPos(Player.Position, "enemy", KhaZix.W.Range,KhaZix.W,140).hitCount
        local wPos = Utils.LinearCastMinionPos(Player.Position, "enemy", KhaZix.W.Range,KhaZix.W,140).spellPos
        if hitCount >= 3 then
          if KhaZix.W:Cast(wPos) then return true end
        end
      end
    else
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "neutral", KhaZix.Q.Range)
      if minionFocus == nil then return false end
      if minionFocus.IsEpicMinion  then
        if KhaZix.Q:IsReady() and Player.Mana > qMana and Menu.Get("qFarm") then
          if KhaZix.Q:Cast(minionFocus) then return true end
        end
        if KhaZix.W:IsReady() and (Player.Mana > qMana + wMana or (Player.Mana > wMana and not KhaZix.Q:IsReady())) and Menu.Get("wFarm") then
          if KhaZix.W:Cast(minionFocus.Position) then return true end
        end
      else
        if KhaZix.Q:IsReady() and Player.Mana > qMana and Menu.Get("qFarm") and not KhaZix.W:IsReady() then
          if KhaZix.Q:Cast(minionFocus) then return true end
        end
        if KhaZix.W:IsReady() and Menu.Get("wFarm") and (Player.Mana > qMana + wMana or (Player.Mana > wMana and not KhaZix.Q:IsReady())) and Menu.Get("wFarm") then
          local wPos = Utils.LinearCastMinionPos(Player.Position, "neutral", KhaZix.Q.Range,KhaZix.W,140).spellPos
          if KhaZix.W:Cast(wPos) then return true end
        end
      end
    end
  end
  return false
end

function KhaZix.ComboDMG(target)
  local dmg = 0
  if Utils.HasBuff(Player,"khazixpdamage") then
    dmg = dmg + DamageLib.CalculateMagicalDamage(Player, target, 10*10*Player.Level+0.5*Player.FlatMagicalDamageMod)
  end
  if KhaZix.Q:IsReady() then
    if KhaZix.Isolated(target) then
      dmg = dmg + DamageLib.CalculatePhysicalDamage(Player, target, (35+25*Player.Level+1.3*Player.BonusAD)*2.1)
    else
      dmg = dmg + DamageLib.CalculatePhysicalDamage(Player, target, 35+25*Player.Level+1.3*Player.BonusAD)
    end
  end
  if KhaZix.W:IsReady() then
    dmg = dmg + DamageLib.CalculatePhysicalDamage(Player, target, 55+35*Player.Level+Player.BonusAD)
  end
  if KhaZix.E:IsReady() then
    dmg = dmg + DamageLib.CalculatePhysicalDamage(Player, target, 30+35*Player.Level+0.2*Player.BonusAD)
  end
  return dmg/1.3
end

function KhaZix.Isolated(target)
  if Utils.CountHeroes(target.Position,500,"enemy") < 2 then
    return true
  end
  return false
end

function KhaZix.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {KhaZix.Q,KhaZix.W,KhaZix.E,KhaZix.R}
    for k, v in pairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  return false
end

function KhaZix.OnDrawDamage(target, dmgList)
  if Menu.Get("DrawDmg") then
    table.insert(dmgList, KhaZix.ComboDMG(target))
  end
end

function KhaZix.OnUpdate()
  if not Utils.IsGameAvailable() then return false end
  if Utils.NoLag(0) and not Orbwalker.IsWindingUp() then
    if KhaZix.Jungle() then return true end
  end
  target = TS:GetTarget(KhaZix.GetBestRange())
  if Utils.IsValidTarget(target) then
    if Utils.HasBuff(Player,"khazixrstealth") and Utils.CountHeroes(Player.Position,600,"enemy") > 2 and Utils.CanKill(target,0,KhaZix.ComboDMG(target)) then
      Orbwalker.BlockAttack(true)
    else
      if Utils.NoLag(1) and KhaZix.Q:IsReady() and Menu.Get("autoQ") and not Orbwalker.IsWindingUp() then
        if KhaZix.LogicQ() then return true end
      end
      Orbwalker.BlockAttack(false)
      if Utils.NoLag(3) and KhaZix.W:IsReady() and Menu.Get("autoW") and not Orbwalker.IsWindingUp() then
        if KhaZix.LogicW() then return true end
      end
      if Utils.NoLag(2) and KhaZix.E:IsReady() and Menu.Get("autoE") then
        if Utils.CanKill(target,0,KhaZix.ComboDMG(target)) then
          if KhaZix.LogicE1() then return true end
        elseif not Utils.HasBuff(Player,"khazixrstealth") then
          if KhaZix.LogicE2() then return true end
        end
      end
    end
    if Utils.NoLag(4) and KhaZix.R:IsReady() and Menu.Get("autoR") then
      if KhaZix.LogicR() then return true end
    end
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
  if OrbwalkerMode == "Waveclear" or OrbwalkerMode == "Lasthit" then
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

function KhaZix.LoadMenu()
  local function KhaZixMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("> Q", 0xB65A94FF, true)
    Menu.Checkbox("autoQ", "Auto Q", false)
    Menu.ColoredText("> W", 0x118AB2FF, true)
    Menu.Checkbox("autoW", "Auto W", true)
    Menu.ColoredText("> E", 0xB65A94FF, true)
    Menu.Checkbox("autoE", "Auto E", true)
    Menu.ColoredText("> R", 0xB65A94FF, true)
    Menu.Checkbox("autoR", "Auto R", false)
    Menu.ColoredText("Farm", 0xB65A94FF, true)
    Menu.Checkbox("qFarm", "Q Farm", true)
    Menu.Checkbox("wFarm", "W Farm", true)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("DrawDmg", "Draw Damage", true)
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
  if Menu.RegisterMenu("Simple KhaZix", "Simple KhaZix", KhaZixMenu) then return true end
  return false
end

function OnLoad()
  KhaZix.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if KhaZix[EventName] then
      EventManager.RegisterCallback(EventId, KhaZix[EventName])
    end
  end
  return true
end
