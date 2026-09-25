-- ============================================================
-- FS25_VeterinarianSyncEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianSyncEvent = {}
local mt = Class(VeterinarianSyncEvent, Event)
InitEventClass(VeterinarianSyncEvent, "VeterinarianSyncEvent")
function VeterinarianSyncEvent.emptyNew() return Event.new(mt) end
function VeterinarianSyncEvent.new(placeable)
    local self = VeterinarianSyncEvent.emptyNew()
    self.placeable = placeable
    return self
end
function VeterinarianSyncEvent:writeStream(streamId, connection) NetworkUtil.writeNodeObject(streamId, self.placeable) end
function VeterinarianSyncEvent:readStream(streamId, connection)
    self.placeable = NetworkUtil.readNodeObject(streamId)
    self:run(connection)
end
function VeterinarianSyncEvent:run(connection)
    if g_server == nil or connection == nil or connection:getIsServer() or g_veterinarian == nil
        or self.placeable == nil or self.placeable.spec_husbandryAnimals == nil then return end
    local vet = g_veterinarian
    vet.syncRequests = vet.syncRequests or setmetatable({}, {__mode="k"})
    local requests = vet.syncRequests[connection] or setmetatable({}, {__mode="k"})
    vet.syncRequests[connection] = requests
    local now = g_time or 0
    if requests[self.placeable] ~= nil and now - requests[self.placeable] < 4000 then return end
    requests[self.placeable] = now
    vet:broadcastState(self.placeable, nil, connection)
end
function VeterinarianSyncEvent.requestMissing(vet, dt)
    if g_client == nil then return end
    vet.syncTimer = (vet.syncTimer or 0) + dt
    if vet.syncTimer < 2000 then return end
    vet.syncTimer = 0
    vet.requestedHusbandries = vet.requestedHusbandries or setmetatable({}, {__mode="k"})
    for _, husbandry in ipairs(vet:getHusbandries()) do
        local state = vet:getOrCreateState(husbandry)
        local last = vet.requestedHusbandries[husbandry]
        if not state.synchronized and (last == nil or (g_time or 0) - last >= 5000) then
            vet.requestedHusbandries[husbandry] = g_time or 0
            g_client:getServerConnection():sendEvent(VeterinarianSyncEvent.new(husbandry))
        end
    end
end
