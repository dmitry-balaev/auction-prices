if not AuctionPrices or not AuctionPrices.enabled then
  return
end

AuctionPrices.AuctionHouse = {}

local SCAN_BUTTON_WIDTH = 220
local SCAN_BUTTON_HEIGHT = 22
local SCAN_BUTTON_OFFSET_X = 168
local SCAN_BUTTON_OFFSET_Y = 5
local SCAN_BUTTON_FRAME_LEVEL_ABOVE_PARENT = 50
local SCAN_COOLDOWN_CHECK_INTERVAL = 0.5

local scanButton

local function AnchorScanButton()
  local auctionHouseFrame = AuctionHouseFrame
  if not auctionHouseFrame or not scanButton then
    return
  end

  scanButton:SetFrameLevel(auctionHouseFrame:GetFrameLevel() + SCAN_BUTTON_FRAME_LEVEL_ABOVE_PARENT)
  scanButton:ClearAllPoints()
  scanButton:SetPoint("BOTTOMLEFT", auctionHouseFrame, "BOTTOMLEFT", SCAN_BUTTON_OFFSET_X, SCAN_BUTTON_OFFSET_Y)
  scanButton:SetShown(auctionHouseFrame:IsShown())
  AuctionPrices.AuctionHouse.UpdateScanButton()
end

local function PollUntilScanAvailable()
  scanButton.elapsed = 0
  scanButton:SetScript("OnUpdate", function(self, elapsed)
    self.elapsed = self.elapsed + elapsed
    if self.elapsed < SCAN_COOLDOWN_CHECK_INTERVAL then
      return
    end
    self.elapsed = 0
    if AuctionPrices.Scan.CanStart() then
      self:SetScript("OnUpdate", nil)
      AuctionPrices.AuctionHouse.UpdateScanButton()
    end
  end)
end

function AuctionPrices.AuctionHouse.UpdateScanButton()
  if not scanButton then
    return
  end
  local scanCanStart = AuctionPrices.Scan.CanStart()
  scanButton:SetEnabled(scanCanStart)
  if scanButton:IsShown() and not scanCanStart and not AuctionPrices.Scan.IsInProgress() then
    PollUntilScanAvailable()
  else
    scanButton:SetScript("OnUpdate", nil)
  end
end

local function ShowScanButtonTooltip(owner)
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:SetText(AuctionPrices.Text("SCAN_TOOLTIP"), nil, nil, nil, nil, true)
  if AuctionPrices.Scan.IsWaitingForAuctionList() then
    GameTooltip:AddLine(AuctionPrices.Text("FETCHING_TOOLTIP"), 1, 0.82, 0, true)
  elseif not AuctionPrices.Scan.IsInProgress() and not AuctionPrices.Scan.CanStart() then
    GameTooltip:AddLine(AuctionPrices.Scan.CooldownMessage(), 1, 0.82, 0, true)
  end
  GameTooltip:Show()
end

local function SetScanButtonText(statusText)
  if statusText and statusText ~= "" then
    scanButton:SetText(statusText)
  else
    scanButton:SetText(AuctionPrices.Text("SCAN"))
  end
  AuctionPrices.AuctionHouse.UpdateScanButton()
  if GameTooltip:IsOwned(scanButton) then
    ShowScanButtonTooltip(scanButton)
  end
end

local function CreateScanButton(auctionHouseFrame)
  scanButton = CreateFrame("Button", "AuctionPricesScanButton", UIParent, "UIPanelButtonTemplate")
  scanButton:SetFrameStrata("HIGH")
  if scanButton.SetMotionScriptsWhileDisabled then
    scanButton:SetMotionScriptsWhileDisabled(true)
  end
  scanButton:SetText(AuctionPrices.Text("SCAN"))
  scanButton:SetSize(SCAN_BUTTON_WIDTH, SCAN_BUTTON_HEIGHT)
  scanButton:SetScript("OnClick", function()
    AuctionPrices.Scan.Start()
  end)
  scanButton:SetScript("OnEnter", ShowScanButtonTooltip)
  scanButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
  end)

  auctionHouseFrame:HookScript("OnShow", AnchorScanButton)
  auctionHouseFrame:HookScript("OnHide", AnchorScanButton)
  AuctionPrices.Scan.SetStatusCallback(SetScanButtonText)
  AnchorScanButton()
end

function AuctionPrices.AuctionHouse.CreateScanButtonWhenReady()
  local auctionHouseFrame = AuctionHouseFrame
  if scanButton or not auctionHouseFrame then
    return
  end
  CreateScanButton(auctionHouseFrame)
end

local auctionHouseLoadListener = CreateFrame("Frame")
auctionHouseLoadListener:RegisterEvent("ADDON_LOADED")
auctionHouseLoadListener:RegisterEvent("AUCTION_HOUSE_SHOW")
auctionHouseLoadListener:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" and addonName ~= "Blizzard_AuctionHouseUI" then
    return
  end
  AuctionPrices.AuctionHouse.CreateScanButtonWhenReady()
end)
