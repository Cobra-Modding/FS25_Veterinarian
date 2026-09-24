-- FS25_Veterinarian - Version 1.0.0.0
ArtificialInseminationResultEvent = {}
local ArtificialInseminationResultEvent_mt = Class(ArtificialInseminationResultEvent, Event)
InitEventClass(ArtificialInseminationResultEvent, "ArtificialInseminationResultEvent")

function ArtificialInseminationResultEvent.emptyNew()
    return Event.new(ArtificialInseminationResultEvent_mt)
end

function ArtificialInseminationResultEvent.new(result, count, cost)
    local self = ArtificialInseminationResultEvent.emptyNew()
    self.result = result or 0
    self.count = count or 0
    self.cost = cost or 0
    return self
end

function ArtificialInseminationResultEvent:readStream(streamId, connection)
    self.result = streamReadUInt8(streamId)
    self.count = streamReadUInt16(streamId)
    self.cost = streamReadInt32(streamId)
    self:run(connection)
end

function ArtificialInseminationResultEvent:writeStream(streamId, connection)
    streamWriteUInt8(streamId, self.result)
    streamWriteUInt16(streamId, math.min(self.count, 65535))
    streamWriteInt32(streamId, self.cost)
end

function ArtificialInseminationResultEvent:run(connection)
    if ArtificialInsemination ~= nil then
        ArtificialInsemination.showResult(self.result, self.count, self.cost)
    end
end

function ArtificialInseminationResultEvent.sendEvent(result, count, cost, connection)
    if connection ~= nil then
        connection:sendEvent(ArtificialInseminationResultEvent.new(result, count, cost))
    else
        ArtificialInsemination.showResult(result, count, cost)
    end
end
