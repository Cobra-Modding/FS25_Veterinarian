-- ============================================================
-- FS25_ArtificialInseminationEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

ArtificialInseminationEvent = {}
local ArtificialInseminationEvent_mt = Class(ArtificialInseminationEvent, Event)
InitEventClass(ArtificialInseminationEvent, "ArtificialInseminationEvent")

function ArtificialInseminationEvent.emptyNew()
    return Event.new(ArtificialInseminationEvent_mt)
end

function ArtificialInseminationEvent.new(husbandry, animalIndex, animalId)
    local self = ArtificialInseminationEvent.emptyNew()
    self.husbandry = husbandry
    self.animalId = animalId or VeterinarianIdentity.getId(husbandry, animalIndex)
    self.animalIndex = animalIndex or 0
    return self
end

function ArtificialInseminationEvent:readStream(streamId, connection)
    self.husbandry = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self.animalId = streamReadString(streamId)
    self:run(connection)
end

function ArtificialInseminationEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.husbandry)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
    streamWriteString(streamId, self.animalId or "")
end

function ArtificialInseminationEvent:run(connection)
    if g_server ~= nil and connection ~= nil and not connection:getIsServer() and ArtificialInsemination ~= nil then
        ArtificialInsemination.perform(self.husbandry, self.animalIndex, connection, self.animalId)
    end
end
