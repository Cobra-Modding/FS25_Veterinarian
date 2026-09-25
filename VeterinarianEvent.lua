-- ============================================================
-- FS25_VeterinarianEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianEvent = {}
local VeterinarianEvent_mt = Class(VeterinarianEvent, Event)
InitEventClass(VeterinarianEvent, "VeterinarianEvent")

function VeterinarianEvent.emptyNew()
    return Event.new(VeterinarianEvent_mt)
end

function VeterinarianEvent.new(placeable, animalIndex, animalId)
    local self = VeterinarianEvent.emptyNew()
    self.placeable = placeable
    self.animalId = animalId or VeterinarianIdentity.getId(placeable, animalIndex)
    self.animalIndex = animalIndex or 0
    return self
end

function VeterinarianEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self.animalId = streamReadString(streamId)
    self:run(connection)
end

function VeterinarianEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
    streamWriteString(streamId, self.animalId or "")
end

function VeterinarianEvent:run(connection)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() and g_veterinarian ~= nil then
        g_veterinarian:treatHusbandry(self.placeable, connection, self.animalIndex, self.animalId)
    end
end

function VeterinarianEvent.sendEvent(placeable, animalIndex, animalId)
    if g_server ~= nil then
        if g_veterinarian ~= nil then
            g_veterinarian:treatHusbandry(placeable, nil, animalIndex, animalId)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(VeterinarianEvent.new(placeable, animalIndex, animalId))
    end
end
