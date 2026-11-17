if not AuctionPrices or not AuctionPrices.enabled then
  return
end

local optionsPanel
local storedPriceCountText
local lastScanTimeText

local function FormatLastScanLabel()
  local lastScanTime = AuctionPrices.GetRealmPriceDatabase().lastScan
  if not lastScanTime then
    return AuctionPrices.Text("LAST_SCAN", AuctionPrices.Text("NEVER"))
  end
  return AuctionPrices.Text("LAST_SCAN", date("%d-%m-%Y %H:%M", lastScanTime))
end

function AuctionPrices.RefreshOptionsPanel()
  if not storedPriceCountText then
    return
  end
  lastScanTimeText:SetText(FormatLastScanLabel())
  storedPriceCountText:SetText(AuctionPrices.Text("ITEM_COUNT", AuctionPrices.CountStoredPrices()))
end

function AuctionPrices.SetupOptionsPanel()
  if optionsPanel then
    return
  end

  optionsPanel = CreateFrame("Frame")
  optionsPanel.name = "AuctionPrices"
  optionsPanel:Hide()
  optionsPanel:SetSize(500, 140)

  lastScanTimeText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  lastScanTimeText:SetPoint("TOPLEFT", 16, -16)
  lastScanTimeText:SetJustifyH("LEFT")

  storedPriceCountText = optionsPanel:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
  storedPriceCountText:SetPoint("TOPLEFT", lastScanTimeText, "BOTTOMLEFT", 0, -6)
  storedPriceCountText:SetJustifyH("LEFT")

  local clearDatabaseButton = CreateFrame("Button", nil, optionsPanel, "UIPanelButtonTemplate")
  clearDatabaseButton:SetPoint("TOPLEFT", storedPriceCountText, "BOTTOMLEFT", 0, -12)
  clearDatabaseButton:SetSize(160, 22)
  clearDatabaseButton:SetText(AuctionPrices.Text("CLEAR_DB"))
  clearDatabaseButton:SetScript("OnClick", function()
    AuctionPrices.ClearStoredPrices()
  end)

  optionsPanel:SetScript("OnShow", AuctionPrices.RefreshOptionsPanel)
  AuctionPrices.RefreshOptionsPanel()

  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local settingsCategory = Settings.RegisterCanvasLayoutCategory(optionsPanel, "AuctionPrices")
    Settings.RegisterAddOnCategory(settingsCategory)
  end
end

AuctionPrices.RegisterDatabaseChangedCallback(AuctionPrices.RefreshOptionsPanel)
