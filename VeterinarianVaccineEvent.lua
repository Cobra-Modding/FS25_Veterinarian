-- ============================================================
-- FS25_VeterinarianVaccineEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianVaccineEvent = {}
local VeterinarianVaccineEvent_mt = Class(VeterinarianVaccineEvent, Event)
InitEventClass(VeterinarianVaccineEvent, "VeterinarianVaccineEvent")

function VeterinarianVaccineEvent.emptyNew()
    return Event.new(VeterinarianVaccineEvent_mt)
end

function VeterinarianVaccineEvent.new(placeable, animalIndex, animalId)
    local self = VeterinarianVaccineEvent.emptyNew()
    self.placeable = placeable
    self.animalId = animalId or VeterinarianIdentity.getId(placeable, animalIndex)
    self.animalIndex = animalIndex or 0
    return self
end

function VeterinarianVaccineEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self.animalId = streamReadString(streamId)
    self:run(connection)
end

function VeterinarianVaccineEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
    streamWriteString(streamId, self.animalId or "")
end

function VeterinarianVaccineEvent:run(connection)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() and g_veterinarian ~= nil then
        VeterinarianLife.vaccinate(self.placeable, self.animalIndex, connection, self.animalId)
    end
end

function VeterinarianVaccineEvent.sendEvent(placeable, animalIndex, animalId)
    if g_server ~= nil then
        if g_veterinarian ~= nil then
            VeterinarianLife.vaccinate(placeable, animalIndex, nil, animalId)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(VeterinarianVaccineEvent.new(placeable, animalIndex, animalId))
    end
end
