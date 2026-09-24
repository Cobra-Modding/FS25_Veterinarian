-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianResultEvent = {}
local VeterinarianResultEvent_mt = Class(VeterinarianResultEvent, Event)
InitEventClass(VeterinarianResultEvent, "VeterinarianResultEvent")

function VeterinarianResultEvent.emptyNew()
    return Event.new(VeterinarianResultEvent_mt)
end

function VeterinarianResultEvent.new(success, count, cost)
    local self = VeterinarianResultEvent.emptyNew()
    self.success = success
    self.count = count or 0
    self.cost = cost or 0
    return self
end

function VeterinarianResultEvent:readStream(streamId, connection)
    self.success = streamReadBool(streamId)
    self.count = streamReadUInt16(streamId)
    self.cost = streamReadInt32(streamId)
    self:run(connection)
end

function VeterinarianResultEvent:writeStream(streamId, connection)
    streamWriteBool(streamId, self.success)
    streamWriteUInt16(streamId, math.min(self.count, 65535))
    streamWriteInt32(streamId, self.cost)
end

function VeterinarianResultEvent:run(connection)
    if g_veterinarian ~= nil then
        g_veterinarian:showTreatmentResult(self.success, self.count, self.cost)
    end
end

function VeterinarianResultEvent.sendEvent(success, count, cost, connection)
    if connection ~= nil then
        connection:sendEvent(VeterinarianResultEvent.new(success, count, cost))
    elseif g_server == nil and g_veterinarian ~= nil then
        g_veterinarian:showTreatmentResult(success, count, cost)
    end
end
