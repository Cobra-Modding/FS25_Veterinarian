-- FS25_Veterinarian - Version 1.0.0.0
VeterinarianActionsDialog = {}
local mt = Class(VeterinarianActionsDialog, ScreenElement)
VeterinarianActionsDialog.MOD_DIRECTORY = g_currentModDirectory

function VeterinarianActionsDialog.show(husbandry, index)
    if husbandry == nil or index == nil or husbandry:getOwnerFarmId() ~= g_currentMission:getFarmId() then return end
    local self = VeterinarianActionsDialog.INSTANCE
    if self == nil then
        self = ScreenElement.new(nil, mt)
        g_gui:loadGui(VeterinarianActionsDialog.MOD_DIRECTORY .. "gui/VeterinarianActionsDialog.xml", "VeterinarianActionsDialog", self)
        VeterinarianActionsDialog.INSTANCE = self
    end
    self.husbandry, self.animalIndex = husbandry, index
    if self:refreshAnimals() then g_gui:showDialog("VeterinarianActionsDialog") end
end

function VeterinarianActionsDialog:onCreate()
    VeterinarianAnimalList.setTextures(self)
    self.actionButtons = {
        {element=self.inseminationButton, texture="actionWide"},
        {element=self.vaccineButton, texture="actionWide"},
        {element=self.renameButton, texture="actionWide"}
    }
    for _, entry in ipairs(self.actionButtons) do
        VeterinarianAnimalList.setFullImage(entry.element:getDescendantByName("actionChevron"),
            self.MOD_DIRECTORY .. "gui/textures/actionChevron.dds")
    end
end

function VeterinarianActionsDialog:findEntry(entries)
    for _, entry in ipairs(entries) do
        if entry.index == self.animalIndex then return entry end
    end
end

function VeterinarianActionsDialog:refreshAnimals()
    local state = g_veterinarian:getOrCreateState(self.husbandry)
    local card = VeterinarianAnimalList.getCards(self.husbandry, state)[self.animalIndex]
    if card == nil then return false end
    VeterinarianAnimalList.fillCard(self.animalCard, card)
    self.inseminationEntry = self:findEntry(ArtificialInsemination.getAnimalEntries(self.husbandry, state))
    self.vaccineEntry = self:findEntry(VeterinarianLife.vaccinationEntries(self.husbandry, state))
    self.inseminationButton:setDisabled(g_veterinarian:isChickenHusbandry(self.husbandry)
        or self.inseminationEntry == nil or not self.inseminationEntry.canInseminate)
    self.treatmentEntry = self:findEntry(g_veterinarian:getAnimalTreatmentEntries(self.husbandry, state))
    self.vaccineButton:getDescendantByName("label"):setText(g_i18n:getText(self.treatmentEntry ~= nil and "vet_treatAction" or "vet_vaccineMode"))
    self.vaccineButton:setDisabled(self.treatmentEntry == nil and (self.vaccineEntry == nil or not self.vaccineEntry.canVaccinate))
    return true
end

function VeterinarianActionsDialog:onOpen()
    VeterinarianActionsDialog:superClass().onOpen(self)
    FocusManager:setFocus(not self.inseminationButton:getIsDisabled() and self.inseminationButton
        or (not self.vaccineButton:getIsDisabled() and self.vaccineButton or self.renameButton))
    g_inputBinding:removeActionEventsByTarget(self)
    for _, action in ipairs({InputAction.VET_INSEMINATE, InputAction.MENU_EXTRA_2, InputAction.MENU_EXTRA_1, InputAction.MENU_BACK}) do
        local _, id = g_inputBinding:registerActionEvent(action, self, self.onServiceAction, false, true, false, true)
        if id ~= nil then g_inputBinding:setActionEventTextVisibility(id, false) end
    end
end

function VeterinarianActionsDialog:onClose()
    g_inputBinding:removeActionEventsByTarget(self)
    VeterinarianActionsDialog:superClass().onClose(self)
end

function VeterinarianActionsDialog:onClickBack()
    g_gui:closeDialogByName("VeterinarianActionsDialog")
end

function VeterinarianActionsDialog:reopen()
    if self:refreshAnimals() then g_gui:showDialog("VeterinarianActionsDialog") end
end

function VeterinarianActionsDialog:onInseminate()
    if not self:refreshAnimals() or self.inseminationButton:getIsDisabled() then return end
    local entry = self.inseminationEntry
    self:onClickBack()
    YesNoDialog.show(self.onInseminationConfirmed, self,
        string.format(g_i18n:getText("vet_inseminationConfirmSingle"), entry.title, entry.price),
        g_i18n:getText("vet_inseminationTitle"))
end

function VeterinarianActionsDialog:onInseminationConfirmed(confirmed)
    if confirmed then ArtificialInsemination.request(self.husbandry, self.animalIndex) end
    self:reopen()
end

function VeterinarianActionsDialog:onVaccinate()
    if not self:refreshAnimals() or self.vaccineButton:getIsDisabled() then return end
    if self.treatmentEntry ~= nil then
        local entry = self.treatmentEntry
        self:onClickBack()
        YesNoDialog.show(self.onTreatmentConfirmed, self,
            string.format(g_i18n:getText("vet_treatConfirm"), entry.title, entry.price),
            g_i18n:getText("vet_treatAction"))
        return
    end
    local entry = self.vaccineEntry
    self:onClickBack()
    YesNoDialog.show(self.onVaccinationConfirmed, self,
        string.format(g_i18n:getText("vet_vaccineConfirm"), entry.title, entry.price),
        g_i18n:getText("vet_vaccineMode"))
end

function VeterinarianActionsDialog:onVaccinationConfirmed(confirmed)
    if confirmed then VeterinarianVaccineEvent.sendEvent(self.husbandry, self.animalIndex) end
    self:reopen()
end

function VeterinarianActionsDialog:onRename()
    if not self:refreshAnimals() then return end
    local dialog = g_gui.guis["TextInputDialog"]
    if dialog == nil then return end
    local state = g_veterinarian:getOrCreateState(self.husbandry)
    self:onClickBack()
    dialog.target:setText(g_i18n:getText("vet_renameTitle"))
    dialog.target:setCallback(self.onNameEntered, self, state.animalNames[self.animalIndex] or "",
        g_i18n:getText("vet_renameTitle"), nil, 24)
    g_gui:showDialog("TextInputDialog")
end

function VeterinarianActionsDialog:onNameEntered(name, confirmed)
    if confirmed then VeterinarianRenameEvent.sendEvent(self.husbandry, self.animalIndex, name) end
    self:reopen()
end

function VeterinarianActionsDialog:onServiceAction(action)
    if not self.isOpen then return end
    if action == InputAction.VET_INSEMINATE then self:onInseminate()
    elseif action == InputAction.MENU_EXTRA_2 then self:onVaccinate()
    elseif action == InputAction.MENU_EXTRA_1 then self:onRename()
    elseif action == InputAction.MENU_BACK then self:onClickBack() end
end

function VeterinarianActionsDialog:update(dt)
    VeterinarianActionsDialog:superClass().update(self, dt)
    if self.isOpen then self:updateActionButtons() end
end

function VeterinarianActionsDialog:updateActionButtons()
    -- Mouse hover takes precedence over a previously keyboard-focused button.
    local hovered = nil
    for _, entry in ipairs(self.actionButtons or {}) do
        local button = entry.element
        if button:getIsVisible() and not button:getIsDisabled() and button:getIsHighlighted() then
            hovered = button
            break
        end
    end
    for _, entry in ipairs(self.actionButtons or {}) do
        local button = entry.element
        local disabled = button:getIsDisabled()
        local active = not disabled and (button == hovered or (hovered == nil and button:getIsFocused()))
        local suffix = disabled and "Disabled" or (active and (button:getIsPressed() and "Pressed" or "Active") or "")
        local texture = entry.texture .. suffix
        if entry.currentTexture ~= texture then
            VeterinarianAnimalList.setFullImage(button, VeterinarianActionsDialog.MOD_DIRECTORY .. "gui/textures/" .. texture .. ".dds")
            entry.currentTexture = texture
            local label = button:getDescendantByName("label")
            local color = disabled and {0.45, 0.47, 0.43, 1}
                or (active and {0.015, 0.020, 0.005, 1} or {0.94, 0.94, 0.93, 1})
            for _, method in ipairs({"setTextColor", "setTextFocusedColor", "setTextSelectedColor", "setTextHighlightedColor", "setTextDisabledColor"}) do
                if label[method] ~= nil then label[method](label, unpack(color)) end
            end
        end
        button:getDescendantByName("actionChevron"):setVisible(active)
    end
end


function VeterinarianActionsDialog:onTreatmentConfirmed(confirmed)
    if confirmed then VeterinarianEvent.sendEvent(self.husbandry, self.animalIndex) end
    self:reopen()
end
