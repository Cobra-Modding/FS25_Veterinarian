-- ============================================================
-- FS25_VeterinarianIdentity.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianIdentity = {}
local V = VeterinarianIdentity
V.FIELDS = {"animalIds", "animalNames", "sickAnimals", "inseminatedAnimals", "inseminatedSubTypes"}

function V.reset()
    V.busy = false
    V.nextId = 0
    V.session = tostring(getDate("%Y%m%d%H%M%S")) .. "-" .. tostring(math.random(1, 1073741823))
end

local function copy(record)
    local result = {}
    for key, value in pairs(record or {}) do result[key] = value end
    return result
end

local function count(cluster)
    return math.max(0, cluster:getNumAnimals() or 0)
end

local function signature(cluster)
    return tostring(cluster:getSubTypeIndex()) .. ":" .. tostring(cluster:getAge())
end

local function readRecord(state, index)
    local record = {}
    for _, field in ipairs(V.FIELDS) do record[field] = (state[field] or {})[index] end
    for _, field in ipairs(VeterinarianLife.FIELDS) do record[field] = state.extra[field][index] end
    return record
end

function V.matches(placeable, state)
    local layout = state.vetLayout
    local clusters = placeable:getClusters()
    if layout == nil or #layout ~= #clusters then return false end
    for i, entry in ipairs(layout) do
        if entry.cluster ~= clusters[i] or entry.count ~= count(clusters[i]) then return false end
    end
    return true
end

function V.commit(placeable, state)
    if g_server == nil or state == nil or not V.matches(placeable, state) then return end
    VeterinarianLife.ensure(state)
    for _, entry in ipairs(state.vetLayout) do
        local records = {}
        for offset = 1, entry.count do records[offset] = readRecord(state, entry.start + offset - 1) end
        entry.cluster.vetAnimals = records
        entry.cluster.vetOwner = placeable
        entry.cluster.vetState = state
    end
end

local function flush(cluster)
    if cluster.vetOwner ~= nil and cluster.vetState ~= nil then
        V.commit(cluster.vetOwner, cluster.vetState)
    end
end

function V.reconcile(placeable, state)
    if g_server == nil then return end
    VeterinarianLife.ensure(state)
    if V.matches(placeable, state) then return end
    local clusters = placeable:getClusters()
    local legacy = not state.vetInitialized
    for _, cluster in ipairs(clusters) do
        if cluster.vetAnimals ~= nil then legacy = false; break end
    end
    local index = 1
    if legacy then
        for _, cluster in ipairs(clusters) do
            cluster.vetAnimals = {}
            for offset = 1, count(cluster) do
                cluster.vetAnimals[offset] = readRecord(state, index)
                index = index + 1
            end
        end
    end
    for _, field in ipairs(V.FIELDS) do state[field] = {} end
    for _, field in ipairs(VeterinarianLife.FIELDS) do state.extra[field] = {} end
    state.vetLayout, state.sick = {}, 0
    index = 1
    for _, cluster in ipairs(clusters) do
        local records = cluster.vetAnimals or {}
        cluster.vetAnimals, cluster.vetOwner, cluster.vetState = records, placeable, state
        table.insert(state.vetLayout, {cluster=cluster, count=count(cluster), start=index})
        for offset = 1, count(cluster) do
            local record = records[offset] or {}
            if record.animalIds == nil then
                V.nextId = (V.nextId or 0) + 1
                record.animalIds = (V.session or "vet") .. "-" .. tostring(V.nextId)
            end
            record.animalNames = record.animalNames or g_veterinarian:allocateAnimalName()
            records[offset] = record
            for _, field in ipairs(V.FIELDS) do state[field][index] = record[field] end
            for _, field in ipairs(VeterinarianLife.FIELDS) do state.extra[field][index] = record[field] end
            if record.sickAnimals then state.sick = state.sick + 1 end
            index = index + 1
        end
    end
    state.vetInitialized = true
end

function V.changeNumAnimals(cluster, superFunc, delta, ...)
    if g_server == nil then return superFunc(cluster, delta, ...) end
    flush(cluster)
    local before = count(cluster)
    local result = superFunc(cluster, delta, ...)
    local after = count(cluster)
    if cluster.vetAnimals ~= nil or cluster.vetCloneRecords ~= nil then
        local records = cluster.vetAnimals or {}
        if not cluster.vetExactRemoval then
            if after < before then
                cluster.vetRemoved = {}
                for i = after + 1, before do table.insert(cluster.vetRemoved, copy(records[i])); records[i] = nil end
                cluster.vetRemovedAt = g_time
            elseif after > before then
                local source = cluster.vetCloneRecords
                for i = before + 1, after do
                    local offset = source ~= nil and #source - (after - i) or 0
                    records[i] = source ~= nil and copy(source[offset]) or {}
                end
                cluster.vetCloneRecords = nil
            end
        end
        cluster.vetAnimals = records
        if cluster.vetState ~= nil then cluster.vetState.vetLayout = nil end
    end
    return result
end

function V.clone(cluster, superFunc, ...)
    if g_server ~= nil then flush(cluster) end
    local result = superFunc(cluster, ...)
    if g_server ~= nil and result ~= nil then
        local source = cluster.vetRemovedAt == g_time and cluster.vetRemoved or cluster.vetAnimals
        cluster.vetRemovedAt = nil
        if source ~= nil then
            result.vetCloneRecords, result.vetAnimals = {}, {}
            result.vetOwner, result.vetState = nil, nil
            for i, record in ipairs(source) do result.vetCloneRecords[i] = copy(record) end
            for i = 1, count(result) do result.vetAnimals[i] = copy(source[i]) end
        end
    end
    return result
end

function V.updateClusters(system, superFunc, ...)
    if g_server == nil or V.busy then return superFunc(system, ...) end
    VeterinarianAnimalProfile.transferShearedRecords(system)
    local owner = system.owner
    local state = owner ~= nil and owner.spec_husbandryAnimals ~= nil and g_veterinarian ~= nil
        and g_currentMission ~= nil and g_currentMission.isMissionStarted
        and g_veterinarian:getOrCreateState(owner) or nil
    if state ~= nil then V.commit(owner, state) end
    local candidates = {}
    local function capture(cluster)
        if type(cluster) ~= "table" or cluster.getNumAnimals == nil or candidates[cluster] ~= nil then return end
        local records = {}
        for i = 1, count(cluster) do records[i] = copy((cluster.vetAnimals or {})[i]) end
        candidates[cluster] = {signature=signature(cluster), records=records, tracked=cluster.vetAnimals ~= nil,
            removed=(system.clustersToRemove or {})[cluster] ~= nil}
    end
    for _, cluster in ipairs(system:getClusters()) do capture(cluster) end
    for cluster, pending in pairs(system.clustersToAdd or {}) do if pending then capture(cluster) end end
    V.busy = true
    local result = superFunc(system, ...)
    V.busy = false
    local present = {}
    for _, cluster in ipairs(system:getClusters()) do present[cluster] = true end
    local pools = {}
    for cluster, candidate in pairs(candidates) do
        if not present[cluster] and candidate.tracked and not candidate.removed then
            local pool = pools[candidate.signature] or {}
            for _, record in ipairs(candidate.records) do table.insert(pool, record) end
            pools[candidate.signature] = pool
        end
    end
    for _, cluster in ipairs(system:getClusters()) do
        local records = cluster.vetAnimals or {}
        local previous = candidates[cluster]
        local pool = pools[signature(cluster)] or {}
        for i = 1, count(cluster) do
            if records[i] == nil or records[i].animalNames == nil then
                records[i] = previous ~= nil and previous.records[i] or nil
                if records[i] == nil or records[i].animalNames == nil then records[i] = table.remove(pool, 1) or {} end
            end
        end
        if cluster.vetAnimals ~= nil or (previous ~= nil and previous.tracked) or pools[signature(cluster)] ~= nil then
            cluster.vetAnimals = records
        end
    end
    if state ~= nil then
        state.vetLayout = nil
        V.reconcile(owner, state)
        state.vetNeedsBroadcast = true
    end
    return result
end

function V.registerXML(schema, basePath)
    local path = basePath .. ".animal(?).veterinarian.animal(?)"
    schema:register(XMLValueType.STRING, path .. "#id", "Veterinarian persistent identity")
    schema:register(XMLValueType.STRING, path .. "#name", "Veterinarian animal name")
    schema:register(XMLValueType.BOOL, path .. "#sick", "Veterinarian illness")
    schema:register(XMLValueType.INT, path .. "#pregnancy", "Veterinarian pregnancy progress")
    schema:register(XMLValueType.INT, path .. "#subType", "Veterinarian pregnancy subtype")
    for _, field in ipairs(VeterinarianLife.FIELDS) do schema:register(XMLValueType.INT, path .. "#" .. field, "Veterinarian " .. field) end
end

function V.save(cluster, xml, key)
    flush(cluster)
    for i, record in ipairs(cluster.vetAnimals or {}) do
        if i > count(cluster) then break end
        local path = string.format("%s.veterinarian.animal(%d)", key, i - 1)
        xml:setString(path .. "#name", record.animalNames or "")
        if record.animalIds ~= nil then xml:setString(path .. "#id", record.animalIds) end
        xml:setBool(path .. "#sick", record.sickAnimals == true)
        if record.inseminatedAnimals ~= nil then xml:setInt(path .. "#pregnancy", record.inseminatedAnimals) end
        if record.inseminatedSubTypes ~= nil then xml:setInt(path .. "#subType", record.inseminatedSubTypes) end
        for _, field in ipairs(VeterinarianLife.FIELDS) do
            if record[field] ~= nil then xml:setInt(path .. "#" .. field, record[field]) end
        end
    end
end

function V.load(cluster, superFunc, xml, key)
    local result = superFunc(cluster, xml, key)
    if result == false then return result end
    for i = 1, count(cluster) do
        local path = string.format("%s.veterinarian.animal(%d)", key, i - 1)
        local name = xml:getString(path .. "#name")
        if name ~= nil then
            cluster.vetAnimals = cluster.vetAnimals or {}
            local record = {animalIds=xml:getString(path .. "#id"), animalNames=name ~= "" and name or nil,
                sickAnimals=xml:getBool(path .. "#sick", false) or nil,
                inseminatedAnimals=xml:getInt(path .. "#pregnancy"),
                inseminatedSubTypes=xml:getInt(path .. "#subType")}
            for _, field in ipairs(VeterinarianLife.FIELDS) do record[field] = xml:getInt(path .. "#" .. field) end
            cluster.vetAnimals[i] = record
        end
    end
    return result
end

function V.resolve(placeable, index, expectedId)
    if placeable == nil or placeable.spec_husbandryAnimals == nil or g_veterinarian == nil then return nil end
    local state = g_veterinarian:getOrCreateState(placeable)
    if expectedId ~= nil then
        if expectedId == "" then return nil end
        for candidate, id in pairs(state.animalIds or {}) do if id == expectedId then return candidate end end
        return nil
    end
    if type(index) == "number" and index == math.floor(index) and index >= 1 and index <= placeable:getNumOfAnimals() then return index end
    return nil
end

function V.getId(placeable, index)
    if placeable == nil or g_veterinarian == nil then return "" end
    local state = g_veterinarian:getOrCreateState(placeable)
    return (state.animalIds or {})[index] or ""
end

AnimalCluster.changeNumAnimals = Utils.overwrittenFunction(AnimalCluster.changeNumAnimals, V.changeNumAnimals)
AnimalCluster.clone = Utils.overwrittenFunction(AnimalCluster.clone, V.clone)
AnimalCluster.saveToXMLFile = Utils.appendedFunction(AnimalCluster.saveToXMLFile, V.save)
AnimalCluster.loadFromXMLFile = Utils.overwrittenFunction(AnimalCluster.loadFromXMLFile, V.load)
AnimalClusterSystem.updateClusters = Utils.overwrittenFunction(AnimalClusterSystem.updateClusters, V.updateClusters)
AnimalClusterSystem.registerSavegameXMLPaths = Utils.appendedFunction(AnimalClusterSystem.registerSavegameXMLPaths, V.registerXML)
