-- ============================================================
-- FS25_ArtificialInsemination.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

ArtificialInsemination = {}

ArtificialInsemination.CALL_OUT_FEE = 350
ArtificialInsemination.COST_PER_ANIMAL = 250
ArtificialInsemination.RESULT_SUCCESS = 1
ArtificialInsemination.RESULT_NO_ELIGIBLE = 2
ArtificialInsemination.RESULT_NOT_ENOUGH_MONEY = 3
ArtificialInsemination.RESULT_STABLE_FULL = 4

local originalUpdateReproduction = nil

local REPRODUCTION_DEFAULTS = {
    COW = { minAge = 18, duration = 10 },
    PIG = { minAge = 6, duration = 4 },
    SHEEP = { minAge = 8, duration = 5 },
    GOAT = { minAge = 16, duration = 5 },
    HORSE = { minAge = 22, duration = 11 },
    CHICKEN = { minAge = 6, duration = 2 }
}

local function getSubType(cluster)
    if cluster == nil or g_currentMission == nil or g_currentMission.animalSystem == nil then return nil end
    local index = cluster.subTypeIndex
    if index == nil and cluster.getSubTypeIndex ~= nil then index = cluster:getSubTypeIndex() end
    return index ~= nil and g_currentMission.animalSystem:getSubTypeByIndex(index) or nil
end

local function getSubTypeName(subType)
    return string.upper(tostring(subType ~= nil and (subType.subTypeName or subType.name) or ""))
end

local function getReproductionRule(subType)
    if subType == nil then return nil end
    if VeterinarianAnimalProfile.nativeReproduction(subType) then return nil end

    local name = getSubTypeName(subType)
    if string.find(name, "ROOSTER", 1, true) ~= nil or name:find("_MALE", 1, true) or name == "BULL" then return nil end

    local reproduction = subType ~= nil and subType.reproduction or nil
    if subType.supportsReproduction == false or (reproduction ~= nil and reproduction.supported == false) then return nil end

    local minAge = reproduction ~= nil and (reproduction.minAgeMonth or reproduction.minAge) or nil
    local duration = reproduction ~= nil and (reproduction.durationMonth or reproduction.duration) or nil

    minAge = minAge or subType.reproductionMinAgeMonth or subType.reproductionMinAge or subType.minReproductionAge
    duration = duration or subType.reproductionDurationMonth or subType.reproductionDuration

    if minAge ~= nil then
        return { minAge = minAge, duration = math.max(1, duration or 1) }
    end

    for animalType, rule in pairs(REPRODUCTION_DEFAULTS) do
        if string.sub(name, 1, #animalType) == animalType then return rule end
    end

    return nil
end

local function getDuration(subTypeIndex)
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    local subType = system ~= nil and system:getSubTypeByIndex(subTypeIndex) or nil
    local rule = getReproductionRule(subType)
    return rule ~= nil and rule.duration or 1
end

function ArtificialInsemination.getRemainingPregnancyMonths(state, animalIndex, fallbackSubTypeIndex)
    if state == nil or animalIndex == nil or state.inseminatedAnimals == nil then return nil end
    local progress = state.inseminatedAnimals[animalIndex]
    if progress == nil then return nil end
    local subTypeIndex = state.inseminatedSubTypes ~= nil and state.inseminatedSubTypes[animalIndex] or nil
    subTypeIndex = subTypeIndex or fallbackSubTypeIndex
    return math.max(0, getDuration(subTypeIndex) - (progress or 0))
end

local function canInseminateCluster(cluster)
    local subType = getSubType(cluster)
    local rule = getReproductionRule(subType)
    local _, chicken = VeterinarianLife.rule(subType)
    if rule == nil or chicken then return false end
    local age = cluster.getAge ~= nil and cluster:getAge() or cluster.age or 0
    return age >= rule.minAge
end

function ArtificialInsemination.getAnimalDetails(cluster)
    local subType = getSubType(cluster)
    local rawName = getSubTypeName(subType)
    local breeds = {
        {"BROWN", "Brown_Swiss"}, {"HOLSTEIN", "Holstein"},
        {"ANGUS", "Angus"}, {"LIMOUSIN", "Limousin"},
        {"BUFFALO", g_i18n:getText("vet_waterBuffalo")}
    }
    local breed
    for _, item in ipairs(breeds) do
        if rawName:find(item[1], 1, true) then breed = item[2]; break end
    end
    if breed == nil then
        local store = subType ~= nil and subType.storeInfo or nil
        breed = store ~= nil and store.shopItemName or nil
        if breed == nil or breed == "" then
            breed = rawName:gsub("^[A-Z]+_", ""):gsub("_", " ")
        end
        if breed == "" then breed = g_i18n:getText("vet_unknown") end
    end
    local age = cluster ~= nil and (cluster.getAge ~= nil and cluster:getAge() or cluster.age) or nil
    local ageText = age ~= nil and tostring(math.floor(math.max(0, age))) or g_i18n:getText("vet_unknown")
    local rule = getReproductionRule(subType)
    local maturity = g_i18n:getText("vet_unknown")
    if rule ~= nil and age ~= nil then
        maturity = g_i18n:getText(age >= rule.minAge and "vet_yes" or "vet_no")
    elseif subType ~= nil and rule == nil then
        maturity = g_i18n:getText("vet_no")
    end
    return string.format(g_i18n:getText("vet_breedAge"), breed, ageText),
        string.format(g_i18n:getText("vet_maturity"), maturity)
end

local function findAnimal(husbandry, wantedIndex)
    local animalIndex = 1
    for _, cluster in ipairs(husbandry ~= nil and husbandry:getClusters() or {}) do
        local count = math.max(0, cluster:getNumAnimals() or 0)
        if wantedIndex >= animalIndex and wantedIndex < animalIndex + count then return cluster end
        animalIndex = animalIndex + count
    end
    return nil
end

function ArtificialInsemination.install()
    if ArtificialInsemination.installed then return true end
    if AnimalCluster == nil or AnimalCluster.updateReproduction == nil then
        Logging.warning("[Veterinarian] Could not install automatic reproduction block")
        return false
    end
    VeterinarianAnimalProfile.installClusterHooks()
    originalUpdateReproduction = AnimalCluster.updateReproduction
    AnimalCluster.updateReproduction = function(cluster, ...)
        local _, chicken = VeterinarianLife.rule(getSubType(cluster))
        if chicken or getReproductionRule(getSubType(cluster)) == nil or (cluster.reproduction or 0) > 0 then return originalUpdateReproduction(cluster, ...) end
        return 0
    end

    if PlaceableHusbandryAnimals ~= nil and PlaceableHusbandryAnimals.onPeriodChanged ~= nil then
        PlaceableHusbandryAnimals.onPeriodChanged = Utils.appendedFunction(
            PlaceableHusbandryAnimals.onPeriodChanged,
            ArtificialInsemination.onHusbandryPeriodChanged)
    else
        Logging.warning("[Veterinarian] Could not install artificial insemination period hook")
    end

    if PlaceableHusbandryMilk ~= nil and PlaceableHusbandryMilk.onHusbandryAnimalsUpdate ~= nil then
        PlaceableHusbandryMilk.onHusbandryAnimalsUpdate = Utils.appendedFunction(
            PlaceableHusbandryMilk.onHusbandryAnimalsUpdate,
            VeterinarianLife.updateMilkProduction)
    else
        Logging.warning("[Veterinarian] Could not install birth-dependent lactation hook")
    end

    ArtificialInsemination.installed = true
    return true
end

function ArtificialInsemination.getAnimalEntries(husbandry, state, includeChickens)
    local entries = {}
    if husbandry == nil or state == nil then return entries end
    local animalSystem = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    local extra = VeterinarianLife.ensure(state)
    local animalIndex = 1
    for _, cluster in ipairs(husbandry:getClusters()) do
        local count = math.max(0, cluster:getNumAnimals() or 0)
        local subTypeIndex = cluster.subTypeIndex
        if subTypeIndex == nil and cluster.getSubTypeIndex ~= nil then subTypeIndex = cluster:getSubTypeIndex() end
        local subType = animalSystem ~= nil and animalSystem:getSubTypeByIndex(subTypeIndex) or nil
        local details, maturity = ArtificialInsemination.getAnimalDetails(cluster)
        local _, chicken = VeterinarianLife.rule(subType)
        for _ = 1, count do
            local progress = state.inseminatedAnimals[animalIndex]
            local eligible = canInseminateCluster(cluster) and progress == nil and (extra.cooldown[animalIndex] or 0) == 0
            local status
            local blocked = false
            if progress ~= nil then
                local duration = getDuration(state.inseminatedSubTypes[animalIndex] or subTypeIndex)
                local remaining = math.max(0, duration - progress)
                if remaining == 0 then
                    status = g_i18n:getText("vet_inseminationBirthWaiting")
                elseif remaining == 1 then
                    status = g_i18n:getText("vet_inseminationRemainingOne")
                else
                    status = string.format(g_i18n:getText("vet_inseminationRemaining"), remaining)
                end
            elseif (extra.cooldown[animalIndex] or 0) > 0 then
                status = string.format(g_i18n:getText("vet_breedingWait"), extra.cooldown[animalIndex])
                blocked = true
            elseif eligible then
                status = g_i18n:getText("vet_inseminationReady")
            else
                status = g_i18n:getText("vet_inseminationNotEligible")
                blocked = true
            end
            if not chicken or includeChickens then table.insert(entries, {
                index = animalIndex,
                title = state.animalNames[animalIndex] or g_i18n:getText("vet_defaultAnimal"),
                details = details,
                maturity = maturity,
                extraInfo = VeterinarianLife.expected(state, animalIndex, subType),
                status = status,
                price = eligible and g_i18n:formatMoney(ArtificialInsemination.CALL_OUT_FEE + ArtificialInsemination.COST_PER_ANIMAL, 0, true, true) or "–",
                canInseminate = eligible,
                isBlocked = blocked
            }) end
            animalIndex = animalIndex + 1
        end
    end
    return entries
end

function ArtificialInsemination.perform(husbandry, animalIndex, connection, animalId)
    animalIndex = VeterinarianIdentity.resolve(husbandry, animalIndex, animalId)
    if animalIndex == nil then return end
    if g_server == nil or husbandry == nil or husbandry.spec_husbandryAnimals == nil then return end
    local farmId = husbandry:getOwnerFarmId()
    if not VeterinarianLife.authorized(husbandry, connection) then return end
    local cluster = findAnimal(husbandry, animalIndex)
    local state = g_veterinarian ~= nil and g_veterinarian:getOrCreateState(husbandry) or nil
    if cluster == nil or state == nil or not canInseminateCluster(cluster)
            or state.inseminatedAnimals[animalIndex] ~= nil
            or (VeterinarianLife.ensure(state).cooldown[animalIndex] or 0) > 0 then
        ArtificialInseminationResultEvent.sendEvent(ArtificialInsemination.RESULT_NO_ELIGIBLE, 0, 0, connection)
        return
    end
    local cost = ArtificialInsemination.CALL_OUT_FEE + ArtificialInsemination.COST_PER_ANIMAL
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm.money < cost then
        ArtificialInseminationResultEvent.sendEvent(ArtificialInsemination.RESULT_NOT_ENOUGH_MONEY, 1, cost, connection)
        return
    end
    VeterinarianLife.start(state, animalIndex, getSubType(cluster))
    state.inseminatedAnimals[animalIndex] = 0
    state.inseminatedSubTypes[animalIndex] = cluster:getSubTypeIndex()
    g_currentMission:addMoney(-cost, farmId, MoneyType.ANIMAL_UPKEEP or MoneyType.OTHER, true, true)
    g_veterinarian:broadcastState(husbandry, state)
    ArtificialInseminationResultEvent.sendEvent(ArtificialInsemination.RESULT_SUCCESS, 1, cost, connection)
end

function ArtificialInsemination.request(husbandry, animalIndex, animalId)
    if g_server ~= nil then
        ArtificialInsemination.perform(husbandry, animalIndex, nil, animalId)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(ArtificialInseminationEvent.new(husbandry, animalIndex, animalId))
    end
end

function ArtificialInsemination.onHusbandryPeriodChanged(husbandry)
    if g_server == nil or g_veterinarian == nil or husbandry == nil
            or husbandry.spec_husbandryAnimals == nil then return end

    local state = g_veterinarian:getOrCreateState(husbandry)
    if state == nil then return end

    VeterinarianLife.month(state)
    local extra = VeterinarianLife.ensure(state)
    local births = {}
    local reserved = 0
    for animalIndex, progress in pairs(state.inseminatedAnimals) do
        local subTypeIndex = state.inseminatedSubTypes[animalIndex]
        local subType = g_currentMission.animalSystem:getSubTypeByIndex(subTypeIndex)
        local _, chicken = VeterinarianLife.rule(subType)
        if chicken then
            state.inseminatedAnimals[animalIndex] = nil
            state.inseminatedSubTypes[animalIndex] = nil
            extra.litter[animalIndex] = nil
            extra.stillRate[animalIndex] = nil
            extra.liveBirths[animalIndex] = nil
            extra.cooldown[animalIndex] = nil
        else
            if extra.litter[animalIndex] == nil then
                VeterinarianLife.start(state, animalIndex, subType)
                extra.cooldown[animalIndex] = math.max(0, extra.cooldown[animalIndex] - (progress or 0) - 1)
            end
            local duration = getDuration(subTypeIndex)
            local nextProgress = math.min(duration, (progress or 0) + 1)
            state.inseminatedAnimals[animalIndex] = nextProgress
            if nextProgress >= duration then
                if extra.liveBirths[animalIndex] == nil then
                    local alive = 0
                    for _ = 1, extra.litter[animalIndex] do
                        if math.random() >= extra.stillRate[animalIndex] / 100 then alive = alive + 1 end
                    end
                    extra.liveBirths[animalIndex] = alive
                end
                local alive = extra.liveBirths[animalIndex]
                local free = math.max(0, husbandry:getNumOfFreeAnimalSlots() - reserved)
                local kept = math.min(alive, free)
                local sold = math.max(0, alive - kept)
                if kept > 0 then table.insert(births, {subTypeIndex, kept}); reserved = reserved + kept end

                VeterinarianLife.startLactation(state, animalIndex, subType)

                if sold > 0 then
                    local salePrice = 0
                    local saleCluster = g_currentMission.animalSystem:createClusterFromSubTypeIndex(subTypeIndex)
                    if saleCluster ~= nil then
                        saleCluster.age = 0
                        if saleCluster.getSellPrice ~= nil then salePrice = math.max(0, saleCluster:getSellPrice() or 0) * sold end
                    end
                    if salePrice > 0 then
                        g_currentMission:addMoney(salePrice, husbandry:getOwnerFarmId(), MoneyType.SOLD_ANIMALS, true, true)
                    end
                    VeterinarianNotificationEvent.send(husbandry, false, "vet_birthAutoSold", sold, salePrice)
                end

                VeterinarianNotificationEvent.send(husbandry, false, "vet_birthResult", state.animalNames[animalIndex], alive, extra.litter[animalIndex] - alive)
                state.inseminatedAnimals[animalIndex] = nil
                state.inseminatedSubTypes[animalIndex] = nil
                extra.litter[animalIndex] = nil
                extra.stillRate[animalIndex] = nil
                extra.liveBirths[animalIndex] = nil
            end
        end
    end
    VeterinarianIdentity.commit(husbandry, state)
    for _, birth in ipairs(births) do VeterinarianAnimalProfile.addNewborns(husbandry, birth[1], birth[2]) end
    if #births > 0 then
        husbandry.spec_husbandryAnimals.clusterSystem:updateNow()
        VeterinarianIdentity.reconcile(husbandry, state)
    end
    g_veterinarian:getOrCreateState(husbandry)
    VeterinarianLife.updateMilkProduction(husbandry, husbandry:getClusters())
    g_veterinarian:broadcastState(husbandry, state)
end

function ArtificialInsemination.periodChanged()
    if g_server == nil or g_veterinarian == nil then return end
    for _, husbandry in ipairs(g_veterinarian:getHusbandries()) do
        ArtificialInsemination.onHusbandryPeriodChanged(husbandry)
    end
end

function ArtificialInsemination.showResult(result, count, cost)
    local kind = FSBaseMission.INGAME_NOTIFICATION_INFO
    local message
    if result == ArtificialInsemination.RESULT_SUCCESS then
        message = string.format(g_i18n:getText("vet_inseminationSuccess"), count, g_i18n:formatMoney(cost, 0, true, true))
    elseif result == ArtificialInsemination.RESULT_NOT_ENOUGH_MONEY then
        kind = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        message = string.format(g_i18n:getText("vet_inseminationNoMoney"), g_i18n:formatMoney(cost, 0, true, true))
    else
        kind = FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        message = g_i18n:getText("vet_inseminationNoEligible")
    end
    if g_currentMission ~= nil then g_currentMission:addIngameNotification(kind, message) end
end
