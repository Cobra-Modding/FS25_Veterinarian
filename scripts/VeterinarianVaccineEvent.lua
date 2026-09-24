-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianVaccineEvent = {}
local VeterinarianVaccineEvent_mt = Class(VeterinarianVaccineEvent, Event)
InitEventClass(VeterinarianVaccineEvent, "VeterinarianVaccineEvent")

function VeterinarianVaccineEvent.emptyNew()
    return Event.new(VeterinarianVaccineEvent_mt)
end

function VeterinarianVaccineEvent.new(placeable, animalIndex)
    local self = VeterinarianVaccineEvent.emptyNew()
    self.placeable = placeable
    self.animalIndex = animalIndex or 0
    return self
end

function VeterinarianVaccineEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self:run(connection)
end

function VeterinarianVaccineEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, math.min(self.animalIndex, 65535))
end

function VeterinarianVaccineEvent:run(connection)
    if g_server ~= nil and g_veterinarian ~= nil then
        VeterinarianLife.vaccinate(self.placeable, self.animalIndex, connection)
    end
end

function VeterinarianVaccineEvent.sendEvent(placeable, animalIndex)
    if g_server ~= nil then
        if g_veterinarian ~= nil then
            VeterinarianLife.vaccinate(placeable, animalIndex, nil)
        end
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(VeterinarianVaccineEvent.new(placeable, animalIndex))
    end
end
