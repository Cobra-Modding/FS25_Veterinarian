-- FS25_Veterinarian - Version 1.0.0.0
Veterinarian = {}
local Veterinarian_mt = Class(Veterinarian)

Veterinarian.BASE_DAILY_CHANCE = 0.015
Veterinarian.CALL_OUT_FEE = 350
Veterinarian.COST_PER_ANIMAL = 125
Veterinarian.TEST_FORCE_DISEASE_ON_LOAD = false
Veterinarian.TEST_SICK_SHARE = 0.5

local DISEASES = {
    "Atemwegsinfekt",
    "Magen-Darm-Infekt",
    "Fieber",
    "Klauenentzündung",
    "Parasitenbefall"
}

function Veterinarian.new()
    local self = setmetatable({}, Veterinarian_mt)
    self.states = {}
    self.initialSyncPending = true
    self.testDiseasePending = Veterinarian.TEST_FORCE_DISEASE_ON_LOAD
    self.animalScreenHookInstalled = false
    self.animalsFrameHookInstalled = false
    self.overviewAnchorWarningShown = false
    self.nameReconcileTimer = 0
    return self
end

local function resolvePlaceable(husbandry)
    if husbandry == nil then return nil end
    if husbandry.owningPlaceable ~= nil then return husbandry.owningPlaceable end
    if husbandry.placeable ~= nil then return husbandry.placeable end
    return husbandry
end

local function ensureIndividualState(state, numAnimals, allocateAnimalName)
    local hasIndividualState = state.sickAnimals ~= nil
    VeterinarianLife.ensure(state)
    state.sickAnimals = state.sickAnimals or {}
    state.animalNames = state.animalNames or {}
    state.inseminatedAnimals = state.inseminatedAnimals or {}
    state.inseminatedSubTypes = state.inseminatedSubTypes or {}
    if not hasIndividualState and (state.sick or 0) > 0 then
        for index = 1, math.min(state.sick, numAnimals) do
            state.sickAnimals[index] = true
        end
    end

    local count = 0
    for index, isSick in pairs(state.sickAnimals) do
        if not isSick or index < 1 or index > numAnimals then
            state.sickAnimals[index] = nil
        else
            count = count + 1
        end
    end
    state.sick = count
    for index = 1, numAnimals do
        if state.animalNames[index] == nil and allocateAnimalName ~= nil then
            state.animalNames[index] = allocateAnimalName()
        end
    end
    for index in pairs(state.animalNames) do
        if index < 1 or index > numAnimals then state.animalNames[index] = nil end
    end
    for index in pairs(state.inseminatedAnimals) do
        if index < 1 or index > numAnimals then
            state.inseminatedAnimals[index] = nil
            state.inseminatedSubTypes[index] = nil
        end
    end
    for _, field in ipairs(VeterinarianLife.FIELDS) do
        for index in pairs(state.extra[field]) do
            if index < 1 or index > numAnimals then state.extra[field][index] = nil end
        end
    end
    return state
end

local function getSickAnimalIndices(state)
    local result = {}
    if state ~= nil and state.sickAnimals ~= nil then
        for index, isSick in pairs(state.sickAnimals) do
            if isSick then table.insert(result, index) end
        end
    end
    table.sort(result)
    return result
end

local function getHusbandries()
    local result = {}
    local system = g_currentMission ~= nil and g_currentMission.placeableSystem or nil
    if system == nil or system.placeables == nil then
        return result
    end

    for _, placeable in pairs(system.placeables) do
        if placeable.spec_husbandryAnimals ~= nil and placeable.getNumOfAnimals ~= nil then
            table.insert(result, placeable)
        end
    end
    return result
end

local function getKey(placeable)
    if placeable == nil then return nil end
    local x, _, z = 0, 0, 0
    if placeable.rootNode ~= nil then
        x, _, z = getWorldTranslation(placeable.rootNode)
    end
    local config = placeable.configFileName or "husbandry"
    return string.format("%s@%.1f@%.1f", config, x, z)
end

local function getName(placeable)
    if placeable.getName ~= nil then
        local name = placeable:getName()
        if name ~= nil and name ~= "" then return name end
    end
    return "Tierstall"
end

local function notify(kind, text)
    if g_currentMission ~= nil and g_currentMission.addIngameNotification ~= nil then
        g_currentMission:addIngameNotification(kind, text)
    end
end

local function formatMoney(value)
    if g_i18n ~= nil and g_i18n.formatMoney ~= nil then
        return g_i18n:formatMoney(value, 0, true, true)
    end
    return string.format("%d €", value)
end

function Veterinarian:loadMap()
    g_veterinarian = self
    if ArtificialInsemination ~= nil then ArtificialInsemination.install() end
    if g_server ~= nil then self:loadState() end

    if g_messageCenter ~= nil and MessageType ~= nil and MessageType.HOUR_CHANGED ~= nil then
        g_messageCenter:subscribe(MessageType.HOUR_CHANGED, self.hourChanged, self)
    end
    self:installAnimalScreenHook()
    self:installAnimalsFrameHook()
    if g_client ~= nil and VeterinarianCardTemplates ~= nil then
        VeterinarianCardTemplates.register()
    end
end

function Veterinarian:deleteMap()
    if g_messageCenter ~= nil then
        g_messageCenter:unsubscribeAll(self)
    end
    if g_veterinarian == self then g_veterinarian = nil end
end

function Veterinarian:update(dt)
    if g_client ~= nil and g_animalScreen ~= nil and g_animalScreen.isOpen == true then
        if g_animalScreen.veterinarianStatus == nil then
            self:addAnimalScreenStatus(g_animalScreen)
        end
        self:updateAnimalScreenStatus(g_animalScreen)
        VeterinarianAnimalList.updateEmbedded(g_animalScreen, dt)
    end


    if not self.animalsFrameHookInstalled then
        self:installAnimalsFrameHook()
    end

    if g_server == nil or g_currentMission == nil then return end
    self.nameReconcileTimer = self.nameReconcileTimer + dt
    if self.nameReconcileTimer >= 2000 then
        self.nameReconcileTimer = 0
        for _, husbandry in ipairs(getHusbandries()) do
            local numAnimals = math.max(0, husbandry:getNumOfAnimals() or 0)
            local state = self.states[getKey(husbandry)]
            local oldCount = state ~= nil and #(state.animalNames or {}) or 0
            state = self:getOrCreateState(husbandry)
            if oldCount ~= numAnimals then self:broadcastState(husbandry, state) end
        end
    end
    if self.testDiseasePending and g_currentMission.isMissionStarted then
        self:forceExistingAnimalsSickForTest()
    end
    if self.initialSyncPending then
        self.initialSyncPending = false
        self:syncAllStates(false)
    end
end

function Veterinarian:hourChanged()
    if g_server ~= nil then
        self:runDiseaseCheck()
    end
end

function Veterinarian:periodChanged()
    if ArtificialInsemination ~= nil then ArtificialInsemination.periodChanged() end
end

local ANIMAL_NAMES = {
    "Bella", "Luna", "Lotte", "Emma", "Frieda", "Alma", "Rosa", "Maja",
    "Daisy", "Molly", "Nala", "Paula", "Berta", "Heidi", "Elsa", "Greta",
    "Lilly", "Flora", "Clara", "Pia", "Romy", "Mila", "Tilda", "Susi",
    "Flocke", "Pünktchen", "Sternchen", "Wölkchen", "Sunny", "Cookie",
    "Muffin", "Krümel", "Sammy", "Charlie", "Willi", "Max", "Felix", "Oskar"
}

function Veterinarian:allocateAnimalName()
    return ANIMAL_NAMES[math.random(1, #ANIMAL_NAMES)]
end

function Veterinarian:renameAnimal(placeable, animalIndex, name, connection)
    if g_server == nil or placeable == nil or placeable.spec_husbandryAnimals == nil then return false end
    local farmId = placeable:getOwnerFarmId()
    if connection ~= nil then
        local userId = g_currentMission.userManager:getUserIdByConnection(connection)
        local farm = userId ~= nil and g_farmManager:getFarmByUserId(userId) or nil
        if farm == nil or farm.farmId ~= farmId then return false end
    elseif g_currentMission:getFarmId() ~= farmId then
        return false
    end
    if type(animalIndex) ~= "number" or animalIndex ~= math.floor(animalIndex)
            or animalIndex < 1 or animalIndex > placeable:getNumOfAnimals() then return false end
    if type(name) ~= "string" then return false end
    name = name:gsub("[%c]", ""):match("^%s*(.-)%s*$")
    if name == "" or #name > 96 then return false end
    local state = self:getOrCreateState(placeable)
    state.animalNames[animalIndex] = name
    self:broadcastState(placeable, state)
    return true
end

function Veterinarian:getHusbandries()
    return getHusbandries()
end

function Veterinarian:getOrCreateState(placeable)
    local key = getKey(placeable)
    if key == nil then return nil end
    local state = self.states[key] or {sick = 0, disease = 1}
    local allocator = nil
    if g_server ~= nil then allocator = function() return self:allocateAnimalName() end end
    ensureIndividualState(state, math.max(0, placeable:getNumOfAnimals() or 0), allocator)
    self.states[key] = state
    return state
end

function Veterinarian:broadcastState(placeable, state, connection)
    if state == nil then state = self:getOrCreateState(placeable) end
    if state ~= nil then
        VeterinarianStateEvent.sendEvent(placeable, state.sick, state.disease, false,
            state.sickAnimals, state.animalNames, state.inseminatedAnimals,
            state.inseminatedSubTypes, connection, state.extra)
    end
end

function Veterinarian:runDiseaseCheck()
    for _, placeable in ipairs(getHusbandries()) do
        local numAnimals = math.max(0, placeable:getNumOfAnimals() or 0)
        if numAnimals > 0 then
            local key = getKey(placeable)
            local state = self:getOrCreateState(placeable)
            VeterinarianLife.hour(placeable, state)
            numAnimals = placeable:getNumOfAnimals()
            local extra = VeterinarianLife.ensure(state)
            local newlySick = 0
            for index = 1, numAnimals do
                if not state.sickAnimals[index] then
                    local chance = Veterinarian.BASE_DAILY_CHANCE / 24
                    if (extra.vaccine[index] or 0) > 0 then chance = chance * (1 - VeterinarianLife.VACCINE_EFFECT) end
                    if math.random() < chance then
                        state.sickAnimals[index] = true
                        extra.sickHours[index] = 0
                        newlySick = newlySick + 1
                    end
                end
            end
            ensureIndividualState(state, numAnimals, function() return self:allocateAnimalName() end)
            if newlySick > 0 then
                state.disease = math.random(1, #DISEASES)
                self:announceDisease(placeable, state)
            end
            self:broadcastState(placeable, state)
        end
    end
end

function Veterinarian:announceDisease(placeable, state)
    local template = g_i18n:getText("vet_diseaseDetected")
    notify(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
        string.format(template, state.sick, getName(placeable), DISEASES[state.disease] or DISEASES[1]))
end

function Veterinarian:receiveState(placeable, sick, disease, showNotification, sickAnimals,
        animalNames, inseminatedAnimals, inseminatedSubTypes, extra)
    if placeable == nil then return end
    local state = {
        extra = extra,
        sick = sick,
        disease = disease,
        sickAnimals = sickAnimals or {},
        animalNames = animalNames or {},
        inseminatedAnimals = inseminatedAnimals or {},
        inseminatedSubTypes = inseminatedSubTypes or {}
    }
    ensureIndividualState(state, math.max(0, placeable:getNumOfAnimals() or 0))
    self.states[getKey(placeable)] = state
    if g_inGameMenu ~= nil and g_inGameMenu.pageAnimals ~= nil then
        local frame = g_inGameMenu.pageAnimals
        local shownHusbandry = frame.veterinarianCurrentHusbandry
        if shownHusbandry ~= nil and getKey(shownHusbandry) == getKey(placeable) then
            self:updateAnimalsOverviewStatus(frame, shownHusbandry)
        end
    end
    local actions = VeterinarianActionsDialog.INSTANCE
    if actions ~= nil and actions.isOpen and actions.husbandry == placeable then
        if not actions:refreshAnimals() then actions:onClickBack() end
    end
    if showNotification and sick > 0 then self:announceDisease(placeable, state) end
end

function Veterinarian:syncAllStates(showNotification, connection)
    for _, placeable in ipairs(getHusbandries()) do
        local state = self:getOrCreateState(placeable)
        VeterinarianStateEvent.sendEvent(placeable, state.sick, state.disease, showNotification,
            state.sickAnimals, state.animalNames, state.inseminatedAnimals,
            state.inseminatedSubTypes, connection, state.extra)
    end
end


function Veterinarian:installAnimalsFrameHook()
    if self.animalsFrameHookInstalled or InGameMenuAnimalsFrame == nil or InGameMenuAnimalsFrame.updateConditionDisplay == nil then
        return
    end

    InGameMenuAnimalsFrame.updateConditionDisplay = Utils.appendedFunction(
        InGameMenuAnimalsFrame.updateConditionDisplay,
        function(frame, husbandry)
            if g_veterinarian ~= nil then
                g_veterinarian:updateAnimalsOverviewStatus(frame, resolvePlaceable(husbandry))
            end
        end)
    self.animalsFrameHookInstalled = true
end

local function findOverviewHeading(element)
    if element == nil then return nil end
    if type(element.text) == "string" then
        local text = string.upper(element.text)
        if string.find(text, "STALL%-INFORMATION") ~= nil
                or string.find(text, "HUSBANDRY INFORMATION", 1, true) ~= nil then
            return element
        end
    end
    if element.elements ~= nil then
        for _, child in ipairs(element.elements) do
            local found = findOverviewHeading(child)
            if found ~= nil then return found end
        end
    end
    return nil
end

function Veterinarian:updateAnimalsOverviewStatus(frame, husbandry)
    if frame == nil then return end
    husbandry = resolvePlaceable(husbandry)
    frame.veterinarianCurrentHusbandry = husbandry
    local status = frame.veterinarianOverviewStatus
    if status == nil then
        local heading = findOverviewHeading(frame)
        if heading == nil then
            if not self.overviewAnchorWarningShown then
                Logging.warning("[Veterinarian] Could not find STALL-INFORMATION heading in animals overview")
                self.overviewAnchorWarningShown = true
            end
            return
        end

        status = heading:clone(heading.parent, false, true)
        status.id = "veterinarianOverviewStatus"
        status.name = "veterinarianOverviewStatus"
        status.target = nil
        status.textBold = true
        status:setPosition(heading.position[1], heading.position[2] - heading.size[2] - 0.006)
        status:setSize(math.max(heading.size[1], 0.32), 0.022)
        frame.veterinarianOverviewStatus = status
    end

    local state = husbandry ~= nil and self.states[getKey(husbandry)] or nil
    if state ~= nil and state.sick > 0 then
        status:setText(string.format(g_i18n:getText("vet_statusSick"),
            state.sick, DISEASES[state.disease] or DISEASES[1]))
        self:setStatusColor(status, 0.95, 0.08, 0.08, 1)
    else
        status:setText(g_i18n:getText("vet_statusHealthy"))
        self:setStatusColor(status, 0.45, 0.8, 0.05, 1)
    end
    status:setVisible(true)
end

function Veterinarian:installAnimalScreenHook()
    local screen = g_animalScreen
    if screen == nil or screen.veterinarianHookInstalled then return end
    screen.veterinarianHookInstalled = true
    screen.onOpen = Utils.appendedFunction(screen.onOpen, function(openedScreen)
        if g_veterinarian ~= nil then
            g_veterinarian:addAnimalScreenStatus(openedScreen)
        end
    end)
    screen.onClose = Utils.prependedFunction(screen.onClose, function()
        VeterinarianAnimalList.closeEmbedded(screen)
        if g_veterinarian ~= nil then
            g_inputBinding:removeActionEventsByTarget(g_veterinarian)
        end
    end)
    self.animalScreenHookInstalled = true
end



function Veterinarian:addAnimalScreenStatus(screen)
    if screen == nil or screen.buttonsPanel == nil then return end

    local status = screen.veterinarianStatus
    if status == nil then
        local statusTemplate = screen.targetText
        local targetSelector = screen.targetSelector
        if statusTemplate == nil or targetSelector == nil or targetSelector.parent == nil then
            Logging.warning("[Veterinarian] AnimalScreen has no status text anchor")
            return
        end

        status = statusTemplate:clone(targetSelector.parent, false, true)
        status.id = "veterinarianStatus"
        status.name = "veterinarianStatus"
        status.target = nil
        status.textBold = true
        status.textAlignment = RenderText.ALIGN_CENTER
        status.textVerticalAlignment = TextElement.VERTICAL_ALIGNMENT.MIDDLE
        status:setPosition(targetSelector.position[1], targetSelector.position[2] - targetSelector.size[2] - 0.012)
        status:setSize(targetSelector.size[1], 0.028)
        screen.veterinarianStatus = status
    end

    status:setVisible(true)
    self:updateAnimalScreenStatus(screen)
    screen.buttonsPanel:invalidateLayout()
end


function Veterinarian:onArtificialInseminationSelected(animalIndex, husbandry)
    if husbandry == nil or animalIndex == nil then return end
    local state = self.states[getKey(husbandry)]
    local animalName = state ~= nil and state.animalNames[animalIndex] or g_i18n:getText("vet_defaultAnimal")
    self.inseminationSelection = {husbandry = husbandry, animalIndex = animalIndex}
    local cost = ArtificialInsemination.CALL_OUT_FEE + ArtificialInsemination.COST_PER_ANIMAL
    local text = string.format(g_i18n:getText("vet_inseminationConfirmSingle"),
        animalName, formatMoney(cost))
    YesNoDialog.show(self.onArtificialInseminationConfirm, self, text,
        g_i18n:getText("vet_inseminationTitle"))
end

function Veterinarian:onArtificialInseminationConfirm(confirmed)
    local selection = self.inseminationSelection
    self.inseminationSelection = nil
    if confirmed and selection ~= nil then
        ArtificialInsemination.request(selection.husbandry, selection.animalIndex)
    end
end

function Veterinarian:getAnimalScreenHusbandry(screen)
    if screen ~= nil and screen.isBuyMode and screen.targetItems ~= nil and screen.targetSelector ~= nil then
        local selected = resolvePlaceable(screen.targetItems[screen.targetSelector:getState()])
        if selected ~= nil and selected.spec_husbandryAnimals ~= nil then return selected end
    end
    local controller = screen ~= nil and screen.controller or nil
    local husbandry = controller ~= nil and controller.husbandry or nil
    return resolvePlaceable(husbandry)
end

function Veterinarian:updateAnimalScreenStatus(screen)
    local status = screen ~= nil and screen.veterinarianStatus or nil
    if status == nil then return end
    local selector = screen.targetSelector
    if selector ~= nil then
        -- Leave room for the wrapped stable name and occupancy counter.
        status:setPosition(selector.position[1], selector.position[2] - selector.size[2] - 0.052)
    end

    local husbandry = self:getAnimalScreenHusbandry(screen)
    if husbandry == nil or husbandry.spec_husbandryAnimals == nil then
        status:setText(g_i18n:getText("vet_statusNoHusbandry"))
        self:setStatusColor(status, 0.95, 0.65, 0.05, 1)
        return
    end

    local state = self.states[getKey(husbandry)]
    if state ~= nil and state.sick > 0 then
        status:setText(string.format(g_i18n:getText("vet_statusSick"),
            state.sick, DISEASES[state.disease] or DISEASES[1]))
        self:setStatusColor(status, 0.95, 0.08, 0.08, 1)
    else
        status:setText(g_i18n:getText("vet_statusHealthy"))
        self:setStatusColor(status, 0.45, 0.8, 0.05, 1)
    end
end

function Veterinarian:isChickenHusbandry(husbandry)
    if husbandry == nil then return false end
    local spec = husbandry.spec_husbandryAnimals
    local typeIndex = husbandry.getAnimalTypeIndex ~= nil and husbandry:getAnimalTypeIndex()
        or (spec ~= nil and spec.animalTypeIndex)
    if AnimalType ~= nil and AnimalType.CHICKEN ~= nil and typeIndex == AnimalType.CHICKEN then return true end
    local system = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    local found = false
    for _, cluster in ipairs(husbandry.getClusters ~= nil and husbandry:getClusters() or {}) do
        local index = cluster.subTypeIndex or (cluster.getSubTypeIndex ~= nil and cluster:getSubTypeIndex())
        local subType = system ~= nil and system:getSubTypeByIndex(index) or nil
        local _, chicken = VeterinarianLife.rule(subType)
        if not chicken then return false end
        found = true
    end
    return found
end

function Veterinarian:setStatusColor(status, r, g, b, a)
    status:setTextColor(r, g, b, a)
    if status.setTextSelectedColor ~= nil then status:setTextSelectedColor(r, g, b, a) end
    if status.setTextHighlightedColor ~= nil then status:setTextHighlightedColor(r, g, b, a) end
    if status.setTextDisabledColor ~= nil then status:setTextDisabledColor(r, g, b, a) end
end


function Veterinarian:getAnimalTreatmentEntries(husbandry, state)
    local entries = {}
    local animalSystem = g_currentMission ~= nil and g_currentMission.animalSystem or nil
    local clusters = husbandry.getClusters ~= nil and husbandry:getClusters() or {}
    local singleCost = Veterinarian.CALL_OUT_FEE + Veterinarian.COST_PER_ANIMAL
    local animalIndex = 1

    for _, cluster in ipairs(clusters) do
        local clusterCount = math.max(0, cluster:getNumAnimals() or 0)
        local details, maturity = ArtificialInsemination.getAnimalDetails(cluster)

        for _ = 1, clusterCount do
            local isSick = state.sickAnimals[animalIndex] == true
            if isSick then
                table.insert(entries, {
                    index = animalIndex,
                    title = state.animalNames[animalIndex] or g_i18n:getText("vet_defaultAnimal"),
                    status = string.format(g_i18n:getText("vet_listDisease"), DISEASES[state.disease] or DISEASES[1]),
                    price = formatMoney(singleCost),
                    extraInfo = string.format(g_i18n:getText("vet_treatmentDeadline"), math.max(0, VeterinarianLife.DEATH_HOURS - (VeterinarianLife.ensure(state).sickHours[animalIndex] or 0))),
                    details = details,
                    maturity = maturity,
                    isSick = true
                })
            end
            animalIndex = animalIndex + 1
        end
    end

    local totalAnimals = math.max(0, husbandry:getNumOfAnimals() or 0)
    local unknownDetails, unknownMaturity = ArtificialInsemination.getAnimalDetails(nil)
    while animalIndex <= totalAnimals do
        local isSick = state.sickAnimals[animalIndex] == true
        if isSick then
            table.insert(entries, {
                index = animalIndex,
                title = state.animalNames[animalIndex] or g_i18n:getText("vet_defaultAnimal"),
                status = string.format(g_i18n:getText("vet_listDisease"), DISEASES[state.disease] or DISEASES[1]),
                price = formatMoney(singleCost),
                details = unknownDetails,
                maturity = unknownMaturity,
                isSick = true
            })
        end
        animalIndex = animalIndex + 1
    end
    return entries
end

function Veterinarian:showAnimalTreatmentDialog(husbandry, animalIndex)
    local numAnimals = math.max(0, husbandry:getNumOfAnimals() or 0)
    if numAnimals == 0 then return end
    animalIndex = math.clamp(animalIndex or 1, 1, numAnimals)

    local state = husbandry ~= nil and self.states[getKey(husbandry)] or nil
    if state == nil then return end
    ensureIndividualState(state, numAnimals)

    local line
    if state.sickAnimals[animalIndex] then
        local singleCost = Veterinarian.CALL_OUT_FEE + Veterinarian.COST_PER_ANIMAL
        line = string.format(g_i18n:getText("vet_animalSick"), state.animalNames[animalIndex],
            DISEASES[state.disease] or DISEASES[1], formatMoney(singleCost))
    else
        line = string.format(g_i18n:getText("vet_animalHealthy"), state.animalNames[animalIndex])
    end

    self.treatmentSelection = {
        husbandry = husbandry,
        animalIndex = animalIndex,
        numAnimals = numAnimals
    }
    local text = string.format(g_i18n:getText("vet_animalPosition"), line, animalIndex, numAnimals)
    YesNoDialog.show(self.onAnimalTreatmentYesNo, self, text,
        g_i18n:getText("vet_animalDialogTitle"),
        g_i18n:getText("vet_selectTreatment"),
        g_i18n:getText("vet_nextAnimal"))
end

function Veterinarian:onAnimalTreatmentYesNo(treatSelected)
    local selection = self.treatmentSelection
    if selection == nil then return end

    if not treatSelected then
        local nextIndex = selection.animalIndex % selection.numAnimals + 1
        self:showAnimalTreatmentDialog(selection.husbandry, nextIndex)
        return
    end

    self:onAnimalTreatmentSelected(selection.animalIndex, selection.husbandry)
end

function Veterinarian:onAnimalTreatmentSelected(selectedIndex, husbandry)
    if type(selectedIndex) ~= "number" or selectedIndex < 1 or husbandry == nil then
        return
    end

    local state = self.states[getKey(husbandry)]
    if state == nil or not state.sickAnimals[selectedIndex] then
        InfoDialog.show(g_i18n:getText("vet_selectedAnimalHealthy"))
        return
    end

    VeterinarianEvent.sendEvent(husbandry, selectedIndex)
end

function Veterinarian:forceExistingAnimalsSickForTest()
    local husbandries = getHusbandries()
    if #husbandries == 0 then return end

    local changed = 0
    for _, placeable in ipairs(husbandries) do
        local numAnimals = math.max(0, placeable:getNumOfAnimals() or 0)
        if numAnimals > 0 then
            local key = getKey(placeable)
            local state = self:getOrCreateState(placeable)
            local targetSick = math.max(state.sick, math.max(1, math.ceil(numAnimals * Veterinarian.TEST_SICK_SHARE)))
            for index = 1, math.min(targetSick, numAnimals) do state.sickAnimals[index] = true end
            ensureIndividualState(state, numAnimals, function() return self:allocateAnimalName() end)
            state.disease = math.random(1, #DISEASES)
            self.states[key] = state
            self:broadcastState(placeable, state)
            changed = changed + 1
        end
    end

    if changed > 0 then
        self.testDiseasePending = false
    end
end

function Veterinarian:treatHusbandry(placeable, connection, animalIndex)
    if placeable == nil or placeable.spec_husbandryAnimals == nil then return end
    local key = getKey(placeable)
    local state = self.states[key]
    if state == nil or state.sick <= 0 then return end
    ensureIndividualState(state, math.max(0, placeable:getNumOfAnimals() or 0),
        function() return self:allocateAnimalName() end)
    if animalIndex == nil or animalIndex < 1 or not state.sickAnimals[animalIndex] then return end

    local farmId = placeable:getOwnerFarmId()
    if connection ~= nil and connection.farmId ~= nil and connection.farmId ~= farmId then return end
    local farm = g_farmManager:getFarmById(farmId)
    local cost = Veterinarian.CALL_OUT_FEE + Veterinarian.COST_PER_ANIMAL
    if farm == nil or farm.money < cost then
        if connection ~= nil then
            VeterinarianResultEvent.sendEvent(false, 1, cost, connection)
        else
            self:showTreatmentResult(false, 1, cost)
        end
        return
    end

    local treated = 1
    state.sickAnimals[animalIndex] = nil
    VeterinarianLife.ensure(state).sickHours[animalIndex] = nil
    ensureIndividualState(state, math.max(0, placeable:getNumOfAnimals() or 0))
    g_currentMission:addMoney(-cost, farmId, MoneyType.ANIMAL_UPKEEP or MoneyType.OTHER, true, true)
    self:broadcastState(placeable, state)
    if connection ~= nil then
        VeterinarianResultEvent.sendEvent(true, treated, cost, connection)
    else
        self:showTreatmentResult(true, treated, cost)
    end
end

function Veterinarian:showTreatmentResult(success, count, cost)
    if success then
        notify(FSBaseMission.INGAME_NOTIFICATION_INFO,
            string.format(g_i18n:getText("vet_treated"), count, formatMoney(cost)))
    else
        notify(FSBaseMission.INGAME_NOTIFICATION_CRITICAL,
            string.format(g_i18n:getText("vet_notEnoughMoney"), formatMoney(cost)))
    end
end

function Veterinarian:getSaveFilename()
    if g_currentMission == nil or g_currentMission.missionInfo == nil then return nil end
    local directory = g_currentMission.missionInfo.savegameDirectory
    if directory == nil then return nil end
    return directory .. "/veterinarian.xml"
end

function Veterinarian:saveToXMLFile()
    if g_server == nil then return end
    local filename = self:getSaveFilename()
    if filename == nil then return end
    local xml = createXMLFile("veterinarian", filename, "veterinarian")
    local index = 0
    for key, state in pairs(self.states) do
        if state.animalNames ~= nil and #state.animalNames > 0 then
            local path = string.format("veterinarian.husbandries.husbandry(%d)", index)
            setXMLString(xml, path .. "#key", key)
            setXMLInt(xml, path .. "#sick", state.sick)
            setXMLInt(xml, path .. "#disease", state.disease)
            setXMLString(xml, path .. "#sickAnimals", table.concat(getSickAnimalIndices(state), ","))
            for animalIndex, name in ipairs(state.animalNames) do
                local animalPath = string.format("%s.names.animal(%d)", path, animalIndex - 1)
                setXMLString(xml, animalPath .. "#name", name)
                local extra = VeterinarianLife.ensure(state)
                for _, field in ipairs(VeterinarianLife.FIELDS) do
                    if extra[field][animalIndex] ~= nil then setXMLInt(xml, animalPath .. "#" .. field, extra[field][animalIndex]) end
                end
            end
            local inseminated = {}
            for animalIndex, progress in pairs(state.inseminatedAnimals or {}) do
                table.insert(inseminated, string.format("%d:%d:%d", animalIndex, progress,
                    state.inseminatedSubTypes[animalIndex] or 0))
            end
            table.sort(inseminated)
            setXMLString(xml, path .. "#inseminatedAnimals", table.concat(inseminated, ","))
            index = index + 1
        end
    end
    saveXMLFile(xml)
    delete(xml)
end

function Veterinarian:loadState()
    local filename = self:getSaveFilename()
    if filename == nil or not fileExists(filename) then return end
    local xml = loadXMLFile("veterinarian", filename)
    local index = 0
    while true do
        local path = string.format("veterinarian.husbandries.husbandry(%d)", index)
        local key = getXMLString(xml, path .. "#key")
        if key == nil then break end
        local sickAnimals = {}
        local animalNames = {}
        local inseminatedAnimals = {}
        local inseminatedSubTypes = {}
        local savedIndices = getXMLString(xml, path .. "#sickAnimals")
        if savedIndices ~= nil then
            for value in string.gmatch(savedIndices, "[^,]+") do
                local animalIndex = tonumber(value)
                if animalIndex ~= nil and animalIndex >= 1 then sickAnimals[animalIndex] = true end
            end
        end
        local extra = VeterinarianLife.ensure({})
        local nameIndex = 0
        while true do
            local name = getXMLString(xml, string.format("%s.names.animal(%d)#name", path, nameIndex))
            if name == nil then break end
            animalNames[nameIndex + 1] = name ~= "" and name or self:allocateAnimalName()
            for _, field in ipairs(VeterinarianLife.FIELDS) do
                extra[field][nameIndex + 1] = getXMLInt(xml, string.format("%s.names.animal(%d)#%s", path, nameIndex, field))
            end
            nameIndex = nameIndex + 1
        end
        local savedInseminations = getXMLString(xml, path .. "#inseminatedAnimals")
        if savedInseminations ~= nil then
            for value in string.gmatch(savedInseminations, "[^,]+") do
                local animalIndex, progress, subTypeIndex = string.match(value, "(%d+):(%d+):(%d+)")
                animalIndex = tonumber(animalIndex)
                if animalIndex ~= nil then
                    inseminatedAnimals[animalIndex] = tonumber(progress) or 1
                    inseminatedSubTypes[animalIndex] = tonumber(subTypeIndex) or 0
                end
            end
        end
        self.states[key] = {
            extra = extra,
            sick = math.max(0, getXMLInt(xml, path .. "#sick") or 0),
            disease = math.clamp(getXMLInt(xml, path .. "#disease") or 1, 1, #DISEASES),
            sickAnimals = sickAnimals,
            animalNames = animalNames,
            inseminatedAnimals = inseminatedAnimals,
            inseminatedSubTypes = inseminatedSubTypes
        }
        index = index + 1
    end
    delete(xml)
end

local veterinarian = Veterinarian.new()
addModEventListener(veterinarian)
