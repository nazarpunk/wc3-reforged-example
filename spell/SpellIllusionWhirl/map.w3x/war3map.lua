gg_trg_Start = nil
gg_unit_Obla_0000 = nil
function InitGlobals()
end

do
    -- На момент патча 1.31 эта функция всегда возвращает 0. Поэтому создадим её локальный аналог.
    local function AbilityId(id)
        return id:byte(1) * 0x1000000 + id:byte(2) * 0x10000 + id:byte(3) * 0x100 + id:byte(4)
    end

    -- Настройки
    local ABILITY_ID = AbilityId('SIWh')
    local CASTER_DAMAGE_PERIOD = 0.5

    local DUMMY_TIMER_PERIOD = 0.03125 --> 1/16
    local DUMMY_ANIMATION_NAME = 'attack slam'
    local DUMMY_ANIMATION_DURATION = 0.95
    local DUMMY_SPEED = 200 --> расстояние, пройденное за одну секунду
    local DUMMY_ARC = 0.3
    local DUMMY_SPAWN_MIN_DISTANCE = 300
    local DUMMY_SPAWN_MAX_DISTANCE = 1200
    local DUMMY_PLAYER = Player(PLAYER_NEUTRAL_PASSIVE)
    local DUMMY_EFFECT = {
        {'Abilities\\Spells\\Orc\\TrollBerserk\\HeadhunterWEAPONSRight.mdl','weapon'},
        {'Abilities\\Weapons\\DemolisherFireMissile\\DemolisherFireMissile.mdl','weapon'}
    }
    local DUMMY_EXPLODE_RANGE = 150
    local DUMMY_EXPLODE_EFFECT = 'Abilities\\Spells\\Orc\\WarStomp\\WarStompCaster.mdl'
    
    -- Код
    local LOCUST_ID = AbilityId('Aloc')
    local RAVEN_ID = AbilityId('Arav')
    local SPEED_INC = DUMMY_SPEED/(1/DUMMY_TIMER_PERIOD)
    local LOC = Location(0, 0)
    local IS_CHANNEL = {}

    local GetTerrainZ_location = Location(0, 0)
    function GetTerrainZ(x,y)
        MoveLocation(GetTerrainZ_location, x, y);
        return GetLocationZ(GetTerrainZ_location);
    end

    --[[
        zs - начальная высота высота одного края дуги
        ze - конечная высота высота другого края дуги
        h  - максимальная высота на середине расстояния
        d  - общее расстояние до цели
        x  - расстояние от исходной цели до точки
    ]]--
    local function Parabola(zs, ze, h, d, x)
        return (2*(zs + ze - 2*h)*(x/d - 1) + (ze - zs))*(x/d) + zs;
    end

    local function addEffectTarget(effect, target)
        return AddSpecialEffectTarget(effect[1], target, effect[2])
    end

    local function SetUnitZ(unit, z)
        SetUnitFlyHeight(unit, z - GetTerrainZ(GetUnitX(unit), GetUnitY(unit)), 0);
    end

    local function InMapXY(x, y)
        return
            x > GetRectMinX(bj_mapInitialPlayableArea)
            and
            x < GetRectMaxX(bj_mapInitialPlayableArea)
            and
            y > GetRectMinY(bj_mapInitialPlayableArea)
            and
            y < GetRectMaxY(bj_mapInitialPlayableArea)        
    end
    
    local function jump(caster, x, y, distance, angle)
        local angle = math.random(0, 360)
        local cos = Cos(angle)
        local sin = Sin(angle)
        local dist = distance
        local player = GetOwningPlayer(caster)

        local xe = x + distance*cos
        local ye = y + distance*sin

        if not InMapXY(xe, ye) then return end

        local zs = GetTerrainZ(x, y)
        local ze = GetTerrainZ(xe, ye)

        local dummy = CreateUnit(DUMMY_PLAYER, GetUnitTypeId(caster), x, y, Rad2Deg(angle))

        local effects = {}
        for i, e in ipairs(DUMMY_EFFECT) do
            table.insert(effects, addEffectTarget(e, dummy))
        end
        
        UnitAddAbility(dummy, LOCUST_ID)
        UnitAddAbility(dummy, RAVEN_ID)
        
        UnitShareVision(dummy, player, true)
        
        SetUnitX(dummy, x)
        SetUnitY(dummy, y)
        
        SetUnitColor(dummy, GetPlayerColor(player))
        SetUnitVertexColor(dummy, 255, 255, 255, 150)
        
        SetUnitAnimation(dummy, DUMMY_ANIMATION_NAME)
        SetUnitTimeScalePercent(dummy, DUMMY_ANIMATION_DURATION/(distance/DUMMY_SPEED)*100)

        TimerStart(CreateTimer(), DUMMY_TIMER_PERIOD, true, function()
            x = x + SPEED_INC*cos
            y = y + SPEED_INC*sin
            dist = dist - SPEED_INC

            local z = Parabola(zs, ze, distance * DUMMY_ARC, distance, distance - (distance-dist))
            if 
                dist < 0
                or
                z <= GetTerrainZ(x, y)
            then
                for i, e in ipairs(effects)
                do
                    DestroyEffect(e)
                end

                DestroyEffect(AddSpecialEffect(DUMMY_EXPLODE_EFFECT, x, y))

                local damage = CASTER_DAMAGE_PERIOD/(1/BlzGetUnitBaseDamage(caster, 1) + BlzGetUnitDiceNumber(caster, 1)*BlzGetUnitDiceSides(caster, 1))
                local group = CreateGroup()
                GroupEnumUnitsInRange(group, x, y, DUMMY_EXPLODE_RANGE, Filter(function()
                    local target = GetFilterUnit()
                    return  UnitAlive(target)
                            and
                            IsPlayerEnemy(GetOwningPlayer(caster), GetOwningPlayer(target))
                            and
                            not IsUnitType(target, UNIT_TYPE_MAGIC_IMMUNE)
                            and
                            not IsUnitType(target, UNIT_TYPE_FLYING)
                end))
                ForGroup(group, function()
                    UnitDamageTarget(caster, GetEnumUnit(), damage, false, true, ATTACK_TYPE_MAGIC, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
                end)
                DestroyGroup(group)

                RemoveUnit(dummy)
                DestroyTimer(GetExpiredTimer())
                return
            end
        
            SetUnitX(dummy, x)
            SetUnitY(dummy, y)
            SetUnitZ(dummy, z, 0)
        end)
    end
    

    local trigger = CreateTrigger()
    for i = 0, bj_MAX_PLAYER_SLOTS - 1, 1 do
        TriggerRegisterPlayerUnitEvent(trigger, Player(i), EVENT_PLAYER_UNIT_SPELL_EFFECT)
    end
    TriggerAddCondition(trigger, Condition(function() return GetSpellAbilityId() == ABILITY_ID end))
    TriggerAddAction(trigger, function()
        local caster = GetTriggerUnit()
        local x = GetUnitX(caster)
        local y = GetUnitY(caster)
        IS_CHANNEL[GetHandleId(caster)] = true

        local damage = CASTER_DAMAGE_PERIOD/(1/BlzGetUnitBaseDamage(caster, 1) + BlzGetUnitDiceNumber(caster, 1)*BlzGetUnitDiceSides(caster, 1))

        TimerStart(CreateTimer(), CASTER_DAMAGE_PERIOD, true, function()
            if 
                not UnitAlive(caster)
                or
                not IS_CHANNEL[GetHandleId(caster)]
            then
                DestroyTimer(GetExpiredTimer())
                return
            end

            local group = CreateGroup()
            GroupEnumUnitsInRange(group, x, y, DUMMY_SPAWN_MIN_DISTANCE, Filter(function()
                local target = GetFilterUnit()
                return  UnitAlive(target)
                        and
                        IsPlayerEnemy(GetOwningPlayer(caster), GetOwningPlayer(target))
                        and
                        not IsUnitType(target, UNIT_TYPE_MAGIC_IMMUNE)
                        and
                        not IsUnitType(target, UNIT_TYPE_FLYING)
            end))
            ForGroup(group, function()
                UnitDamageTarget(caster, GetEnumUnit(), damage, false, true, ATTACK_TYPE_MAGIC, DAMAGE_TYPE_NORMAL, WEAPON_TYPE_WHOKNOWS)
            end)
            DestroyGroup(group)

            jump(
                caster,
                x,
                y,
                
                    math.random(DUMMY_SPAWN_MIN_DISTANCE, DUMMY_SPAWN_MAX_DISTANCE),Deg2Rad(math.random(0, 360))
            )
        end)
    end)

    trigger = CreateTrigger()
    for i = 0, bj_MAX_PLAYER_SLOTS - 1, 1 do
        TriggerRegisterPlayerUnitEvent(trigger, Player(i), EVENT_PLAYER_UNIT_SPELL_ENDCAST)
    end
    TriggerAddCondition(trigger, Condition(function() return GetSpellAbilityId() == ABILITY_ID end))
    TriggerAddAction(trigger, function()
        local key = GetHandleId(GetTriggerUnit())
        if (IS_CHANNEL[key] ~= nil)
        then
            IS_CHANNEL[key] = false
        end
    end)
end
function CreateUnitsForPlayer0()
local p = Player(0)
local u
local unitID
local t
local life

gg_unit_Obla_0000 = BlzCreateUnitWithSkin(p, FourCC("Obla"), 92.6, 353.6, 276.826, FourCC("Obla"))
SetHeroLevel(gg_unit_Obla_0000, 10, false)
SelectHeroSkill(gg_unit_Obla_0000, FourCC("SIWh"))
IssueImmediateOrder(gg_unit_Obla_0000, "")
end

function CreatePlayerBuildings()
end

function CreatePlayerUnits()
CreateUnitsForPlayer0()
end

function CreateAllUnits()
CreatePlayerBuildings()
CreatePlayerUnits()
end

function Trig_Start_Actions()
SelectUnitSingle(gg_unit_Obla_0000)
PanCameraToTimedLocForPlayer(Player(0), GetUnitLoc(gg_unit_Obla_0000), 0)
end

function InitTrig_Start()
gg_trg_Start = CreateTrigger()
TriggerAddAction(gg_trg_Start, Trig_Start_Actions)
end

function InitCustomTriggers()
InitTrig_Start()
end

function RunInitializationTriggers()
ConditionalTriggerExecute(gg_trg_Start)
end

function InitCustomPlayerSlots()
SetPlayerStartLocation(Player(0), 0)
SetPlayerColor(Player(0), ConvertPlayerColor(0))
SetPlayerRacePreference(Player(0), RACE_PREF_ORC)
SetPlayerRaceSelectable(Player(0), false)
SetPlayerController(Player(0), MAP_CONTROL_USER)
end

function InitCustomTeams()
SetPlayerTeam(Player(0), 0)
end

function main()
SetCameraBounds(-2048.0 + GetCameraMargin(CAMERA_MARGIN_LEFT), -1536.0 + GetCameraMargin(CAMERA_MARGIN_BOTTOM), 2048.0 - GetCameraMargin(CAMERA_MARGIN_RIGHT), 2560.0 - GetCameraMargin(CAMERA_MARGIN_TOP), -2048.0 + GetCameraMargin(CAMERA_MARGIN_LEFT), 2560.0 - GetCameraMargin(CAMERA_MARGIN_TOP), 2048.0 - GetCameraMargin(CAMERA_MARGIN_RIGHT), -1536.0 + GetCameraMargin(CAMERA_MARGIN_BOTTOM))
SetDayNightModels("Environment\\DNC\\DNCAshenvale\\DNCAshenvaleTerrain\\DNCAshenvaleTerrain.mdl", "Environment\\DNC\\DNCAshenvale\\DNCAshenvaleUnit\\DNCAshenvaleUnit.mdl")
NewSoundEnvironment("Default")
SetAmbientDaySound("AshenvaleDay")
SetAmbientNightSound("AshenvaleNight")
SetMapMusic("Music", true, 0)
CreateAllUnits()
InitBlizzard()
InitGlobals()
InitCustomTriggers()
RunInitializationTriggers()
end

function config()
SetMapName("TRIGSTR_003")
SetMapDescription("")
SetPlayers(1)
SetTeams(1)
SetGamePlacement(MAP_PLACEMENT_USE_MAP_SETTINGS)
DefineStartLocation(0, 128.0, 320.0)
InitCustomPlayerSlots()
InitCustomTeams()
end

