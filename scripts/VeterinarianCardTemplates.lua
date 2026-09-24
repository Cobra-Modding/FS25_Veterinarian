-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianCardTemplates = {}
local mt = Class(VeterinarianCardTemplates, ScreenElement)
VeterinarianCardTemplates.MOD_DIRECTORY = g_currentModDirectory

-- Resource holder only: this GUI is never shown as a screen or dialog.
function VeterinarianCardTemplates.register()
    if VeterinarianCardTemplates.INSTANCE ~= nil then return end
    local self = ScreenElement.new(nil, mt)
    g_gui:loadGui(VeterinarianCardTemplates.MOD_DIRECTORY .. "gui/VeterinarianCardTemplates.xml", "VeterinarianCardTemplates", self)
    VeterinarianCardTemplates.INSTANCE = self
end

function VeterinarianCardTemplates:onCreate()
    VeterinarianAnimalList.setTextures(self)
    self.embeddedRowTemplate:unlinkElement()
    self.embeddedPanelTemplate:unlinkElement()
end

function VeterinarianCardTemplates:delete()
    if self.embeddedRowTemplate ~= nil then self.embeddedRowTemplate:delete() end
    if self.embeddedPanelTemplate ~= nil then self.embeddedPanelTemplate:delete() end
    VeterinarianCardTemplates:superClass().delete(self)
end
