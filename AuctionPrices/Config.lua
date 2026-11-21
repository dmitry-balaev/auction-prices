local SELL_WORTH_PERCENT_MIN = 10
local SELL_WORTH_PERCENT_MAX = 200
local SELL_WORTH_PERCENT_STEP = 10

AuctionPrices.SellWorthMarks = {
  Auction = "auction",
  Vendor = "vendor",
  Both = "both",
}

local SELL_WORTH_DEFAULTS = {
  enabled = false,
  percent = 50,
  mark = AuctionPrices.SellWorthMarks.Auction,
}

local SMART_SELL_DEFAULTS = {
  enabled = false,
}

local MARK_OPTIONS = {
  { mark = AuctionPrices.SellWorthMarks.Auction, textKey = "MARK_PROFITABLE_WITH_ICON" },
  { mark = AuctionPrices.SellWorthMarks.Vendor, textKey = "DIM_UNPROFITABLE" },
  { mark = AuctionPrices.SellWorthMarks.Both, textKey = "MARK_BOTH_WAYS" },
}

local PANEL_WIDTH = 560
local PANEL_HEIGHT = 640
local PANEL_PADDING = 16
local SECTION_INDENT = 20
local CONTROL_COLUMN_OFFSET = 250
local ACTION_BUTTON_WIDTH = 160
local ACTION_BUTTON_HEIGHT = 22

local ENABLED_LABEL_FONT = "GameFontNormal"
local DISABLED_LABEL_FONT = "GameFontDisable"
local ENABLED_SLIDER_FONT = "GameFontHighlightSmall"
local DISABLED_SLIDER_FONT = "GameFontDisableSmall"

AuctionPrices.SmartSellEnabledChanged = AuctionPrices.CreateNotifier()

local function FillMissingSettings(groupName, defaults)
  local settings = AUCTION_PRICES_DB.settings[groupName] or {}
  AUCTION_PRICES_DB.settings[groupName] = settings
  for key, defaultValue in pairs(defaults) do
    if settings[key] == nil then
      settings[key] = defaultValue
    end
  end
end

function AuctionPrices.InitializeSettings()
  FillMissingSettings("sellWorth", SELL_WORTH_DEFAULTS)
  FillMissingSettings("smartSell", SMART_SELL_DEFAULTS)
end

function AuctionPrices.GetSellWorthSettings()
  return AUCTION_PRICES_DB.settings.sellWorth
end

function AuctionPrices.GetSmartSellSettings()
  return AUCTION_PRICES_DB.settings.smartSell
end

local lastScanLabel
local priceCountLabel
local clearDatabaseButton
local doNotSellCountLabel
local clearDoNotSellButton
local smartSellCheckbox
local sellWorthCheckbox
local markLabel
local markDropdown
local thresholdLabel
local thresholdSlider

local function SnapPercent(value)
  return math.floor(value / SELL_WORTH_PERCENT_STEP + 0.5) * SELL_WORTH_PERCENT_STEP
end

local function LastScanText()
  local lastScanTime = AuctionPrices.GetRealmPriceDatabase().lastScan
  if not lastScanTime then
    return AuctionPrices.Text("LAST_SCAN_TIME", AuctionPrices.Text("NEVER"))
  end
  return AuctionPrices.Text("LAST_SCAN_TIME", date("%d-%m-%Y %H:%M", lastScanTime))
end

local function MarkOptionText(mark)
  for _, option in ipairs(MARK_OPTIONS) do
    if option.mark == mark then
      return AuctionPrices.Text(option.textKey)
    end
  end
end

local function SetSellWorthControlsEnabled(enabled)
  local labelFont = enabled and ENABLED_LABEL_FONT or DISABLED_LABEL_FONT
  local sliderFont = enabled and ENABLED_SLIDER_FONT or DISABLED_SLIDER_FONT
  markLabel:SetFontObject(labelFont)
  thresholdLabel:SetFontObject(labelFont)
  thresholdSlider.Low:SetFontObject(sliderFont)
  thresholdSlider.High:SetFontObject(sliderFont)
  if enabled then
    UIDropDownMenu_EnableDropDown(markDropdown)
    thresholdSlider:Enable()
  else
    UIDropDownMenu_DisableDropDown(markDropdown)
    thresholdSlider:Disable()
  end
end

local function RefreshDatabaseSection()
  local storedPriceCount = AuctionPrices.CountStoredPrices()
  lastScanLabel:SetText(LastScanText())
  priceCountLabel:SetText(AuctionPrices.Text("STORED_RECORD_COUNT", storedPriceCount))
  clearDatabaseButton:SetEnabled(storedPriceCount > 0)
end

local function RefreshSellWorthSection()
  local sellWorthSettings = AuctionPrices.GetSellWorthSettings()
  sellWorthCheckbox:SetChecked(sellWorthSettings.enabled)
  UIDropDownMenu_SetText(markDropdown, MarkOptionText(sellWorthSettings.mark))
  thresholdSlider:SetValue(sellWorthSettings.percent)
  thresholdLabel:SetText(AuctionPrices.Text("DIFFERENCE_THRESHOLD", sellWorthSettings.percent))
  SetSellWorthControlsEnabled(sellWorthSettings.enabled)
end

local function RefreshSmartSellSection()
  local excludedItemCount = AuctionPrices.CountDoNotSell()
  smartSellCheckbox:SetChecked(AuctionPrices.GetSmartSellSettings().enabled)
  doNotSellCountLabel:SetText(AuctionPrices.Text("NOT_FOR_SALE_COUNT", excludedItemCount))
  clearDoNotSellButton:SetEnabled(excludedItemCount > 0)
end

local function RefreshOptionsPanel()
  RefreshDatabaseSection()
  RefreshSellWorthSection()
  RefreshSmartSellSection()
end

local function ChangeSellWorthSetting(key, value)
  AuctionPrices.GetSellWorthSettings()[key] = value
  RefreshSellWorthSection()
  AuctionPrices.RefreshBagIcons()
end

local function ResetSettings()
  for key, defaultValue in pairs(SELL_WORTH_DEFAULTS) do
    AuctionPrices.GetSellWorthSettings()[key] = defaultValue
  end
  for key, defaultValue in pairs(SMART_SELL_DEFAULTS) do
    AuctionPrices.GetSmartSellSettings()[key] = defaultValue
  end
  RefreshOptionsPanel()
  AuctionPrices.RefreshBagIcons()
  AuctionPrices.SmartSellEnabledChanged.Notify()
end

local function OnSmartSellCheckboxClicked(checkbox)
  AuctionPrices.GetSmartSellSettings().enabled = checkbox:GetChecked()
  AuctionPrices.SmartSellEnabledChanged.Notify()
end

local function OnSellWorthCheckboxClicked(checkbox)
  ChangeSellWorthSetting("enabled", checkbox:GetChecked())
end

local function OnMarkSelected(_, mark)
  ChangeSellWorthSetting("mark", mark)
end

local function InitializeMarkDropdown()
  local selectedMark = AuctionPrices.GetSellWorthSettings().mark
  for _, option in ipairs(MARK_OPTIONS) do
    local optionInfo = UIDropDownMenu_CreateInfo()
    optionInfo.text = AuctionPrices.Text(option.textKey)
    optionInfo.arg1 = option.mark
    optionInfo.checked = selectedMark == option.mark
    optionInfo.func = OnMarkSelected
    UIDropDownMenu_AddButton(optionInfo)
  end
end

local function OnThresholdChanged(slider, value)
  local percent = SnapPercent(value)
  if percent ~= value then
    slider:SetValue(percent)
    return
  end
  if AuctionPrices.GetSellWorthSettings().percent ~= percent then
    ChangeSellWorthSetting("percent", percent)
  end
end

local function CreateText(parent, font, text)
  local label = parent:CreateFontString(nil, "ARTWORK", font)
  label:SetJustifyH("LEFT")
  label:SetText(text)
  return label
end

local function CreateSectionDescription(parent, header, textKey)
  local description = CreateText(parent, "GameFontHighlightSmall", AuctionPrices.Text(textKey))
  description:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -4)
  description:SetWidth(PANEL_WIDTH - PANEL_PADDING * 2)
  description:SetWordWrap(true)
  description:SetSpacing(2)
  local descriptionGray = 0.75
  description:SetTextColor(descriptionGray, descriptionGray, descriptionGray)
  return description
end

local function CreateActionButton(parent, textKey, onClick)
  local button = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  button:SetSize(ACTION_BUTTON_WIDTH, ACTION_BUTTON_HEIGHT)
  button:SetText(AuctionPrices.Text(textKey))
  button:SetScript("OnClick", onClick)
  return button
end

local function CreateCheckbox(parent, label, onClick)
  local checkbox = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  checkbox:SetPoint("LEFT", label, "LEFT", CONTROL_COLUMN_OFFSET, 0)
  checkbox.Text:SetText("")
  checkbox:SetScript("OnClick", onClick)
  return checkbox
end

local function CreateHeader(parent)
  local title = CreateText(parent, "GameFontNormalHuge", "AuctionPrices")
  title:SetPoint("TOPLEFT", PANEL_PADDING, -12)
  title:SetTextColor(1, 1, 1)

  local defaultsButton = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  defaultsButton:SetPoint("TOPRIGHT", -PANEL_PADDING, -10)
  defaultsButton:SetSize(140, 24)
  defaultsButton:SetText(AuctionPrices.Text("DEFAULTS"))
  defaultsButton:SetScript("OnClick", ResetSettings)

  local divider = parent:CreateTexture(nil, "ARTWORK")
  divider:SetColorTexture(0.85, 0.7, 0.35, 0.85)
  divider:SetHeight(1)
  divider:SetPoint("TOPLEFT", 12, -46)
  divider:SetPoint("TOPRIGHT", -12, -46)
end

local function CreateDatabaseSection(parent)
  local databaseHeader = CreateText(parent, "GameFontHighlightLarge", AuctionPrices.Text("DATABASE"))
  databaseHeader:SetPoint("TOPLEFT", PANEL_PADDING, -62)
  local databaseDescription = CreateSectionDescription(parent, databaseHeader, "SAVED_PRICES_COMPARE_VENDOR")

  lastScanLabel = CreateText(parent, "GameFontNormal")
  lastScanLabel:SetPoint("TOPLEFT", databaseDescription, "BOTTOMLEFT", SECTION_INDENT, -12)

  priceCountLabel = CreateText(parent, "GameFontNormal")
  priceCountLabel:SetPoint("TOPLEFT", lastScanLabel, "BOTTOMLEFT", 0, -6)

  clearDatabaseButton = CreateActionButton(parent, "CLEAR_DATABASE", AuctionPrices.ClearStoredPrices)
  clearDatabaseButton:SetPoint("TOPLEFT", priceCountLabel, "BOTTOMLEFT", 0, -12)
end

local function CreateThresholdSlider(parent)
  local slider = CreateFrame("Slider", nil, parent, "OptionsSliderTemplate")
  slider:SetPoint("LEFT", thresholdLabel, "LEFT", CONTROL_COLUMN_OFFSET, 0)
  slider:SetWidth(200)
  slider:SetMinMaxValues(SELL_WORTH_PERCENT_MIN, SELL_WORTH_PERCENT_MAX)
  slider:SetValueStep(SELL_WORTH_PERCENT_STEP)
  slider:SetObeyStepOnDrag(true)
  slider.Text:Hide()
  slider.Low:SetText(SELL_WORTH_PERCENT_MIN .. "%")
  slider.High:SetText(SELL_WORTH_PERCENT_MAX .. "%")
  slider:SetScript("OnValueChanged", OnThresholdChanged)
  return slider
end

local function CreateSellWorthSection(parent)
  local sellWorthHeader = CreateText(parent, "GameFontHighlightLarge", AuctionPrices.Text("AUCTION_PROFITABILITY"))
  sellWorthHeader:SetPoint("TOPLEFT", clearDatabaseButton, "BOTTOMLEFT", -SECTION_INDENT, -22)
  local sellWorthDescription = CreateSectionDescription(parent, sellWorthHeader, "BAG_MARKS_AUCTION_OR_VENDOR")

  local enableLabel = CreateText(parent, ENABLED_LABEL_FONT, AuctionPrices.Text("ENABLE"))
  enableLabel:SetPoint("TOPLEFT", sellWorthDescription, "BOTTOMLEFT", SECTION_INDENT, -14)
  sellWorthCheckbox = CreateCheckbox(parent, enableLabel, OnSellWorthCheckboxClicked)

  markLabel = CreateText(parent, ENABLED_LABEL_FONT, AuctionPrices.Text("HOW_TO_MARK"))
  markLabel:SetPoint("TOPLEFT", enableLabel, "BOTTOMLEFT", 0, -20)

  markDropdown = CreateFrame("Frame", "AuctionPricesSellWorthDropdown", parent, "UIDropDownMenuTemplate")
  markDropdown:SetPoint("LEFT", markLabel, "LEFT", CONTROL_COLUMN_OFFSET - 16, -2)
  UIDropDownMenu_SetWidth(markDropdown, 180)
  UIDropDownMenu_Initialize(markDropdown, InitializeMarkDropdown)

  thresholdLabel = CreateText(parent, ENABLED_LABEL_FONT)
  thresholdLabel:SetPoint("TOPLEFT", markLabel, "BOTTOMLEFT", 0, -24)
  thresholdSlider = CreateThresholdSlider(parent)
end

local function CreateSmartSellSection(parent)
  local smartSellHeader = CreateText(parent, "GameFontHighlightLarge", AuctionPrices.Text("SMART_SELL"))
  smartSellHeader:SetPoint("TOPLEFT", thresholdLabel, "BOTTOMLEFT", -SECTION_INDENT, -28)
  local smartSellDescription = CreateSectionDescription(parent, smartSellHeader, "POST_PROFITABLE_OR_EXCLUDE")

  local enableLabel = CreateText(parent, ENABLED_LABEL_FONT, AuctionPrices.Text("ENABLE"))
  enableLabel:SetPoint("TOPLEFT", smartSellDescription, "BOTTOMLEFT", SECTION_INDENT, -14)
  smartSellCheckbox = CreateCheckbox(parent, enableLabel, OnSmartSellCheckboxClicked)

  doNotSellCountLabel = CreateText(parent, "GameFontNormal")
  doNotSellCountLabel:SetPoint("TOPLEFT", enableLabel, "BOTTOMLEFT", 0, -16)

  clearDoNotSellButton = CreateActionButton(parent, "CLEAR_LIST", AuctionPrices.ClearDoNotSell)
  clearDoNotSellButton:SetPoint("TOPLEFT", doNotSellCountLabel, "BOTTOMLEFT", 0, -12)
end

function AuctionPrices.SetupOptionsPanel()
  local optionsPanel = CreateFrame("Frame")
  optionsPanel:Hide()
  optionsPanel:SetSize(PANEL_WIDTH, PANEL_HEIGHT)

  CreateHeader(optionsPanel)
  CreateDatabaseSection(optionsPanel)
  CreateSellWorthSection(optionsPanel)
  CreateSmartSellSection(optionsPanel)

  optionsPanel:SetScript("OnShow", RefreshOptionsPanel)
  RefreshOptionsPanel()
  AuctionPrices.DatabaseChanged.Register(RefreshDatabaseSection)
  AuctionPrices.DoNotSellChanged.Register(RefreshSmartSellSection)

  local settingsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, "AuctionPrices")
  Settings.RegisterAddOnCategory(settingsCategory)
end
