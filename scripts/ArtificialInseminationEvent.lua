-- FS25_Veterinarian - Version 1.0.0.0
ArtificialInseminationEvent = {}
local ArtificialInseminationEvent_mt = Class(ArtificialInseminationEvent, Event)
InitEventClass(ArtificialInseminationEvent, "ArtificialInseminationEvent")

function ArtificialInseminationEvent.emptyNew()
    return Event.new(ArtificialInseminationEvent_mt)
end

function ArtificialInseminationEvent.new(husbandry, animalIndex)
    local self = ArtificialInseminationEvent.emptyNew()
    self.husbandry = husbandry
    self.animalIndex = animalIndex or 0
    return self
end

function ArtificialInseminationEvent:readStream(streamId, connection)
    self.husbandry = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self:run(connection)
end

function ArtificialInseminationEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.husbandry)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
end

function ArtificialInseminationEvent:run(connection)
    if g_server ~= nil and ArtificialInsemination ~= nil then
        ArtificialInsemination.perform(self.husbandry, self.animalIndex, connection)
    end
end
