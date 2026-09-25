-- ============================================================
-- FS25_VeterinarianAnimalProfile.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.1.0.0
-- Tierprodukte werden aus der geladenen Karte ermittelt, einschließlich Hof Bergmann.
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianAnimalProfile = {}
local P = VeterinarianAnimalProfile

function P.name(subType)
    return string.upper(tostring(subType and (subType.subTypeName or subType.name) or ""))
end

function P.kind(subType)
    local name = P.name(subType)
    if name:find("GOAT", 1, true) then return "GOAT" end
    local system = g_currentMission and g_currentMission.animalSystem
    local animalType = system and system.getTypeByIndex and subType and subType.typeIndex
        and system:getTypeByIndex(subType.typeIndex)
    return animalType and string.upper(animalType.name or "") or name:match("^([^_]+)")
end

function P.fillName(output)
    if output == nil then return "" end
    if type(output.fillType) == "string" then return string.upper(output.fillType) end
    local manager = g_fillTypeManager
    local fillType = manager and manager.getFillTypeByIndex and output.fillType
        and manager:getFillTypeByIndex(output.fillType)
    return string.upper(tostring(fillType and fillType.name or ""))
end

function P.isMilk(output)
    local name = P.fillName(output)
    return name:find("MILK", 1, true) ~= nil and name:find("SPERM", 1, true) == nil
end

function P.product(subType)
    if subType == nil then return nil end
    local kind, name = P.kind(subType), P.name(subType)
    if kind == "HORSE" or kind == "CAT" or kind == "DOG" then return nil end
    local output = subType.output or {}
    local milk, pallets = output.milk, output.pallets
    local milkName, palletName = P.fillName(milk), P.fillName(pallets)
    if milkName:find("SPERM", 1, true) then
        return {icon="semen", label="vet_cardSemenProduction", output=milk, minAge=12}
    end
    if P.isMilk(milk) or (milk ~= nil and milkName == "" and (kind == "COW" or kind == "GOAT")) then
        return {icon="milk", label="vet_cardMilkProduction", output=milk,
            minAge=kind == "GOAT" and 16 or (kind == "MILKCOW" and 12 or 18),
            lactation=kind ~= "MILKCOW" and subType.supportsReproduction ~= false
                and not (subType.reproduction and subType.reproduction.supported == false)}
    end
    if P.isMilk(pallets) then
        return {icon="milk", label="vet_cardMilkProduction", output=pallets, minAge=16}
    end
    if palletName:find("EGG", 1, true) or kind == "CHICKEN" or kind == "ROOSTER"
        or kind == "DUCKWILD" or kind == "DUCK" or kind == "GOOSE" or kind == "QUAIL" then
        return {icon="eggs", label="vet_cardEggProduction", output=pallets, minAge=6,
            male=name:find("ROOSTER", 1, true) ~= nil}
    end
    if palletName:find("WOOL", 1, true) or kind == "SHEEP" or kind == "ALPACA" then
        return {icon="wool", label="vet_cardWoolProduction", output=pallets, minAge=8,
            sheared=name:find("SHEARED", 1, true) ~= nil}
    end
    if kind == "GOAT" then
        return {icon="milk", label="vet_cardMilkProduction", minAge=16, lactation=true}
    end
    if kind == "PIG" or kind == "COW" or kind == "RABBIT" or kind == "DEER" then
        return {icon="meat", label="vet_cardMeatProduction", readiness=true,
            minAge=kind == "COW" and 18 or (kind == "DEER" and 18 or (kind == "RABBIT" and 8 or 6))}
    end
    return nil
end

function P.productionAge(subType, profile)
    local reproduction = subType.reproduction or {}
    local age
    if subType.supportsReproduction ~= false and reproduction.supported ~= false then
        age = reproduction.minAgeMonth or reproduction.minAge or subType.reproductionMinAgeMonth
    end
    return type(age) == "number" and age > 0 and age < math.huge and age or profile.minAge
end

function P.nativeReproduction(subType)
    local kind, name = P.kind(subType), P.name(subType)
    return kind == "CHICKEN" or kind == "ROOSTER" or kind == "DUCK" or kind == "DUCKWILD"
        or kind == "GOOSE" or kind == "QUAIL" or kind == "DEER"
        or name:find("SHEARED", 1, true) ~= nil
end

function P.supportsMilk(husbandry)
    local system = g_currentMission and g_currentMission.animalSystem
    local spec = husbandry and husbandry.spec_husbandryAnimals
    if system == nil or spec == nil then return false end
    local animalType = spec.animalType or (system.getTypeByIndex and system:getTypeByIndex(spec.animalTypeIndex))
    for _, index in ipairs(animalType and animalType.subTypes or {}) do
        local allowed = spec.subtypeFilterAllowedSubTypes == nil or spec.subtypeFilterAllowedSubTypes[index] == true
        if husbandry.getSupportsAnimalSubType then allowed = allowed and husbandry:getSupportsAnimalSubType(index) end
        local subtype = system:getSubTypeByIndex(index)
        local profile = P.product(subtype)
        if allowed and profile and profile.icon == "milk" and profile.output ~= nil then
            local age = math.max(P.productionAge(subtype, profile), spec.subtypeFilterAgeMin or 0)
            local ageAllowed = spec.subtypeFilterAgeMax == nil or age <= spec.subtypeFilterAgeMax
            local visualAllowed = true
            if spec.subtypeFilterAllowedVisuals and system.getVisualByAge then
                local visual = system:getVisualByAge(index, age)
                visualAllowed = visual ~= nil and spec.subtypeFilterAllowedVisuals[visual.visualAnimalIndex] == true
            end
            if ageAllowed and visualAllowed then return true end
        end
    end
    return false
end

function P.installClusterHooks()
    local map = _G.FS25_HofBergmann
    local sheep = _G.LSFMSheepCluster or (map and map.LSFMSheepCluster)
    if sheep and not sheep.veterinarianCloneHook then
        sheep.clone = Utils.overwrittenFunction(sheep.clone, VeterinarianIdentity.clone)
        sheep.veterinarianCloneHook = true
    end
end

function P.isHofBergmann()
    if g_modIsLoaded and g_modIsLoaded.FS25_HofBergmann then return true end
    local system = g_currentMission and g_currentMission.animalSystem
    return system ~= nil and system.getSubTypeByName ~= nil
        and system:getSubTypeByName("MILK_COW") ~= nil
        and system:getSubTypeByName("BULL") ~= nil
        and system:getSubTypeByName("LSFM_SHEEP_LANDRACE_SHEARED") ~= nil
end

function P.addNewborns(husbandry, subTypeIndex, count)
    if count <= 0 then return end
    if not P.isHofBergmann() then husbandry:addAnimals(subTypeIndex, count, 0); return end
    local system = g_currentMission.animalSystem
    local mother = system:getSubTypeByIndex(subTypeIndex)
    local name = P.name(mother)
    local mixedCows = {COW_SWISS_BROWN=true, COW_HOLSTEIN=true, COW_ANGUS=true, COW_LIMOUSIN=true}
    local bull = mixedCows[name] and system:getSubTypeByName("BULL") or nil
    local males = 0
    if bull ~= nil and bull.typeIndex == mother.typeIndex then
        for _ = 1, count do if math.random() < 0.5 then males = males + 1 end end
    end
    local function add(index, number)
        if number <= 0 then return end
        local newborn = system:createClusterFromSubTypeIndex(index)
        newborn.age, newborn.numAnimals = 0, number
        husbandry.spec_husbandryAnimals.clusterSystem:addPendingAddCluster(newborn)
        local subtype = system:getSubTypeByIndex(index)
        if g_farmManager and subtype.statsBreedingName then
            g_farmManager:updateFarmStats(husbandry:getOwnerFarmId(), subtype.statsBreedingName, number)
        end
    end
    add(subTypeIndex, count - males)
    if males > 0 then add(bull.subTypeIndex, males) end
end

function P.transferShearedRecords(system)
    for _, source in ipairs(system:getClusters()) do
        local tool = source.lsfmSheepShearsProcessing
        local spec = tool and tool.spec_lsfmSheepShears
        local target = spec and spec.serverTarget
        local destination = target and target.cluster == source and target.resultCluster
        if destination and source.vetRemovedAt == g_time and source.vetRemoved
            and source.vetRemoved[1] and destination.vetAnimals == nil then
            local record = {}
            for key, value in pairs(source.vetRemoved[1]) do record[key] = value end
            destination.vetAnimals = {record}
            source.vetRemovedAt = nil
        end
    end
end
