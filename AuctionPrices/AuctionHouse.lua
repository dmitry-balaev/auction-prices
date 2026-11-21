local SCAN_BUTTON_TEXT_PADDING = 40
local SCAN_BUTTON_HEIGHT = 22
local SCAN_BUTTON_OFFSET_X = 166
local SCAN_BUTTON_OFFSET_Y = 5
local SCAN_BUTTON_FRAME_LEVEL_ABOVE_PARENT = 50
local SCAN_COOLDOWN_CHECK_INTERVAL = 0.5

local scanButton
local UpdateScanButton

local function StopPollingScanCooldown()
  scanButton:SetScript("OnUpdate", nil)
end

local function PollScanCooldown()
  local elapsedSinceCheck = 0
  scanButton:SetScript("OnUpdate", function(_, elapsed)
    elapsedSinceCheck = elapsedSinceCheck + elapsed
    if elapsedSinceCheck < SCAN_COOLDOWN_CHECK_INTERVAL then
      return
    end
    elapsedSinceCheck = 0
    if AuctionPrices.Scan.CanStart() then
      StopPollingScanCooldown()
      UpdateScanButton()
    end
  end)
end

UpdateScanButton = function()
  local scanCanStart = AuctionPrices.Scan.CanStart()
  scanButton:SetEnabled(scanCanStart)
  if scanButton:IsShown() and not scanCanStart and not AuctionPrices.Scan.IsInProgress() then
    PollScanCooldown()
    return
  end
  StopPollingScanCooldown()
end

local function AnchorScanButton()
  scanButton:SetFrameLevel(AuctionHouseFrame:GetFrameLevel() + SCAN_BUTTON_FRAME_LEVEL_ABOVE_PARENT)
  scanButton:ClearAllPoints()
  scanButton:SetPoint("BOTTOMLEFT", AuctionHouseFrame, "BOTTOMLEFT", SCAN_BUTTON_OFFSET_X, SCAN_BUTTON_OFFSET_Y)
  scanButton:SetShown(AuctionHouseFrame:IsShown())
  UpdateScanButton()
end

local function ScanButtonStatusText()
  if AuctionPrices.Scan.IsWaitingForAuctionList() then
    return AuctionPrices.Text("DONT_CLOSE_WHILE_RECEIVING")
  end
  if not AuctionPrices.Scan.IsInProgress() then
    return AuctionPrices.Scan.CooldownMessage()
  end
end

local function ShowScanButtonTooltip(owner)
  if AuctionPrices.Scan.CanStart() then
    GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
    GameTooltip:SetText(AuctionPrices.Text("SCAN_AND_SAVE_PRICES"), nil, nil, nil, nil, true)
    GameTooltip:Show()
    return
  end

  local statusText = ScanButtonStatusText()
  if not statusText then
    GameTooltip:Hide()
    return
  end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(statusText, 1, 0.82, 0, nil, true)
  GameTooltip:Show()
end

local function FitScanButton()
  scanButton:SetWidth(scanButton:GetFontString():GetStringWidth() + SCAN_BUTTON_TEXT_PADDING)
end

local function ShowScanStatus(statusText)
  scanButton:SetText(statusText or AuctionPrices.Text("SCAN"))
  FitScanButton()
  UpdateScanButton()
  if GameTooltip:IsOwned(scanButton) then
    ShowScanButtonTooltip(scanButton)
  end
end

local function CreateScanButton()
  scanButton = CreateFrame("Button", "AuctionPricesScanButton", UIParent, "UIPanelButtonTemplate")
  scanButton:SetFrameStrata("HIGH")
  scanButton:SetMotionScriptsWhileDisabled(true)
  scanButton:SetText(AuctionPrices.Text("SCAN"))
  scanButton:SetHeight(SCAN_BUTTON_HEIGHT)
  FitScanButton()
  scanButton:SetScript("OnClick", AuctionPrices.Scan.Start)
  scanButton:SetScript("OnEnter", ShowScanButtonTooltip)
  scanButton:SetScript("OnLeave", GameTooltip_Hide)

  AuctionHouseFrame:HookScript("OnShow", AnchorScanButton)
  AuctionHouseFrame:HookScript("OnHide", AnchorScanButton)
  AuctionPrices.Scan.SetStatusCallback(ShowScanStatus)
  AnchorScanButton()
end

AuctionPrices.AuctionHouseUILoaded.Register(CreateScanButton)
