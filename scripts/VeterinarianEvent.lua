-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianEvent = {}
local VeterinarianEvent_mt = Class(VeterinarianEvent, Event)
InitEventClass(VeterinarianEvent, "VeterinarianEvent")

function VeterinarianEvent.emptyNew()
    return Event.new(VeterinarianEvent_mt)
end

function VeterinarianEvent.new(placeable, animalIndex)
    local self = VeterinarianEvent.emptyNew()
    self.placeable = placeable
    self.animalIndex = animalIndex or 0
    return self
end

function VeterinarianEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self:run(connection)
end

function VeterinarianEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
end

function VeterinarianEvent:run(connection)
    if g_server ~= nil and g_veterinarian ~= nil then
        g_veterinarian:treatHusbandry(self.placeable, connection, self.animalIndex)
    end
end

function VeterinarianEvent.sendEvent(placeable, animalIndex)
    if g_server ~= nil then
        if g_veterinarian ~= nil then
            g_veterinarian:treatHusbandry(placeable, nil, animalIndex)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(VeterinarianEvent.new(placeable, animalIndex))
    end
end
