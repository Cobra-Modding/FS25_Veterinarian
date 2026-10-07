-- ============================================================
-- FS25_VeterinarianStateEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianStateEvent = {}
local VeterinarianStateEvent_mt = Class(VeterinarianStateEvent, Event)
InitEventClass(VeterinarianStateEvent, "VeterinarianStateEvent")

function VeterinarianStateEvent.emptyNew()
    return Event.new(VeterinarianStateEvent_mt)
end

function VeterinarianStateEvent.new(placeable, sick, disease, showNotification, sickAnimals,
        animalNames, inseminatedAnimals, inseminatedSubTypes, extra)
    local self = VeterinarianStateEvent.emptyNew()
    self.extra = VeterinarianLife.ensure({extra=extra})
    self.placeable = placeable
    self.sick = sick
    self.disease = disease
    self.showNotification = showNotification == true
    self.sickAnimals = sickAnimals or {}
    self.animalNames = animalNames or {}
    local state = g_veterinarian ~= nil and g_veterinarian:getOrCreateState(placeable) or nil
    self.animalIds = state ~= nil and state.animalIds or {}
    self.inseminatedAnimals = inseminatedAnimals or {}
    self.inseminatedSubTypes = inseminatedSubTypes or {}
    return self
end

function VeterinarianStateEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.sick = streamReadUInt16(streamId)
    self.disease = streamReadUInt8(streamId)
    self.showNotification = streamReadBool(streamId)
    self.sickAnimals = {}
    local numIndices = streamReadUInt16(streamId)
    for _ = 1, numIndices do
        self.sickAnimals[streamReadUInt16(streamId)] = true
    end
    self.animalNames = {}
    local numNames = streamReadUInt16(streamId)
    self.animalIds = {}
    for index = 1, numNames do
        self.animalNames[index] = streamReadString(streamId)
        self.animalIds[index] = streamReadString(streamId)
    end
    self.inseminatedAnimals = {}
    self.inseminatedSubTypes = {}
    local numInseminated = streamReadUInt16(streamId)
    for _ = 1, numInseminated do
        local animalIndex = streamReadUInt16(streamId)
        self.inseminatedAnimals[animalIndex] = streamReadUInt8(streamId)
        self.inseminatedSubTypes[animalIndex] = streamReadUInt16(streamId)
    end
    self.extra = VeterinarianLife.ensure({})
    for _, field in ipairs(VeterinarianLife.FIELDS) do
        for index = 1, #self.animalNames do
            if streamReadBool(streamId) then self.extra[field][index] = streamReadUInt16(streamId) end
        end
    end
    self:run(connection)
end

function VeterinarianStateEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, math.min(self.sick, 65535))
    streamWriteUInt8(streamId, self.disease)
    streamWriteBool(streamId, self.showNotification)
    local indices = {}
    for index, isSick in pairs(self.sickAnimals) do
        if isSick then table.insert(indices, index) end
    end
    table.sort(indices)
    streamWriteUInt16(streamId, math.min(#indices, 65535))
    for i = 1, math.min(#indices, 65535) do streamWriteUInt16(streamId, math.min(indices[i], 65535)) end
    streamWriteUInt16(streamId, math.min(#self.animalNames, 65535))
    for index = 1, math.min(#self.animalNames, 65535) do
        streamWriteString(streamId, self.animalNames[index])
        streamWriteString(streamId, (self.animalIds or {})[index] or "")
    end
    local inseminated = {}
    for index in pairs(self.inseminatedAnimals) do table.insert(inseminated, index) end
    table.sort(inseminated)
    streamWriteUInt16(streamId, math.min(#inseminated, 65535))
    for i = 1, math.min(#inseminated, 65535) do
        local index = inseminated[i]
        streamWriteUInt16(streamId, math.min(index, 65535))
        streamWriteUInt8(streamId, math.min(self.inseminatedAnimals[index], 255))
        streamWriteUInt16(streamId, math.min(self.inseminatedSubTypes[index] or 0, 65535))
    end
    for _, field in ipairs(VeterinarianLife.FIELDS) do
        for index = 1, math.min(#self.animalNames, 65535) do
            local value = self.extra[field][index]
            streamWriteBool(streamId, value ~= nil)
            if value ~= nil then streamWriteUInt16(streamId, math.min(65535, math.max(0, value))) end
        end
    end
end

function VeterinarianStateEvent:run(connection)
    if g_server == nil and connection:getIsServer() and g_veterinarian ~= nil then
        g_veterinarian:receiveState(self.placeable, self.sick, self.disease,
            self.showNotification, self.sickAnimals, self.animalNames,
            self.inseminatedAnimals, self.inseminatedSubTypes, self.extra, self.animalIds)
    end
end

function VeterinarianStateEvent.sendEvent(placeable, sick, disease, showNotification, sickAnimals,
        animalNames, inseminatedAnimals, inseminatedSubTypes, connection, extra)
    if g_server ~= nil then
        local event = VeterinarianStateEvent.new(placeable, sick, disease, showNotification,
            sickAnimals, animalNames, inseminatedAnimals, inseminatedSubTypes, extra)
        if connection ~= nil then
            connection:sendEvent(event)
        else
            g_server:broadcastEvent(event, false, nil, placeable)
        end
    end
end
