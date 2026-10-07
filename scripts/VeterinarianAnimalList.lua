-- ============================================================
-- FS25_VeterinarianAnimalList.lua
-- by Marcus (Cobra Modding)
-- 
--
-- Version 1.1.0.0
--
--
-- Keine Änderung am Skript ohne meine Erlaubnis
-- ============================================================
VeterinarianAnimalList = {}
VeterinarianAnimalList.MOD_DIRECTORY = g_currentModDirectory
VeterinarianAnimalList.GREEN = {0.67, 0.86, 0.12, 1}
VeterinarianAnimalList.RED = {1, 0.16, 0.20, 1}

function VeterinarianAnimalList.setFullImage(element, filename, preserveColor)
    local overlay = element.overlay
    if overlay ~= nil then
        for _, suffix in ipairs({"", "Disabled", "Focused", "Selected", "Highlighted", "Pressed"}) do
            overlay["sliceId" .. suffix] = nil
            overlay["maskFilename" .. suffix] = nil
            overlay["filename" .. suffix] = nil
            overlay["uvs" .. suffix] = {unpack(Overlay.DEFAULT_UVS)}
            if not preserveColor then overlay["color" .. suffix] = {1, 1, 1, 1} end
        end
        overlay.alpha = 1
    end
    element:setImageFilename(filename)
end

function VeterinarianAnimalList.getProductionStatus(cluster, extra, index, isSick, husbandry)
    local hidden = {visible=false, active=false, tooYoung=false}
    if cluster == nil then return hidden end
    local system = g_currentMission.animalSystem
    local subType = system:getSubTypeByIndex(cluster.subTypeIndex or cluster:getSubTypeIndex())
    if subType == nil then return hidden end
    local rule = VeterinarianAnimalProfile.product(subType)
    if rule == nil then return hidden end
    local result = {visible=true, label=rule.label, icon=rule.icon, active=false, tooYoung=false}
    if rule.male then return result end
    local minAge = VeterinarianAnimalProfile.productionAge(subType, rule)
    local age = cluster.getAge ~= nil and cluster:getAge() or cluster.age or 0
    result.tooYoung = age < minAge
    if result.tooYoung or rule.sheared then return result end
    local healthy = not isSick and (cluster.health == nil or cluster.health > 0)
    if husbandry ~= nil and husbandry.getProductionFactor ~= nil then
        healthy = healthy and (husbandry:getProductionFactor() or 0) > 0
    end
    local output = rule.output
    local produces = output ~= nil and (output.curve == nil or (output.curve:get(age) or 0) > 0)
    if rule.lactation then
        produces = produces and ((extra and extra.lactation or {})[index] or 0) > 0
    end
    result.active = healthy and (rule.readiness == true or produces)

    return result
end

function VeterinarianAnimalList.getCards(husbandry, state)
    local cards = {}
    if husbandry == nil or state == nil then return cards end
    local extra = VeterinarianLife.ensure(state)
    local index = 0
    for _, cluster in ipairs(husbandry:getClusters() or {}) do
        local subtype = cluster.subTypeIndex or cluster:getSubTypeIndex()
        local age = cluster.getAge ~= nil and cluster:getAge() or cluster.age or 0
        local visual = g_currentMission.animalSystem:getVisualByAge(subtype, age)
        local baseDetails = ArtificialInsemination.getAnimalDetails(cluster)
        for individual = 1, math.max(0, cluster:getNumAnimals() or 0) do
            index = index + 1
            local fertilized = state.inseminatedAnimals[index] ~= nil
            local details = baseDetails
            local lactationMonths = math.max(0, extra.lactation[index] or 0)
            cards[index] = {
                index = index, cluster = cluster, individual = individual,
                title = state.animalNames[index] or g_i18n:getText("vet_defaultAnimal"),
                details = details, image = visual ~= nil and visual.store ~= nil and visual.store.imageFilename or nil,
                isSick = state.sickAnimals[index] == true,
                vaccinated = (extra.vaccine[index] or 0) > 0,
                fertilized = fertilized,
                production = VeterinarianAnimalList.getProductionStatus(cluster, extra, index, state.sickAnimals[index] == true, husbandry),
                young = fertilized and (extra.litter[index] ~= nil and tostring(extra.litter[index]) or "–") or nil,
                birthRemaining = fertilized and ArtificialInsemination.getRemainingPregnancyMonths(state, index, subtype) or nil
            }
        end
    end

    local totalAnimals = husbandry.getNumOfAnimals ~= nil and math.max(0, husbandry:getNumOfAnimals() or 0) or index
    while index < totalAnimals do
        index = index + 1
        local fertilized = state.inseminatedAnimals[index] ~= nil
        local details = ArtificialInsemination.getAnimalDetails(nil)
        local lactationMonths = math.max(0, extra.lactation[index] or 0)
        cards[index] = {
            index = index, cluster = nil, individual = 1,
            title = state.animalNames[index] or g_i18n:getText("vet_defaultAnimal"),
            details = details, image = nil,
            isSick = state.sickAnimals[index] == true,
            vaccinated = (extra.vaccine[index] or 0) > 0,
            fertilized = fertilized,
            production = {visible=false, active=false, tooYoung=false},
            young = fertilized and (extra.litter[index] ~= nil and tostring(extra.litter[index]) or "–") or nil,
            birthRemaining = fertilized and ArtificialInsemination.getRemainingPregnancyMonths(state, index, nil) or nil
        }
    end

    return cards
end

function VeterinarianAnimalList.setTextures(element)
    local name = element.name or element.id or ""
    local textures = {rowTemplate="card", stockRowTemplate="card", embeddedRowTemplate="card", cardHover="hover", healthBadge="badge", healthHeart="heart", youngDivider="white"}
    local texture = textures[name] or textures[element.id] or name:match("^vetTexture_(.+)$")
    if name == "productionBox" then texture = "statBox" end
    if texture ~= nil then VeterinarianAnimalList.setFullImage(element, VeterinarianAnimalList.MOD_DIRECTORY .. "gui/textures/" .. texture .. ".dds", texture == "white") end
    for _, child in ipairs(element.elements or {}) do VeterinarianAnimalList.setTextures(child) end
end

function VeterinarianAnimalList.getManualContentHeight(list)
    if list == nil then return 0 end

    list:invalidateLayout(true)

    local height = 0
    for _, row in ipairs(list.elements or {}) do
        if row ~= nil and row:getIsVisible() then
            local rowHeight = 0
            if row.absSize ~= nil then rowHeight = row.absSize[2] or 0 end
            if rowHeight <= 0 and row.size ~= nil then rowHeight = row.size[2] or 0 end
            local margin = row.margin or {}
            height = height + math.max(0, rowHeight) + (margin[2] or 0) + (margin[4] or 0)
        end
    end

    height = math.max(height, list.maxFlowSize or 0, list.contentSize or 0)
    return height
end

function VeterinarianAnimalList.updateManualSlider(list)
    if list == nil then return end
    local slider = list.veterinarianSlider
    if slider == nil then return end

    local viewport = list.absSize ~= nil and (list.absSize[2] or 0) or 0
    local content = VeterinarianAnimalList.getManualContentHeight(list)
    local maxScroll = math.max(0, content - viewport)
    local scrollY = math.max(0, math.min(list.contentOffsetY or list.veterinarianScrollY or 0, maxScroll))
    list.veterinarianScrollY = scrollY
    list:scrollTo(scrollY, false)

    slider.minValue = 1
    slider.maxValue = 101
    slider.stepSize = 1
    slider.needsSlider = maxScroll > 0

    if slider.setSliderSize ~= nil and content > 0 then
        slider:setSliderSize(math.max(viewport, 0.000001), math.max(content, viewport, 0.000001))
    end

    local ratio = maxScroll > 0 and (scrollY / maxScroll) or 0
    slider:setValue(1 + ratio * 100, true, true)
    slider:setVisible(maxScroll > 0)
    if slider.parent ~= nil then slider.parent:setVisible(maxScroll > 0) end
end

function VeterinarianAnimalList.scrollManual(list, deltaRows)
    if list == nil then return false end

    local viewport = list.absSize ~= nil and (list.absSize[2] or 0) or 0
    local content = VeterinarianAnimalList.getManualContentHeight(list)
    local maxScroll = math.max(0, content - viewport)
    if maxScroll <= 0 then
        list.veterinarianScrollY = 0
        list:scrollTo(0, false)
        VeterinarianAnimalList.updateManualSlider(list)
        return false
    end

    local step = 0
    local first = list.elements ~= nil and list.elements[1] or nil
    if first ~= nil then
        if first.absSize ~= nil then step = first.absSize[2] or 0 end
        if step <= 0 and first.size ~= nil then step = first.size[2] or 0 end
    end
    if step <= 0 then step = viewport * 0.25 end
    if step <= 0 then step = maxScroll / 10 end

    local newY = (list.contentOffsetY or list.veterinarianScrollY or 0) + step * deltaRows
    newY = math.max(0, math.min(newY, maxScroll))
    list.veterinarianScrollY = newY
    list:scrollTo(newY, false)
    VeterinarianAnimalList.updateManualSlider(list)
    return true
end

function VeterinarianAnimalList.manualListMouseEvent(list, posX, posY, isDown, isUp, button, eventUsed)
    if list == nil or not list:getIsVisible() then return eventUsed == true end
    if VeterinarianAnimalList.handleListMouseWheel(list, posX, posY, eventUsed) then
        return true
    end

    local used = GuiElement.mouseEvent(list, posX, posY, isDown, isUp, button, eventUsed)
    return used or g_gui:getIsDialogVisible()
end

function VeterinarianAnimalList.handleListMouseWheel(list, posX, posY, eventUsed)
    if eventUsed or list == nil or not list:getIsVisible() then
        return false
    end

    if list.absPosition == nil or list.absSize == nil then
        return false
    end

    local overList = GuiUtils.checkOverlayOverlap(
        posX, posY,
        list.absPosition[1], list.absPosition[2],
        list.absSize[1], list.absSize[2]
    )
    local slider = list.veterinarianSlider
    if not overList and slider ~= nil and slider:getIsVisible() then
        local box = slider.parent or slider
        overList = GuiUtils.checkOverlayOverlap(posX, posY,
            box.absPosition[1], box.absPosition[2], box.absSize[1], box.absSize[2])
    end

    if not overList then
        return false
    end

    if Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_DOWN) then
        return VeterinarianAnimalList.scrollManual(list, 1)
    elseif Input.isMouseButtonPressed(Input.MOUSE_BUTTON_WHEEL_UP) then
        return VeterinarianAnimalList.scrollManual(list, -1)
    end

    return false
end

function VeterinarianAnimalList.guardScrollBounds(list)
    if list == nil or list.veterinarianBoundsGuard then return end
    list.veterinarianBoundsGuard = true
    local originalInvalidate = list.invalidateLayout
    local function clampBounds(element)
        local axis = element.scrollDirection == "horizontal" and 1 or 2
        local viewport = element.absSize ~= nil and element.absSize[axis] or 0
        element.contentSize = math.max(element.contentSize or 0, viewport)
        element.maxFlowSize = math.max(element.maxFlowSize or 0, viewport)
    end
    list.invalidateLayout = function(element, ...)
        local result = originalInvalidate(element, ...)
        clampBounds(element)
        return result
    end
    clampBounds(list)
end

function VeterinarianAnimalList.configureManualScrolling(list, slider)
    if list == nil then return end

    VeterinarianAnimalList.guardScrollBounds(list)
    list.veterinarianSlider = slider
    list.veterinarianScrollY = 0
    list.flowDirection = "vertical"
    list.numFlows = 1
    list.scrollDirection = "vertical"
    list.contentOffsetX = 0
    list.targetContentOffsetX = 0
    list.contentOffsetY = 0
    list.targetContentOffsetY = 0
    list.isMovingToTarget = false
    list.sliderElement = nil
    list.mouseEvent = VeterinarianAnimalList.manualListMouseEvent

    if slider ~= nil then
        if slider.setDataElement ~= nil then slider:setDataElement(nil) end
        slider.dataElement = nil
        slider.dataElementId = nil
        slider.dataElementName = nil
        slider.direction = SliderElement.DIRECTION_Y
        slider.minValue = 1
        slider.maxValue = 101
        slider.currentValue = 1
        slider.sliderValue = 1
        slider.stepSize = 1
        slider.useStepRounding = false
        slider.dataElement = {
            onSliderValueChanged = function(_, changedSlider, value)
                local content = VeterinarianAnimalList.getManualContentHeight(list)
                local maxScroll = math.max(0, content - list.absSize[2])
                local ratio = math.max(0, math.min(1,
                    (value - changedSlider.minValue) / (changedSlider.maxValue - changedSlider.minValue)))
                list.veterinarianScrollY = ratio * maxScroll
                list:scrollTo(list.veterinarianScrollY, false)
            end
        }
        slider.mouseEvent = function(element, posX, posY, isDown, isUp, button, eventUsed)
            if VeterinarianAnimalList.handleListMouseWheel(list, posX, posY, eventUsed) then return true end
            return SliderElement.mouseEvent(element, posX, posY, isDown, isUp, button, eventUsed)
        end
        if slider.updateSliderLimits ~= nil then slider:updateSliderLimits() end
    end

    list:invalidateLayout(true)
    list:scrollTo(0, false)
    VeterinarianAnimalList.updateManualSlider(list)
end

function VeterinarianAnimalList.resetManualScroll(list)
    if list == nil then return end
    list.veterinarianScrollY = 0
    list:scrollTo(0, false)
    VeterinarianAnimalList.updateManualSlider(list)
end

function VeterinarianAnimalList.closeEmbedded(screen)
    if screen.veterinarianEmbedded ~= nil then screen.veterinarianEmbedded:setVisible(false) end
    for element, visible in pairs(screen.veterinarianHiddenElements or {}) do element:setVisible(visible) end
    screen.veterinarianHiddenElements = nil
end

function VeterinarianAnimalList.onEmbeddedClick(screen, row)
    if row == nil or row.veterinarianAnimalIndex == nil or not screen.isOpen
            or not screen.isBuyMode or g_gui:getIsDialogVisible() then return end
    local husbandry = g_veterinarian:getAnimalScreenHusbandry(screen)
    if husbandry ~= screen.veterinarianEmbeddedHusbandry then return end
    VeterinarianActionsDialog.show(husbandry, row.veterinarianAnimalIndex)
end

function VeterinarianAnimalList.updateEmbedded(screen, dt)
    local original = screen.targetList
    VeterinarianAnimalList.guardScrollBounds(original)
    VeterinarianAnimalList.guardScrollBounds(screen.sourceList)
    local dialog = VeterinarianCardTemplates.INSTANCE
    if original == nil or dialog == nil then return end
    local husbandry = g_veterinarian:getAnimalScreenHusbandry(screen)
    local enabled = screen.isOpen and screen.isBuyMode and screen.targetListContainer:getIsVisible()
        and husbandry ~= nil and husbandry.getOwnerFarmId ~= nil
        and husbandry:getOwnerFarmId() == g_currentMission:getFarmId()
    if not enabled then VeterinarianAnimalList.closeEmbedded(screen); return end
    if screen.veterinarianEmbedded == nil then
        local panel = dialog.embeddedPanelTemplate:clone(original.parent)
        panel:setSize(original.size[1], original.size[2])
        panel:setAbsolutePosition(original.absPosition[1], original.absPosition[2])
        local list = panel:getDescendantByName("embeddedList")
        local sliderBox = panel:getDescendantByName("embeddedSliderBox")
        local slider = panel:getDescendantByName("embeddedSlider")
        list:setSize(panel.size[1] - sliderBox.size[1] * 1.6, panel.size[2])
        sliderBox:setSize(sliderBox.size[1], panel.size[2])
        slider:setSize(slider.size[1], panel.size[2])
        VeterinarianAnimalList.configureManualScrolling(list, slider)
        screen.veterinarianEmbedded = panel
        screen.veterinarianEmbeddedList = list
        screen.veterinarianEmbeddedSlider = slider
    end
    local hidden = screen.veterinarianHiddenElements or {}
    local function hide(element)
        if element ~= nil then
            if hidden[element] == nil then hidden[element] = element:getIsVisible() end
            element:setVisible(false)
        end
    end
    hide(original)
    hide(screen.targetListEmptyText)
    if screen.targetSlider ~= nil then hide(screen.targetSlider.parent or screen.targetSlider) end
    hide(original.parent:getDescendantByName("startClipperTarget"))
    hide(original.parent:getDescendantByName("endClipperTarget"))
    screen.veterinarianHiddenElements = hidden
    screen.veterinarianEmbedded:setVisible(true)
    local list = screen.veterinarianEmbeddedList
    VeterinarianAnimalList.updateHover(list)
    screen.veterinarianEmbeddedTimer = (screen.veterinarianEmbeddedTimer or 0) - dt
    if screen.veterinarianEmbeddedTimer > 0 and husbandry == screen.veterinarianEmbeddedHusbandry then return end
    screen.veterinarianEmbeddedTimer = 250
    local cards = VeterinarianAnimalList.getCards(husbandry, g_veterinarian:getOrCreateState(husbandry))
    local countChanged = #list.elements ~= #cards
    for i = #list.elements, #cards + 1, -1 do list.elements[i]:delete() end
    for index, card in ipairs(cards) do
        local row = list.elements[index]
        if row == nil then
            row = dialog.embeddedRowTemplate:clone(list)
            local ratio = list.size[1] / row.size[1]
            row:setSize(list.size[1], row.size[2])
            for _, child in ipairs(row.elements) do
                child:setPosition(child.position[1] * ratio, child.position[2])
                child:setSize(child.size[1] * ratio, child.size[2])
            end
            row.target = screen
            row.onClickCallback = VeterinarianAnimalList.onEmbeddedClick
        end
        row.veterinarianAnimalIndex = card.index
        VeterinarianAnimalList.fillCard(row, card)
    end
    if countChanged then
        list:invalidateLayout(true)
        VeterinarianAnimalList.updateManualSlider(list)
    end
    if husbandry ~= screen.veterinarianEmbeddedHusbandry then
        VeterinarianAnimalList.resetManualScroll(list)
    end
    screen.veterinarianEmbeddedHusbandry = husbandry
end

function VeterinarianAnimalList.fillCard(row, card)
    local function child(name) return row:getDescendantByName(name) end
    local function colorText(element, color)
        if element == nil then return end
        element:setTextColor(unpack(color))
        for _, method in ipairs({"setTextSelectedColor", "setTextHighlightedColor", "setTextDisabledColor"}) do
            if element[method] ~= nil then element[method](element, unpack(color)) end
        end
    end
    local function colorBitmap(element, color)
        if element == nil then return end
        element:setImageColor(nil, unpack(color))
        if element.overlay ~= nil then
            for _, suffix in ipairs({"", "Disabled", "Focused", "Selected", "Highlighted", "Pressed"}) do
                element.overlay["color" .. suffix] = {unpack(color)}
            end
        end
    end

    child("animalTitle"):setText(card.title)
    child("detailsText"):setText(card.details)

    local icon = child("animalIcon")
    icon:setVisible(card.image ~= nil)
    if card.image ~= nil and icon.veterinarianImage ~= card.image then
        VeterinarianAnimalList.setFullImage(icon, card.image)
        icon.veterinarianImage = card.image
    end

    local healthColor = card.isSick and VeterinarianAnimalList.RED or VeterinarianAnimalList.GREEN
    child("healthText"):setText(g_i18n:getText(card.isSick and "vet_cardSick" or "vet_cardHealthy"))
    colorText(child("healthText"), healthColor)
    colorBitmap(child("healthBadge"), healthColor)
    colorBitmap(child("healthHeart"), healthColor)

    local vaccineLabel = child("vaccineLabel")
    if vaccineLabel ~= nil then vaccineLabel:setText(g_i18n:getText("vet_cardVaccinated")) end
    local fertilityLabel = child("fertilityLabel")
    if fertilityLabel ~= nil then fertilityLabel:setText(g_i18n:getText("vet_cardFertilized")) end
    local milkLabel = child("milkLabel")
    local production = card.production or {visible=false}
    for _, name in ipairs({"productionBox", "milkLabel", "milkValue", "vetTexture_milk"}) do
        local element = child(name)
        if element ~= nil then element:setVisible(production.visible == true) end
    end
    if milkLabel ~= nil and production.visible then milkLabel:setText(g_i18n:getText(production.label)) end
    local productionIcon = child("vetTexture_milk")
    if productionIcon ~= nil then
        productionIcon:setVisible(production.visible == true)
        if production.visible and productionIcon.veterinarianProduct ~= production.icon then
            VeterinarianAnimalList.setFullImage(productionIcon,
                VeterinarianAnimalList.MOD_DIRECTORY .. "gui/textures/" .. (production.icon or "milk") .. ".dds")
            productionIcon.veterinarianProduct = production.icon
        end
    end

    local statuses = {
        {"vaccineValue", "vetTexture_syringe", card.vaccinated},
        {"fertilityValue", "vetTexture_fertility", card.fertilized},
        {"milkValue", "vetTexture_milk", production.active, production.tooYoung}
    }
    for _, field in ipairs(statuses) do
        local value = child(field[1])
        local active = field[3] == true
        local fieldColor = active and VeterinarianAnimalList.GREEN or VeterinarianAnimalList.RED
        if value ~= nil then
            value:setText(g_i18n:getText(field[4] and "vet_tooYoung" or (active and "vet_yes" or "vet_no")))
            colorText(value, fieldColor)
        end
        colorBitmap(child(field[2]), fieldColor)
    end

    child("youngLabel"):setText(g_i18n:getText("vet_cardYoung"))
    child("youngValue"):setText(card.young or "–")
    colorText(child("youngValue"), VeterinarianAnimalList.GREEN)

    local birthText = "–"
    if card.birthRemaining ~= nil then
        if card.birthRemaining <= 0 then
            birthText = g_i18n:getText("vet_cardBirthNow")
        elseif card.birthRemaining == 1 then
            birthText = g_i18n:getText("vet_cardBirthOneMonth")
        else
            birthText = string.format(g_i18n:getText("vet_cardBirthMonths"), card.birthRemaining)
        end
    end
    child("birthLabel"):setText(g_i18n:getText("vet_cardBirthIn"))
    child("birthValue"):setText(birthText)
    colorText(child("birthValue"), VeterinarianAnimalList.GREEN)

    for _, name in ipairs({"vetTexture_statBox", "vetTexture_young", "vetTexture_calendar", "youngLabel", "youngValue", "birthLabel", "birthValue"}) do
        local element = child(name)
        if element ~= nil then element:setVisible(true) end
    end
end

function VeterinarianAnimalList.updateHover(list)
    for _, row in ipairs(list.elements or {}) do
        local hover = row:getDescendantByName("cardHover")
        if hover ~= nil then
            local highlighted = row.getIsHighlighted ~= nil and row:getIsHighlighted() or row.highlighted
            local focused = row.getIsFocused ~= nil and row:getIsFocused() or row.focused
            hover:setVisible(highlighted == true or focused == true or row.veterinarianSelected == true)
        end
    end
end
