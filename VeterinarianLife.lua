-- ============================================================
-- FS25_VeterinarianLife.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.1.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianLife = {}
VeterinarianLife.FIELDS = {"litter", "stillRate", "cooldown", "sickHours", "vaccine", "liveBirths", "lactation"}
VeterinarianLife.VACCINE_MONTHS = 12
VeterinarianLife.VACCINE_EFFECT = 0.9
VeterinarianLife.VACCINE_COST = 50
VeterinarianLife.DEATH_HOURS = 72
VeterinarianLife.LACTATION_MONTHS = 12
VeterinarianLife.RULES = {
    COW = {min=1, max=1, rateMin=10, rateMax=20, interval=12},
    PIG = {min=10, max=14, rateMin=5, rateMax=10, interval=6},
    SHEEP = {min=1, max=2, rateMin=2, rateMax=5, interval=12},
    GOAT = {min=1, max=3, rateMin=2, rateMax=5, interval=12}
}

function VeterinarianLife.ensure(state)
    state.extra = state.extra or {}
    for _, key in ipairs(VeterinarianLife.FIELDS) do state.extra[key] = state.extra[key] or {} end
    return state.extra
end

function VeterinarianLife.rule(subType)
    local name = string.upper(tostring(subType and (subType.subTypeName or subType.name) or ""))
    if VeterinarianAnimalProfile.nativeReproduction(subType) then return nil, true end
    for kind, rule in pairs(VeterinarianLife.RULES) do
        if name:sub(1, #kind) == kind then return rule, false end
    end
    return {min=1, max=1, rateMin=0, rateMax=0, interval=0}, false
end

function VeterinarianLife.start(state, index, subType)
    local extra = VeterinarianLife.ensure(state)
    local rule = VeterinarianLife.rule(subType)
    if rule == nil then return end
    extra.litter[index] = math.random(rule.min, rule.max)
    extra.stillRate[index] = math.random(rule.rateMin, rule.rateMax)
    extra.cooldown[index] = rule.interval
    extra.liveBirths[index] = nil
end

function VeterinarianLife.expected(state, index, subType)
    local extra = VeterinarianLife.ensure(state)
    local rule, chicken = VeterinarianLife.rule(subType)
    if chicken then return "" end
    local count = extra.litter[index]
    local text = count ~= nil and tostring(count) or (rule.min == rule.max and tostring(rule.min) or string.format("%d–%d", rule.min, rule.max))
    return string.format(g_i18n:getText("vet_expectedYoung"), text)
end

function VeterinarianLife.authorized(placeable, connection)
    if g_currentMission == nil or placeable == nil or placeable.getOwnerFarmId == nil then return false end
    if connection == nil then return g_client ~= nil and g_currentMission:getFarmId() == placeable:getOwnerFarmId() end
    if connection:getIsServer() then return false end
    local id = g_currentMission.userManager:getUserIdByConnection(connection)
    local farm = id ~= nil and g_farmManager:getFarmByUserId(id) or nil
    return farm ~= nil and farm.farmId == placeable:getOwnerFarmId()
end

function VeterinarianLife.vaccinate(placeable, index, connection, animalId)
    index = VeterinarianIdentity.resolve(placeable, index, animalId)
    if index == nil then return end
    if g_server == nil or placeable == nil or placeable.spec_husbandryAnimals == nil
            or not VeterinarianLife.authorized(placeable, connection) then return end
    if index < 1 or index > placeable:getNumOfAnimals() then return end
    local state = g_veterinarian:getOrCreateState(placeable)
    local extra = VeterinarianLife.ensure(state)
    if state.sickAnimals[index] or (extra.vaccine[index] or 0) > 0 then return end
    local farmId = placeable:getOwnerFarmId()
    local cost = Veterinarian.CALL_OUT_FEE + VeterinarianLife.VACCINE_COST
    local farm = g_farmManager:getFarmById(farmId)
    if farm == nil or farm.money < cost then
        if connection ~= nil then VeterinarianResultEvent.sendEvent(false, 0, cost, connection)
        else g_veterinarian:showTreatmentResult(false, 0, cost) end
        return
    end
    extra.vaccine[index] = VeterinarianLife.VACCINE_MONTHS
    g_currentMission:addMoney(-cost, farmId, MoneyType.ANIMAL_UPKEEP or MoneyType.OTHER, true, true)
    g_veterinarian:broadcastState(placeable, state)
end

function VeterinarianLife.snapshot(placeable, state)
    local snapshot = {}
    local index = 1
    for _, cluster in ipairs(placeable:getClusters()) do
        local animals = {}
        snapshot[cluster] = animals
        for offset = 1, cluster:getNumAnimals() do
            local animal = {}
            for _, field in ipairs({"animalNames", "sickAnimals", "inseminatedAnimals", "inseminatedSubTypes"}) do
                animal[field] = state[field][index]
            end
            for _, field in ipairs(VeterinarianLife.FIELDS) do animal[field] = state.extra[field][index] end
            animals[offset] = animal
            index = index + 1
        end
    end
    return snapshot
end

function VeterinarianLife.restore(placeable, state, snapshot)
    for _, field in ipairs({"animalNames", "sickAnimals", "inseminatedAnimals", "inseminatedSubTypes"}) do state[field] = {} end
    for _, field in ipairs(VeterinarianLife.FIELDS) do state.extra[field] = {} end
    local index = 1
    for _, cluster in ipairs(placeable:getClusters()) do
        for offset = 1, cluster:getNumAnimals() do
            local animal = (snapshot[cluster] or {})[offset] or {}
            for _, field in ipairs({"animalNames", "sickAnimals", "inseminatedAnimals", "inseminatedSubTypes"}) do
                state[field][index] = animal[field]
            end
            for _, field in ipairs(VeterinarianLife.FIELDS) do state.extra[field][index] = animal[field] end
            state.animalNames[index] = state.animalNames[index] or g_veterinarian:allocateAnimalName()
            index = index + 1
        end
    end
end

function VeterinarianLife.month(state)
    local extra = VeterinarianLife.ensure(state)
    for _, key in ipairs({"vaccine", "cooldown", "lactation"}) do
        for index, value in pairs(extra[key]) do extra[key][index] = math.max(0, value - 1) end
    end
end

function VeterinarianLife.remove(placeable, state, index)
    local first = 1
    for _, cluster in ipairs(placeable:getClusters()) do
        local count = cluster:getNumAnimals()
        if index >= first and index < first + count then
            local system = placeable.spec_husbandryAnimals.clusterSystem
            if cluster.changeNumAnimals == nil or system == nil or system.updateNow == nil then return false end
            VeterinarianIdentity.commit(placeable, state)
            table.remove(cluster.vetAnimals, index - first + 1)
            cluster.vetExactRemoval = true
            local total = placeable:getNumOfAnimals()
            local tables = {state.animalNames, state.sickAnimals, state.inseminatedAnimals, state.inseminatedSubTypes}
            for _, field in ipairs(VeterinarianLife.FIELDS) do table.insert(tables, state.extra[field]) end
            for _, values in ipairs(tables) do
                for i = index, total - 1 do values[i] = values[i + 1] end
                values[total] = nil
            end
            state.vetLayout = nil
            cluster:changeNumAnimals(-1)
            cluster.vetExactRemoval = nil
            state.vetLayout = nil
            system:updateNow()
            VeterinarianIdentity.reconcile(placeable, state)
            return true
        end
        first = first + count
    end
    return false
end

function VeterinarianLife.hour(placeable, state)
    local extra = VeterinarianLife.ensure(state)
    local deaths = {}
    for index in pairs(state.sickAnimals) do
        extra.sickHours[index] = (extra.sickHours[index] or 0) + 1
        if extra.sickHours[index] >= VeterinarianLife.DEATH_HOURS then table.insert(deaths, index) end
    end
    table.sort(deaths, function(a,b) return a > b end)
    for _, index in ipairs(deaths) do
        local name = state.animalNames[index]
        if VeterinarianLife.remove(placeable, state, index) then
            VeterinarianNotificationEvent.send(placeable, true, "vet_animalDied", name)
        end
    end
end

function VeterinarianLife.startLactation(state, index, subType)
    local profile = VeterinarianAnimalProfile.product(subType)
    if profile ~= nil and profile.lactation then
        VeterinarianLife.ensure(state).lactation[index] = VeterinarianLife.LACTATION_MONTHS
    end
end

function VeterinarianLife.updateMilkProduction(placeable, clusters)
    if placeable == nil or placeable.spec_husbandryMilk == nil or g_veterinarian == nil then return end
    local state = g_veterinarian:getOrCreateState(placeable)
    if state == nil then return end
    local extra = VeterinarianLife.ensure(state)
    local spec = placeable.spec_husbandryMilk
    if spec.hasMilkProduction == false or spec.litersPerHour == nil then return end

    local managed = {}
    for _, cluster in ipairs(clusters or placeable:getClusters() or {}) do
        local subType = g_currentMission.animalSystem:getSubTypeByIndex(cluster.subTypeIndex)
        local profile = VeterinarianAnimalProfile.product(subType)
        local milk = subType and subType.output and subType.output.milk
        if milk and profile and profile.lactation and spec.litersPerHour[milk.fillType] ~= nil then
            managed[milk.fillType] = true
        end
    end
    for fillType in pairs(managed) do spec.litersPerHour[fillType] = 0 end
    local animalIndex = 1
    for _, cluster in ipairs(clusters or placeable:getClusters() or {}) do
        local count = math.max(0, cluster:getNumAnimals() or 0)
        local subType = g_currentMission.animalSystem:getSubTypeByIndex(cluster.subTypeIndex)
        local milk = subType and subType.output and subType.output.milk
        if milk and managed[milk.fillType] then
            local profile = VeterinarianAnimalProfile.product(subType)
            local producing = 0
            for offset = 0, count - 1 do
                if not profile.lactation or (extra.lactation[animalIndex + offset] or 0) > 0 then
                    producing = producing + 1
                end
            end
            spec.litersPerHour[milk.fillType] = spec.litersPerHour[milk.fillType]
                + (milk.curve:get(cluster:getAge()) or 0) * producing / 24
        end
        animalIndex = animalIndex + count
    end
    spec.activeFillTypes = {}
    for fillType, liters in pairs(spec.litersPerHour) do
        if liters > 0 then table.insert(spec.activeFillTypes, fillType) end
    end
end

function VeterinarianLife.vaccinationEntries(husbandry, state)
    local entries = ArtificialInsemination.getAnimalEntries(husbandry, state, true)
    local extra = VeterinarianLife.ensure(state)
    for _, entry in ipairs(entries) do
        local index = entry.index
        local months = extra.vaccine[index] or 0
        entry.canVaccinate = not state.sickAnimals[index] and months == 0
        entry.isBlocked = state.sickAnimals[index] == true
        if state.sickAnimals[index] then
            entry.status = g_i18n:getText("vet_vaccineTreatFirst")
        elseif months > 0 then
            entry.status = string.format(g_i18n:getText("vet_vaccineActive"), months)
        else
            entry.status = g_i18n:getText("vet_vaccineReady")
        end
        entry.extraInfo = g_i18n:getText("vet_vaccineEffect")
        entry.price = entry.canVaccinate and g_i18n:formatMoney(Veterinarian.CALL_OUT_FEE + VeterinarianLife.VACCINE_COST, 0, true, true) or "–"
    end
    return entries
end
