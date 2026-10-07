-- ============================================================
-- FS25_VeterinarianNotificationEvent.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.0.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================

VeterinarianNotificationEvent = {}
local mt = Class(VeterinarianNotificationEvent, Event)
InitEventClass(VeterinarianNotificationEvent, "VeterinarianNotificationEvent")
function VeterinarianNotificationEvent.emptyNew() return Event.new(mt) end
function VeterinarianNotificationEvent.new(farmId, critical, key, args)
    local self = VeterinarianNotificationEvent.emptyNew()
    self.farmId, self.critical, self.key, self.args = farmId, critical, key, args or {}
    return self
end
function VeterinarianNotificationEvent:writeStream(streamId, connection)
    streamWriteUInt16(streamId, self.farmId)
    streamWriteBool(streamId, self.critical)
    streamWriteString(streamId, self.key)
    streamWriteUInt8(streamId, #self.args)
    for _, value in ipairs(self.args) do
        local numeric = type(value) == "number"
        streamWriteBool(streamId, numeric)
        if numeric then streamWriteInt32(streamId, value) else streamWriteString(streamId, tostring(value)) end
    end
end
function VeterinarianNotificationEvent:readStream(streamId, connection)
    self.farmId = streamReadUInt16(streamId)
    self.critical = streamReadBool(streamId)
    self.key = streamReadString(streamId)
    self.args = {}
    for i = 1, streamReadUInt8(streamId) do
        if streamReadBool(streamId) then self.args[i] = streamReadInt32(streamId) else self.args[i] = streamReadString(streamId) end
    end
    if connection:getIsServer() then self:show() end
end
function VeterinarianNotificationEvent:show()
    if g_client == nil or g_currentMission == nil or g_currentMission:getFarmId() ~= self.farmId then return end
    local allowed = {vet_birthResult=true, vet_birthAutoSold=true, vet_animalDied=true}
    if not allowed[self.key] then return end
    local args = {unpack(self.args)}
    if self.key == "vet_birthAutoSold" then args[2] = g_i18n:formatMoney(args[2], 0, true, true) end
    g_currentMission:addIngameNotification(self.critical and FSBaseMission.INGAME_NOTIFICATION_CRITICAL
        or FSBaseMission.INGAME_NOTIFICATION_INFO, string.format(g_i18n:getText(self.key), unpack(args)))
end
function VeterinarianNotificationEvent.send(placeable, critical, key, ...)
    if g_server == nil then return end
    local event = VeterinarianNotificationEvent.new(placeable:getOwnerFarmId(), critical, key, {...})
    event:show()
    g_server:broadcastEvent(event, false)
end
