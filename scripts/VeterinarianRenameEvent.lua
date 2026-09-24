-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianRenameEvent = {}
local VeterinarianRenameEvent_mt = Class(VeterinarianRenameEvent, Event)
InitEventClass(VeterinarianRenameEvent, "VeterinarianRenameEvent")

function VeterinarianRenameEvent.emptyNew()
    return Event.new(VeterinarianRenameEvent_mt)
end

function VeterinarianRenameEvent.new(placeable, animalIndex, name)
    local self = VeterinarianRenameEvent.emptyNew()
    self.placeable = placeable
    self.animalIndex = animalIndex
    self.name = name
    return self
end

function VeterinarianRenameEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self.animalIndex = streamReadUInt16(streamId)
    self.name = streamReadString(streamId)
    self:run(connection)
end

function VeterinarianRenameEvent:writeStream(streamId, connection)
    NetworkUtil.writeNodeObject(streamId, self.placeable)
    streamWriteUInt16(streamId, self.animalIndex)
    streamWriteString(streamId, self.name)
end

function VeterinarianRenameEvent:run(connection)
    if g_server ~= nil and not connection:getIsServer() and g_veterinarian ~= nil then
        g_veterinarian:renameAnimal(self.placeable, self.animalIndex, self.name, connection)
    end
end

function VeterinarianRenameEvent.sendEvent(placeable, animalIndex, name)
    if g_server ~= nil then
        g_veterinarian:renameAnimal(placeable, animalIndex, name, nil)
    elseif g_client ~= nil then
        g_client:getServerConnection():sendEvent(VeterinarianRenameEvent.new(placeable, animalIndex, name))
    end
end
