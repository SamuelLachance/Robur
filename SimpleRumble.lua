if Player.CharName ~= "Rumble" then return end

module("Simple Rumble", package.seeall, log.setup)
clean.module("Simple Rumble", clean.seeall, log.setup)
local CoreEx = _G.CoreEx
local Libs = _G.Libs
local ScriptName, Version = "SimpleRumble", "1.0.0"
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
local Rumble = {}
local qMana = 0
local wMana = 0
local eMana = 0
local rMana = 0
local iTick = 0
local Combo,Harass,Laneclear,None = false,false,false, false
local eOnGround = {}
local qFive = {}
local Qobj = {}
local fullQ = false
local eIsOn = false
local BallPos = Vector(0,0,0)
Rumble.Q = SpellLib.Skillshot({
  Slot = SpellSlots.Q,
  Range = 600,
  Delay = 0.5,
  Radius = 240,
  Speed = 1300,
  Type = "Cone",
  Key = "Q"
})

Rumble.W = SpellLib.Active({
  Slot = SpellSlots.W,
  Key = "W"
})

Rumble.E = SpellLib.Skillshot({
  Slot = SpellSlots.E,
  Range = 950,
  Delay = 0.25,
  Speed = 2000,
  Radius = 120,
  Collisions = {Minions = true, WindWall = true },
  Type = "Linear",
  Key = "E"
})

Rumble.R = SpellLib.Skillshot({
  Slot = SpellSlots.R,
  Range = 1700,
  Radius = 410,
  Delay = 0,
  Speed = 1600,
  Type = "Linear",
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
  if Rumble.Q:IsReady() then
    qMana = Rumble.Q:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    qMana = 0
  else
    qMana = 0
  end
  if Rumble.W:IsReady() then
    wMana = Rumble.W:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    wMana = 0
  else
    wMana = 0
  end
  if Rumble.E:IsReady() then
    eMana = Rumble.E:GetManaCost()
  elseif (Player.Health/Player.MaxHealth) * 100 < 20 then
    eMana = 0
  else
    eMana = 0
  end
  if Rumble.R:IsReady() then
    rMana = Rumble.R:GetManaCost()
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
    local RumbleUlt = TargetAi:GetBuff("chronoshift")

    if KindredUlt or TryndUlt or KayleUlt or RumbleUlt  or TargetAi.IsZombie or TargetAi.IsDead then
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
        if minion.Health < minionFocus.Health or minionFocus:Distance(pos) > minion:Distance(pos) then
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
  local predHp = HPred.GetHealthPrediction(target,delay,true)
  local incomingDamage = HPred.GetDamagePrediction(target,2,true)
  if incomingDamage > target.Health then return false end
  if predHp < dmg then
    return true
  end
  return false
end

function Utils.PassWall(Start,End)
  local count = Start:Distance(End)
  for i=0 , count , 25 do
    local pos = Start:Extended(Player.Position,-i)
    if Nav.IsWall(pos) then
      return true
    end
  end
  return false
end

function Rumble.KeepHeat()
  if Player.Mana < 50 then
    if Rumble.Q:IsReady() and Utils.CountHeroes(Player.Position,1500, "Enemy") < 1 then
      if Rumble.Q:Cast(Renderer.GetMousePos()) then return true end
    end
    if Rumble.W:IsReady() then
      if Rumble.W:Cast() then return true end
    end
  end
  return false
end

function Rumble.LogicQ()
  local target = TS:GetTarget(Rumble.Q.Range)
  if Utils.IsValidTarget(target) and Utils.IsFacing(target,Player) then
    if Rumble.Q:Cast(target.Position) then return true end
  end
  return false
end

function Rumble.LogicW()
  for k, enemy in ipairs(ObjectManager.GetNearby("enemy", "heroes")) do
    if Utils.IsValidTarget(enemy) and Player:Distance(enemy.AsHero.Position) < 400 and enemy.IsVisible then
      if Rumble.W:Cast() then return true end
    end
  end
end
function Rumble.LogicE()
  local target = TS:GetTarget(Rumble.E.Range)
  if Utils.IsValidTarget(target) and (Combo or Harass) then
    local ePred = Rumble.E:GetPrediction(target)
    if not Utils.CanMove(target) then
      if Rumble.E:Cast(target.Position) then return true end
    elseif ePred and ePred.HitChanceEnum >= HitChanceEnum.High then
      if Rumble.E:Cast(ePred.CastPosition) then return true end
    end
  elseif Utils.IsValidTarget(target) and target.Health <= Rumble.GetDamageE(target) then
    local ePred = Rumble.E:GetPrediction(target)
    if ePred and ePred.HitChanceEnum >= HitChanceEnum.Low then
      if Rumble.E:Cast(ePred.CastPosition) then return true end
    end
  end
  return false
end

function Rumble.LogicR()
  if Menu.Get("CastR") then
    if Rumble.CastR() then return true end
  end
  local enemies = {}
  for k, enemy in pairs(ObjectManager.Get("enemy", "heroes")) do
    local target = enemy.AsHero
    local pos = target:FastPrediction(Game.GetLatency() + Rumble.R.Delay)
    if Utils.IsValidTarget(target) and Player:Distance(target.Position) <= Rumble.R.Range+100 then
      table.insert(enemies, pos)
    end
  end
  local rCastPosL, hitCountL = Rumble.R:GetBestLinearCastPos(enemies,Rumble.R.Radius)
  local rCastPosC, hitCountC = Rumble.R:GetBestCircularCastPos(enemies,Rumble.R.Radius)
  if hitCountL >= Menu.Get("HitcountR") then
    if Rumble.CastR() then return true end
  elseif hitCountC >= Menu.Get("HitcountR") then
    if Rumble.CastR() then return true end
  end
  local target = TS:GetTarget(Rumble.R.Range)
  if Utils.IsValidTarget(target) and Menu.Get("rKS") then
    if Utils.CanKill(target,Rumble.R.Delay,Rumble.GetDamageR(target)) then
      if Rumble.CastR() then return true end
    end
  end
  return false
end

function Rumble.CastR()
  local target = TS:GetTarget(Rumble.R.Range)
  if Utils.IsValidTarget(target) and Utils.ValidUlt(target) then
    local v1 = target.Position - (target.Position - Player.Position):Normalized() * 300
    local pred = Rumble.R:GetPrediction(target)
    if Player:Distance(target.Position) < 400 and pred then
      local midpoint = (Player.Position + pred.TargetPosition) /2
      v1 = midpoint + (pred.TargetPosition - Player.Position):Normalized() * 800
      local v2 = midpoint - (pred.TargetPosition - Player.Position):Normalized() * 300
      if not Utils.PassWall(pred.TargetPosition, v1) and not Utils.PassWall(pred.TargetPosition,v2)  then
        if Input.Cast(SpellSlots.R,v1,v2) then return true end
      end
    elseif pred and not Utils.PassWall(pred.TargetPosition,v1) and not Utils.PassWall(pred.TargetPosition,pred.CastPosition) then
      if pred.HitChanceEnum >= HitChanceEnum.High then
        if Input.Cast(SpellSlots.R,v1,pred.CastPosition) then return true end
      end
    end
  end
  return false
end

function Rumble.Farm()
  if Laneclear then
    local monsters = Utils.CountMinionsInRange(Rumble.E.Range, "neutral")
    local minions = Utils.CountMinionsInRange(Rumble.E.Range, "enemy")
    if minions > monsters then
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "enemy",Rumble.E.Range)
      if minionFocus == nil then return false end
      local eDmg = Rumble.GetDamageE(minionFocus)
      if Rumble.E:IsReady() and Menu.Get("eFarm") and Player:Distance(minionFocus) > Orbwalker.GetTrueAutoAttackRange() and minionFocus.Health < eDmg then
        local ePred = Rumble.E:GetPrediction(minionFocus)
        if ePred and ePred.HitChanceEnum >= HitChanceEnum.Medium then
          if Rumble.E:Cast(ePred.CastPosition) then return true end
        end
      end
    else
      local minionFocus = Utils.GetPriorityMinion(Player.Position, "neutral", Rumble.Q.Range)
      if minionFocus == nil then return false end
      if Rumble.Q:IsReady() and Menu.Get("qFarm") then
        if Rumble.Q:Cast(minionFocus.Position) then return true end
      end
      if Rumble.E:IsReady() and Menu.Get("eFarm") then
        if Rumble.E:Cast(minionFocus.Position) then return true end
      end
    end
  end
  return false
end

function Rumble.OnProcessSpell(sender,spell)
  if sender.IsHero and sender.IsEnemy and Rumble.W:IsReady() and Player:Distance(sender.Position) < 700 and (not spell.IsBasicAttack or spell.IsSpecialAttack) and Menu.Get("autoW") then
    if Utils.CanHit(Player,spell) then
      if Rumble.W:Cast() then return true end
    end
    if spell.Target and spell.Target.IsMe then
      if Rumble.W:Cast() then return true end
    end
  end
  return false
end

function Rumble.GetDamageQ(target)
  local playerAI = Player.AsAI
  local dmgQ = 11.7 + 3.3 * Player:GetSpell(SpellSlots.Q).Level
  local bonusDmg = playerAI.TotalAP * 0.917
  local totalDmg = (dmgQ+bonusDmg) * 6

  return DamageLib.CalculateMagicalDamage(Player, target, totalDmg)
end

function Rumble.GetDamageE(target)
  local playerAI = Player.AsAI
  local dmgE = 35 + 25 * Player:GetSpell(SpellSlots.E).Level
  local bonusDmg = playerAI.TotalAP * 0.40
  local totalDmg = dmgE+bonusDmg

  return DamageLib.CalculateMagicalDamage(Player, target, totalDmg)
end

function Rumble.GetDamageR(target)
  local playerAI = Player.AsAI
  local dmgR = 35 + 35 * Player:GetSpell(SpellSlots.R).Level
  local bonusDmg = playerAI.TotalAP * 0.175
  local totalDmg = (dmgR+bonusDmg) * 2.5

  return DamageLib.CalculateMagicalDamage(Player, target, totalDmg)
end

function Rumble.GetDamage(target)
  local rCD = 0
  if Rumble.R:IsReady() then
    rCD = 1
  end
  return Rumble.GetDamageQ(target) + Rumble.GetDamageE(target)  + Rumble.GetDamageR(target)*rCD
end

function Rumble.OnDrawDamage(target, dmgList)
  if Menu.Get("DrawDmg") then
    table.insert(dmgList, Rumble.GetDamage(target))
  end
end

function Rumble.OnDraw()
  if Player.IsVisible and Player.IsOnScreen and not Player.IsDead then
    local Pos = Player.Position
    local spells = {Rumble.Q}
    for k, v in pairs(spells) do
      if Menu.Get("Drawing."..v.Key..".Enabled", true) then
        if Renderer.DrawCircle3D(Pos, v.Range, 30, 3, Menu.Get("Drawing."..v.Key..".Color")) then return true end
      end
    end
  end
  return false
end

function Rumble.OnUpdate()
  if not Utils.IsGameAvailable() then return false end

  if Utils.NoLag(0)  then
    if Rumble.Farm() then return true end
  end
  if Utils.NoLag(1) and Rumble.Q:IsReady() and Menu.Get("autoQ") then
    if Rumble.LogicQ() then return true end
  end
  if Utils.NoLag(2) and Rumble.E:IsReady() and Menu.Get("autoE") then
    if Rumble.LogicE() then return true end
  end
  if Utils.NoLag(3) and Rumble.W:IsReady() and Menu.Get("autoW") then
    if Rumble.LogicW() then return true end
  end
  if Utils.NoLag(4) and Menu.Get("autoHeat") then
    if Rumble.KeepHeat() then return true end
  end
  if Utils.NoLag(5) and Rumble.R:IsReady() then
    if Rumble.LogicR() then return true end
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
  if OrbwalkerMode == "Waveclear" or OrbwalkerMode == "Lasthit" or OrbwalkerMode == "Harass"  then
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
  if iTick > 5 then
    iTick = 0
  end
  return false
end

function Rumble.LoadMenu()
  local function RumbleMenu()
    Menu.ColumnLayout("Casting", "Casting", 2, true, function ()
    Menu.ColoredText("> Q", 0xB65A94FF, true)
    Menu.Checkbox("autoQ", "Auto Q", true)
    Menu.ColoredText("> W", 0x118AB2FF, true)
    Menu.Checkbox("autoW", "Auto W", true)
    Menu.ColoredText("> E", 0xB65A94FF, true)
    Menu.Checkbox("autoE", "Auto E", true)
    Menu.ColoredText("> R", 0xB65A94FF, true)
    Menu.Slider("HitcountR", "[R] HitCount", 3, 1, 5)
    Menu.Checkbox("rKS", "R KS", true)
    Menu.Keybind("CastR", "Semi [R] Cast", string.byte('T'))
    Menu.ColoredText("Misc", 0xB65A94FF, true)
    Menu.Checkbox("autoHeat", "Auto Heat", false)
    Menu.ColoredText("Farm", 0xB65A94FF, true)
    Menu.Checkbox("qFarm", "Q Farm", true)
    Menu.Checkbox("eFarm", "E Farm", true)
    Menu.Separator()
    Menu.ColoredText("Drawing", 0xB65A94FF, true)
    Menu.Checkbox("DrawDmg", "Draw Damage", true)
    Menu.Checkbox("Drawing.Q.Enabled",   "Draw [Q] Range",true)
    Menu.ColorPicker("Drawing.Q.Color", "Draw [Q] Color", 0x118AB2FF)
    end)
  end
  if Menu.RegisterMenu("Simple Rumble", "Simple Rumble", RumbleMenu) then return true end
  return false
end

function OnLoad()
  Rumble.LoadMenu()
  for EventName, EventId in pairs(Events) do
    if Rumble[EventName] then
      EventManager.RegisterCallback(EventId, Rumble[EventName])
    end
  end
  return true
end
