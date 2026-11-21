local SLOT_SIZE = 37
local PREVIEW_ICON_SIZE = 44
local SLOT_GAP = 4
local BAG_PADDING = 10
local PAGE_LEFT = 6
local PAGE_RIGHT = 6
local PAGE_TOP = -32
local PAGE_BOTTOM = 28
local SECTION_TAB_TOP = -43
local LIST_TOP = -41
local ITEM_HEADER_HEIGHT = 72
local ITEM_HEADER_PADDING = 14
local PREVIEW_HEIGHT = ITEM_HEADER_HEIGHT + ITEM_HEADER_PADDING * 2
local PREVIEW_GAP = 4
local PREVIEW_BOTTOM_SPACE = PREVIEW_HEIGHT + PREVIEW_GAP
local PREVIEW_TEXT_GAP = 10
local PREVIEW_PRICE_GAP = 16
local TOTAL_BELOW_DURATION = 12
local DURATION_DROPDOWN_OVERFLOW = 27
local LEFT_TAB_OFFSET = 44
local RIGHT_TAB_OFFSET = 8
local LIST_BACKGROUND = "auctionhouse-background-index"
local HINT_GRAY = 0.75
local POST_BUTTON_TEXT_PADDING = 40
local POST_BUTTON_HEIGHT = 22
local TAB_PADDING = 20
local MIN_TAB_WIDTH = 70
local TAB_BOTTOM_OFFSET = -28
local TAB_RIGHT_OFFSET = -20
local SMART_SELL_FRAME_KEY = "AuctionPricesSmartSell"

local page
local postButton
local relevantList
local excludedList
local relevantTotalLabel
local itemHeader
local headerContent
local previewIcon
local previewLotLabel
local previewName
local previewPrice
local previewDeposit
local previewDuration
local previewEmptyNotice
local smartSellTab
local smartSellMode
local relevantEntries = {}
local waitingForItemData = false
local refreshQueued = false

local function SplitWorthAuctionSlots()
  local relevant = {}
  local excluded = {}
  local excludedPriceKeys = {}
  local slots, slotsWaitingForItemData = AuctionPrices.CollectWorthAuctionSlots()
  for _, slot in ipairs(slots) do
    local priceKey = AuctionPrices.PrimaryPriceKey(slot.itemLink)
    if not AuctionPrices.IsDoNotSell(slot.itemLink) then
      table.insert(relevant, slot)
    elseif not excludedPriceKeys[priceKey] then
      excludedPriceKeys[priceKey] = true
      table.insert(excluded, slot)
    end
  end
  return relevant, excluded, slotsWaitingForItemData
end

local function ShowPostButtonTooltip(owner)
  if not owner:IsEnabled() then
    GameTooltip:Hide()
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(AuctionPrices.Text("POST_CURRENT_LOT"), nil, nil, nil, nil, true)
  GameTooltip:Show()
end

local function UpdatePostButton()
  if not postButton then
    return
  end
  local checkingPrices = AuctionPrices.Scan.IsInProgress() or AuctionPrices.BagPrices.IsChecking()
  local labelKey = checkingPrices and "CHECKING_PRICES" or "POST"
  if postButton.labelKey ~= labelKey then
    postButton.labelKey = labelKey
    postButton:SetText(AuctionPrices.Text(labelKey))
    postButton:SetWidth(postButton:GetFontString():GetStringWidth() + POST_BUTTON_TEXT_PADDING)
  end
  local hasLots = AuctionPrices.Posting.IsActive() or #relevantEntries > 0
  postButton:SetEnabled(
    not checkingPrices
      and page:IsShown()
      and hasLots
      and C_AuctionHouse.IsThrottledMessageSystemReady()
      and not AuctionPrices.Posting.IsWaitingForServer()
  )
  if GameTooltip:IsOwned(postButton) then
    ShowPostButtonTooltip(postButton)
  end
end

local function ScrollList(scroll, delta)
  local offset = scroll:GetVerticalScroll() - delta * (SLOT_SIZE + SLOT_GAP)
  scroll:SetVerticalScroll(math.min(math.max(offset, 0), scroll:GetVerticalScrollRange()))
end

local function ColumnCount(scroll)
  return math.max(math.floor((scroll:GetWidth() + SLOT_GAP) / (SLOT_SIZE + SLOT_GAP)), 1)
end

local function OnSlotClick(button, mouseButton)
  if button.excludedFromSale then
    AuctionPrices.RemoveDoNotSell(button.itemLink)
    return
  end
  if mouseButton == "LeftButton" then
    AuctionPrices.Posting.ChooseForSale({ bagID = button.bagID, slotID = button.slotID, itemLink = button.itemLink })
    return
  end
  AuctionPrices.AddDoNotSell(button.itemLink)
end

local function OnSlotEnter(button)
  GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
  if button.excludedFromSale then
    GameTooltip:SetText(AuctionPrices.Text("CLICK_RETURNS_TO_SALE"), nil, nil, nil, nil, true)
  else
    GameTooltip:SetText(AuctionPrices.Text("LEFT_CLICK_POSTS_ITEM"), nil, nil, nil, nil, true)
    GameTooltip:AddLine(AuctionPrices.Text("RIGHT_CLICK_EXCLUDES_ITEM"), nil, nil, nil, true)
  end
  GameTooltip:Show()
end

local function CreateSlotButton(list)
  local button = CreateFrame("ItemButton", nil, list.content)
  button:SetSize(SLOT_SIZE, SLOT_SIZE)
  local slotBackground = button:CreateTexture(nil, "BACKGROUND")
  slotBackground:SetAtlas("bags-item-slot64")
  slotBackground:SetAllPoints()
  local currentLotGlow = button:CreateTexture(nil, "OVERLAY", nil, 7)
  currentLotGlow:SetTexture("Interface\\Buttons\\CheckButtonHilight")
  currentLotGlow:SetBlendMode("ADD")
  currentLotGlow:SetAllPoints()
  currentLotGlow:Hide()
  button.currentLotGlow = currentLotGlow
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:SetScript("OnClick", OnSlotClick)
  button:SetScript("OnEnter", OnSlotEnter)
  button:SetScript("OnLeave", GameTooltip_Hide)
  button:SetScript("OnMouseWheel", function(_, delta)
    ScrollList(list.scroll, delta)
  end)
  table.insert(list.buttons, button)
  return button
end

local function ShowSlotItem(button, slot, stackCount)
  local slotKey = slot.bagID .. ":" .. slot.slotID .. ":" .. slot.itemLink
  if button.slotKey ~= slotKey then
    button.slotKey = slotKey
    button:SetItemLocation(ItemLocation:CreateFromBagAndSlot(slot.bagID, slot.slotID))
  end
  button.bagID = slot.bagID
  button.slotID = slot.slotID
  button.itemLink = slot.itemLink
  button:SetItemButtonCount(stackCount)
end

local function PlaceSlotButton(list, button, index, columns)
  local column = (index - 1) % columns
  local row = math.floor((index - 1) / columns)
  button.excludedFromSale = list.excludedFromSale
  button:ClearAllPoints()
  button:SetPoint("TOPLEFT", list.content, "TOPLEFT", column * (SLOT_SIZE + SLOT_GAP), -row * (SLOT_SIZE + SLOT_GAP))
  button:Show()
end

local function HideSpareButtons(list, usedCount)
  for index = usedCount + 1, #list.buttons do
    local button = list.buttons[index]
    button.slotKey = nil
    button:Hide()
  end
end

local function ResizeListContent(list, entryCount, columns)
  local rows = math.ceil(entryCount / columns)
  local height = math.max(rows * SLOT_SIZE + (rows - 1) * SLOT_GAP, 1)
  list.content:SetSize(math.max(list.scroll:GetWidth(), 1), height)
  list.scroll:SetVerticalScroll(math.min(list.scroll:GetVerticalScroll(), list.scroll:GetVerticalScrollRange()))
end

local function ShowEntries(list, slots)
  local columns = ColumnCount(list.scroll)
  for index, slot in ipairs(slots) do
    local button = list.buttons[index] or CreateSlotButton(list)
    ShowSlotItem(button, slot, list.excludedFromSale and 0 or slot.stackCount)
    PlaceSlotButton(list, button, index, columns)
  end
  HideSpareButtons(list, #slots)
  ResizeListContent(list, #slots, columns)
end

local function FitLotCaption()
  local widestLine = 1
  for line in AuctionPrices.Text("LOT_BEING_POSTED"):gmatch("[^\n]+") do
    previewLotLabel:SetText(line)
    widestLine = math.max(widestLine, previewLotLabel:GetStringWidth())
  end
  previewLotLabel:SetText(AuctionPrices.Text("LOT_BEING_POSTED"))
  previewLotLabel:SetWidth(widestLine + 2)
  return widestLine + 2
end

local function FitItemHeaderContent()
  local headerWidth = itemHeader:GetWidth()
  if headerWidth < 1 then
    return
  end
  local lotCaptionWidth = FitLotCaption()
  previewName:SetWidth(1000)
  local priceWidth = previewPrice:GetStringWidth() + PREVIEW_PRICE_GAP + previewDeposit:GetStringWidth()
  local leadWidth = lotCaptionWidth + PREVIEW_TEXT_GAP
  local maxTextWidth = headerWidth - 24 - leadWidth - PREVIEW_ICON_SIZE - PREVIEW_TEXT_GAP
  local textWidth = math.min(math.max(previewName:GetStringWidth(), priceWidth), maxTextWidth)
  previewName:SetWidth(math.max(textWidth, 1))
  headerContent:SetWidth(leadWidth + PREVIEW_ICON_SIZE + PREVIEW_TEXT_GAP + textWidth)
end

local function ShowPreviewLotArea(shown)
  itemHeader:SetShown(shown)
  previewDuration:SetShown(shown)
  relevantTotalLabel:SetShown(shown)
  previewEmptyNotice:SetShown(not shown)
end

local function ShowPreviewItem(itemLink, quantity)
  local itemName, _, itemQuality, _, _, _, _, _, _, itemIcon = C_Item.GetItemInfo(itemLink)
  SetItemButtonTexture(previewIcon, itemIcon)
  SetItemButtonQuality(previewIcon, itemQuality, itemLink)
  SetItemButtonCount(previewIcon, quantity)
  if itemName then
    previewName:SetText(ITEM_QUALITY_COLORS[itemQuality].hex .. itemName .. "|r")
  else
    previewName:SetText(itemLink)
  end
end

local function ShowCurrentLotTooltip()
  if not previewIcon.bagID then
    return
  end
  GameTooltip:SetOwner(previewIcon, "ANCHOR_RIGHT")
  GameTooltip:SetBagItem(previewIcon.bagID, previewIcon.slotID)
  GameTooltip:Show()
end

local function ShowPreviewLot(lot)
  ShowPreviewItem(lot.itemLink, lot.quantity)
  local stackPrice = lot.unitPrice * lot.quantity
  local priceText = stackPrice > 0 and AuctionPrices.FormatMoney(stackPrice) or AuctionPrices.Text("UNKNOWN")
  previewPrice:SetText(AuctionPrices.Text("PRICE", priceText))
  previewDeposit:SetText(AuctionPrices.Text("DEPOSIT", AuctionPrices.FormatMoney(lot.deposit)))
end

local function ShowUnknownLot()
  SetItemButtonTexture(previewIcon, nil)
  SetItemButtonQuality(previewIcon, nil)
  SetItemButtonCount(previewIcon, nil)
  previewName:SetText(AuctionPrices.Text("NO_ITEM"))
  previewPrice:SetText(AuctionPrices.Text("PRICE", AuctionPrices.Text("UNKNOWN")))
  previewDeposit:SetText(AuctionPrices.Text("DEPOSIT", AuctionPrices.Text("UNKNOWN")))
end

local function HighlightCurrentLot(slot)
  for _, button in ipairs(relevantList.buttons) do
    local isCurrentLot = slot ~= nil
      and button:IsShown()
      and button.bagID == slot.bagID
      and button.slotID == slot.slotID
    button.currentLotGlow:SetShown(isCurrentLot)
  end
end

local function RefreshPreview()
  local slot = AuctionPrices.Posting.GetCurrentSlot()
    or AuctionPrices.Posting.ChosenAmong(relevantEntries)
    or relevantEntries[1]
  HighlightCurrentLot(slot)
  previewIcon.bagID = slot and slot.bagID
  previewIcon.slotID = slot and slot.slotID
  local lot = slot and AuctionPrices.Posting.DescribeLot(slot)
  ShowPreviewLotArea(lot ~= nil or waitingForItemData)
  if lot then
    ShowPreviewLot(lot)
  else
    ShowUnknownLot()
  end
  FitItemHeaderContent()
end

local function TotalStackValue(slots)
  local totalValue = 0
  for _, slot in ipairs(slots) do
    totalValue = totalValue + AuctionPrices.GetStoredUnitPrice(slot.itemLink) * slot.stackCount
  end
  return totalValue
end

local function RefreshLists()
  if not page or not page:IsShown() then
    return
  end
  local relevant, excluded
  relevant, excluded, waitingForItemData = SplitWorthAuctionSlots()
  relevantEntries = relevant
  relevantTotalLabel:SetText(AuctionPrices.Text("TOTAL_SALE_VALUE", AuctionPrices.FormatMoney(TotalStackValue(relevant))))
  ShowEntries(relevantList, relevant)
  ShowEntries(excludedList, excluded)
  UpdatePostButton()
  RefreshPreview()
end

local function QueueRefreshLists()
  if refreshQueued or not page or not page:IsShown() then
    return
  end
  refreshQueued = true
  C_Timer.After(0, function()
    refreshQueued = false
    RefreshLists()
  end)
end

local function CreateListBackground(parent)
  local background = CreateFrame("Frame", nil, parent)
  background.layoutType = "InsetFrameTemplate"

  local texture = background:CreateTexture(nil, "BACKGROUND")
  texture:SetAtlas(LIST_BACKGROUND)
  texture:SetPoint("TOPLEFT", 3, -3)
  texture:SetPoint("BOTTOMRIGHT", -3, 3)

  local border = CreateFrame("Frame", nil, background, "NineSlicePanelTemplate")
  border:SetAllPoints()
  return background
end

local function CreatePreviewText(fontObject)
  local text = headerContent:CreateFontString(nil, "OVERLAY", fontObject)
  text:SetJustifyH("LEFT")
  return text
end

local function CreateItemHeader(preview)
  itemHeader = CreateFrame("Frame", nil, preview)
  itemHeader:SetPoint("TOPLEFT", preview, "TOPLEFT", ITEM_HEADER_PADDING, -ITEM_HEADER_PADDING)
  itemHeader:SetPoint("BOTTOMRIGHT", preview, "BOTTOM", -ITEM_HEADER_PADDING, ITEM_HEADER_PADDING)
  itemHeader:SetFrameLevel(preview:GetFrameLevel() + 2)
  local headerTexture = itemHeader:CreateTexture(nil, "BACKGROUND")
  headerTexture:SetAtlas("auctionhouse-itemheaderframe")
  headerTexture:SetAllPoints()

  headerContent = CreateFrame("Frame", nil, itemHeader)
  headerContent:SetPoint("CENTER")
  headerContent:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)

  previewIcon = CreateFrame("Button", nil, headerContent, "GiantItemButtonTemplate")
  previewIcon:SetSize(PREVIEW_ICON_SIZE, PREVIEW_ICON_SIZE)
  previewIcon.Icon:SetSize(PREVIEW_ICON_SIZE - 4, PREVIEW_ICON_SIZE - 4)
  previewIcon.EmptyBackground:SetAllPoints()
  previewLotLabel = CreatePreviewText("GameFontNormal")
  previewLotLabel:SetPoint("LEFT")
  previewLotLabel:SetJustifyH("RIGHT")
  previewLotLabel:SetJustifyV("MIDDLE")
  previewLotLabel:SetWordWrap(true)
  previewLotLabel:SetText(AuctionPrices.Text("LOT_BEING_POSTED"))

  previewIcon:SetPoint("LEFT", previewLotLabel, "RIGHT", PREVIEW_TEXT_GAP, 0)
  previewIcon:RegisterForDrag()
  previewIcon:SetScript("OnDragStart", nil)
  previewIcon:SetScript("OnReceiveDrag", nil)
  previewIcon:SetScript("OnEnter", ShowCurrentLotTooltip)
  previewIcon:SetScript("OnLeave", GameTooltip_Hide)

  previewName = CreatePreviewText("SystemFont_Shadow_Med2")
  previewName:SetPoint("TOPLEFT", previewIcon, "TOPRIGHT", PREVIEW_TEXT_GAP, -2)
  previewName:SetWordWrap(false)

  previewPrice = CreatePreviewText("GameFontNormal")
  previewPrice:SetPoint("BOTTOMLEFT", previewIcon, "BOTTOMRIGHT", PREVIEW_TEXT_GAP, 0)

  previewDeposit = CreatePreviewText("GameFontNormal")
  previewDeposit:SetPoint("BOTTOMLEFT", previewPrice, "BOTTOMRIGHT", PREVIEW_PRICE_GAP, 0)
  itemHeader:SetScript("OnSizeChanged", FitItemHeaderContent)
end

local function CreateDurationDropdown(preview)
  local rightHalf = CreateFrame("Frame", nil, preview)
  rightHalf:SetPoint("TOPLEFT", preview, "TOP")
  rightHalf:SetPoint("BOTTOMRIGHT", preview, "BOTTOMRIGHT")

  previewDuration = CreateFrame("Frame", nil, preview, "AuctionHouseAlignedDurationTemplate")
  previewDuration:SetLabel(AUCTION_HOUSE_DURATION_LABEL)
  previewDuration:SetPoint("CENTER", rightHalf, "CENTER", -DURATION_DROPDOWN_OVERFLOW / 2, 12)
  previewDuration:SetFrameLevel(preview:GetFrameLevel() + 5)

  relevantTotalLabel = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  relevantTotalLabel:SetPoint("TOP", previewDuration, "BOTTOM", DURATION_DROPDOWN_OVERFLOW / 2, -TOTAL_BELOW_DURATION)
  relevantTotalLabel:SetWidth(260)
  relevantTotalLabel:SetJustifyH("CENTER")
  relevantTotalLabel:SetWordWrap(false)
  relevantTotalLabel:SetText(AuctionPrices.Text("TOTAL_SALE_VALUE", AuctionPrices.FormatMoney(0)))
end

local function CreateEmptyNotice(preview)
  previewEmptyNotice = preview:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  previewEmptyNotice:SetPoint("LEFT", preview, "LEFT", ITEM_HEADER_PADDING, 0)
  previewEmptyNotice:SetPoint("RIGHT", preview, "RIGHT", -ITEM_HEADER_PADDING, 0)
  previewEmptyNotice:SetJustifyH("CENTER")
  previewEmptyNotice:SetJustifyV("MIDDLE")
  previewEmptyNotice:SetWordWrap(true)
  previewEmptyNotice:SetText(AuctionPrices.Text("NO_PROFITABLE_ITEMS"))
  previewEmptyNotice:Hide()
end

local function CreatePreview(parent)
  local preview = CreateListBackground(parent)
  preview:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", 0, 0)
  preview:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, 0)
  preview:SetHeight(PREVIEW_HEIGHT)
  function preview:OnDurationUpdated()
    RefreshPreview()
  end

  CreateItemHeader(preview)
  CreateDurationDropdown(preview)
  CreateEmptyNotice(preview)
end

local function CreateSectionTab(parent, inset, titleKey, anchorPoint, offsetX)
  local tab = CreateFrame("Button", nil, parent, "AuctionHouseFrameTopTabTemplate")
  tab:SetText(AuctionPrices.Text(titleKey))
  PanelTemplates_TabResize(tab, TAB_PADDING, nil, MIN_TAB_WIDTH)
  tab:SetPoint("TOPLEFT", parent:GetParent(), anchorPoint, offsetX, SECTION_TAB_TOP)
  tab:SetFrameLevel(inset:GetFrameLevel() + 5)
  PanelTemplates_SelectTab(tab)
end

local function CreateItemScroll(inset, bottomInset, excludedFromSale)
  local list = { buttons = {}, excludedFromSale = excludedFromSale }
  list.scroll = CreateFrame("ScrollFrame", nil, inset)
  list.scroll:SetPoint("TOPLEFT", inset, "TOPLEFT", BAG_PADDING, -BAG_PADDING)
  list.scroll:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -BAG_PADDING, BAG_PADDING + bottomInset)
  list.scroll:EnableMouseWheel(true)
  list.scroll:SetScript("OnMouseWheel", ScrollList)
  list.content = CreateFrame("Frame", nil, list.scroll)
  list.content:SetSize(1, 1)
  list.scroll:SetScrollChild(list.content)
  return list
end

local function CreateListHint(inset, textKey)
  local hint = inset:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  hint:SetPoint("BOTTOMLEFT", inset, "BOTTOMLEFT", 16, 12)
  hint:SetPoint("BOTTOMRIGHT", inset, "BOTTOMRIGHT", -16, 12)
  hint:SetJustifyH("CENTER")
  hint:SetWordWrap(true)
  hint:SetTextColor(HINT_GRAY, HINT_GRAY, HINT_GRAY)
  hint:SetText(AuctionPrices.Text(textKey))
end

local function CreateRelevantList(parent)
  local inset = CreateListBackground(parent)
  inset:SetPoint("TOPLEFT", parent, "TOPLEFT", 0, LIST_TOP)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOM", 0, PREVIEW_BOTTOM_SPACE)
  CreateSectionTab(parent, inset, "PROFITABLE_QUEUE", "TOPLEFT", PAGE_LEFT + LEFT_TAB_OFFSET)
  CreateListHint(inset, "MORE_PROFITABLE_ON_AUCTION")
  relevantList = CreateItemScroll(inset, 36, false)
end

local function CreateExcludedList(parent)
  local inset = CreateListBackground(parent)
  inset:SetPoint("TOPLEFT", parent, "TOP", 0, LIST_TOP)
  inset:SetPoint("BOTTOMRIGHT", parent, "BOTTOMRIGHT", 0, PREVIEW_BOTTOM_SPACE)
  CreateSectionTab(parent, inset, "NOT_FOR_SALE", "TOP", RIGHT_TAB_OFFSET)
  CreateListHint(inset, "EXCLUDED_FROM_POSTING")
  excludedList = CreateItemScroll(inset, 36, true)
end

local function OnPostButtonClicked()
  if AuctionPrices.Posting.IsActive() then
    AuctionPrices.Posting.PostNext()
    return
  end
  AuctionPrices.Posting.Start()
end

local function CreatePostButton()
  postButton = CreateFrame("Button", nil, page, "UIPanelButtonTemplate")
  postButton:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -6, 6)
  postButton:SetText(AuctionPrices.Text("POST"))
  postButton:SetSize(postButton:GetFontString():GetStringWidth() + POST_BUTTON_TEXT_PADDING, POST_BUTTON_HEIGHT)
  postButton:SetScript("OnClick", OnPostButtonClicked)
  postButton:SetScript("OnEnter", ShowPostButtonTooltip)
  postButton:SetScript("OnLeave", GameTooltip_Hide)
end

local function CreatePage()
  page = CreateFrame("Frame", nil, AuctionHouseFrame)
  page:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPLEFT", PAGE_LEFT, PAGE_TOP)
  page:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", -PAGE_RIGHT, PAGE_BOTTOM)
  page:Hide()

  CreatePreview(page)
  CreateRelevantList(page)
  CreateExcludedList(page)
  CreatePostButton()

  page:SetScript("OnShow", function()
    C_Timer.After(0, RefreshLists)
  end)
  page:SetScript("OnHide", AuctionPrices.Posting.Stop)
  AuctionHouseFrame[SMART_SELL_FRAME_KEY] = page
end

local function ApplySmartSellEnabled()
  local enabled = AuctionPrices.GetSmartSellSettings().enabled
  if not enabled then
    AuctionPrices.Posting.Stop()
  end
  if not smartSellTab then
    return
  end
  smartSellTab:SetShown(enabled)
  if not enabled and AuctionHouseFrame:GetDisplayMode() == smartSellMode then
    AuctionHouseFrame:SetDisplayMode(AuctionHouseFrameDisplayMode.Buy)
  end
end

local function CreateTab()
  smartSellMode = { SMART_SELL_FRAME_KEY }
  AuctionHouseFrameDisplayMode.SmartSell = smartSellMode

  smartSellTab = CreateFrame("Button", "AuctionPricesSmartSellTab", AuctionHouseFrame, "AuctionHouseFrameDisplayModeTabTemplate")
  smartSellTab:SetText(AuctionPrices.Text("SMART_SELL"))
  smartSellTab.displayMode = smartSellMode
  PanelTemplates_TabResize(smartSellTab, TAB_PADDING, nil, MIN_TAB_WIDTH)
  smartSellTab:ClearAllPoints()
  smartSellTab:SetPoint("BOTTOMRIGHT", AuctionHouseFrame, "BOTTOMRIGHT", TAB_RIGHT_OFFSET, TAB_BOTTOM_OFFSET)
  smartSellTab:SetFrameLevel(AuctionHouseFrame.BuyTab:GetFrameLevel())

  AuctionHouseFrame.numTabs = #AuctionHouseFrame.Tabs
  AuctionHouseFrame.tabsForDisplayMode[smartSellMode] = AuctionHouseFrame.numTabs
  PanelTemplates_UpdateTabs(AuctionHouseFrame)
  ApplySmartSellEnabled()

  hooksecurefunc(AuctionHouseFrame, "UpdateTitle", function(frame)
    if frame:GetDisplayMode() == smartSellMode then
      frame:SetTitle(AUCTION_HOUSE_FRAME_TITLE_SELL)
    end
  end)
end

AuctionPrices.AuctionHouseUILoaded.Register(function()
  CreatePage()
  CreateTab()
end)

local smartSellListener = CreateFrame("Frame")
smartSellListener:RegisterEvent("AUCTION_HOUSE_CLOSED")
smartSellListener:RegisterEvent("AUCTION_HOUSE_THROTTLED_MESSAGE_SENT")
smartSellListener:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
smartSellListener:RegisterEvent("BAG_UPDATE_DELAYED")
smartSellListener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
smartSellListener:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_CLOSED" then
    relevantEntries = {}
  elseif event == "AUCTION_HOUSE_THROTTLED_MESSAGE_SENT" or event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    UpdatePostButton()
  elseif event == "BAG_UPDATE_DELAYED" or (event == "ITEM_DATA_LOAD_RESULT" and waitingForItemData) then
    QueueRefreshLists()
  end
end)

AuctionPrices.Posting.SetActivityCallback(RefreshLists)
AuctionPrices.PriceCheckChanged.Register(UpdatePostButton)
AuctionPrices.SmartSellEnabledChanged.Register(ApplySmartSellEnabled)
AuctionPrices.DatabaseChanged.Register(RefreshLists)
AuctionPrices.DoNotSellChanged.Register(RefreshLists)
