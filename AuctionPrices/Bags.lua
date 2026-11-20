AuctionPrices.Bags = {}

local AUCTION_WORTH_ICON = "Interface\\MoneyFrame\\UI-GoldIcon"
local AUCTION_WORTH_ICON_INSET = 1
local AUCTION_WORTH_ICON_SCALE = 0.4
local MIN_AUCTION_WORTH_ICON_SIZE = 12
local MAX_AUCTION_WORTH_ICON_SIZE = 18
local AUCTION_WORTH_OVERLAY_LEVEL = 5
local JUNK_ICON_SHADE = 0.5

local SALE_UNKNOWN = "unknown"
local SALE_AUCTION = "auction"
local SALE_VENDOR = "vendor"
local SALE_NOT_COMPARABLE = "notComparable"

local pendingItemIDs = {}
local failedItemIDs = {}
local refreshQueued = false

local function RequestItemData(itemLink)
  local itemID = C_Item.GetItemInfoInstant(itemLink)
  if not itemID or pendingItemIDs[itemID] or failedItemIDs[itemID] then
    return
  end
  pendingItemIDs[itemID] = true
  C_Item.RequestLoadItemDataByID(itemID)
end

local function AuctionPriceBeatsVendor(auctionPrice, vendorPrice)
  local percent = AuctionPrices.GetSellWorthSettings().percent
  return (auctionPrice - vendorPrice) * 100 > vendorPrice * percent
end

local function BestSale(containerItemInfo)
  local itemLink = containerItemInfo.hyperlink
  local itemName, _, _, _, _, _, _, _, _, _, vendorPrice = C_Item.GetItemInfo(itemLink)
  if not itemName then
    return SALE_UNKNOWN
  end
  local auctionPrice = AuctionPrices.GetStoredUnitPrice(itemLink)
  if not auctionPrice or vendorPrice == 0 or AuctionPrices.IsBagItemBound(containerItemInfo) then
    return SALE_NOT_COMPARABLE
  end
  if AuctionPriceBeatsVendor(auctionPrice, vendorPrice) then
    return SALE_AUCTION
  end
  return SALE_VENDOR
end

function AuctionPrices.CollectWorthAuctionSlots()
  local slots = {}
  local waitingForItemData = false
  AuctionPrices.EachCarriedBagSlot(function(bagID, slotID)
    local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
    if not itemInfo then
      return
    end
    local bestSale = BestSale(itemInfo)
    if bestSale == SALE_UNKNOWN then
      waitingForItemData = true
      RequestItemData(itemInfo.hyperlink)
    elseif bestSale == SALE_AUCTION then
      table.insert(slots, {
        bagID = bagID,
        slotID = slotID,
        itemLink = itemInfo.hyperlink,
        stackCount = itemInfo.stackCount,
      })
    end
  end)
  return slots, waitingForItemData
end

local function AuctionWorthIconSize(button)
  local iconSize = math.floor(button:GetWidth() * AUCTION_WORTH_ICON_SCALE)
  return math.min(math.max(iconSize, MIN_AUCTION_WORTH_ICON_SIZE), MAX_AUCTION_WORTH_ICON_SIZE)
end

local function CreateAuctionWorthOverlay(button)
  local overlay = CreateFrame("Frame", nil, button)
  overlay:SetPoint("TOPLEFT", button, "TOPLEFT", AUCTION_WORTH_ICON_INSET, -AUCTION_WORTH_ICON_INSET)
  overlay:EnableMouse(false)
  local icon = overlay:CreateTexture(nil, "OVERLAY")
  icon:SetAllPoints()
  icon:SetTexture(AUCTION_WORTH_ICON)
  button.auctionPricesWorthOverlay = overlay
  return overlay
end

local function ShowAuctionWorthOverlay(button)
  local overlay = button.auctionPricesWorthOverlay
  if not overlay then
    if InCombatLockdown() then
      return
    end
    overlay = CreateAuctionWorthOverlay(button)
  end
  local iconSize = AuctionWorthIconSize(button)
  overlay:SetFrameLevel(button:GetFrameLevel() + AUCTION_WORTH_OVERLAY_LEVEL)
  overlay:SetSize(iconSize, iconSize)
  overlay:Show()
end

local function HideAuctionWorthOverlay(button)
  if button.auctionPricesWorthOverlay then
    button.auctionPricesWorthOverlay:Hide()
  end
end

local function SetJunkShade(button, shaded)
  local shade = shaded and JUNK_ICON_SHADE or 1
  button.icon:SetVertexColor(shade, shade, shade, 1)
end

local function ClearButtonMark(button)
  HideAuctionWorthOverlay(button)
  SetJunkShade(button, false)
end

local function MarkButton(button, containerItemInfo)
  local itemLink = containerItemInfo.hyperlink
  local bestSale = BestSale(containerItemInfo)
  if bestSale == SALE_UNKNOWN then
    ClearButtonMark(button)
    RequestItemData(itemLink)
    return
  end
  local mark = AuctionPrices.GetSellWorthSettings().mark
  local showAuctionIcon = bestSale == SALE_AUCTION
    and mark ~= AuctionPrices.SellWorthMarks.Vendor
    and not AuctionPrices.IsDoNotSell(itemLink)
  local shadeAsJunk = bestSale == SALE_VENDOR and mark ~= AuctionPrices.SellWorthMarks.Auction
  if showAuctionIcon then
    ShowAuctionWorthOverlay(button)
  else
    HideAuctionWorthOverlay(button)
  end
  SetJunkShade(button, shadeAsJunk)
end

local function CarriedContainerItem(button)
  local bagID = button.bagID or button:GetAttribute("bagid")
  local slotID = button:GetID()
  if not bagID or slotID <= 0 or not AuctionPrices.IsCarriedBag(bagID) then
    return
  end
  return C_Container.GetContainerItemInfo(bagID, slotID)
end

local function UpdateButton(button)
  local containerItemInfo = CarriedContainerItem(button)
  if not containerItemInfo or not AuctionPrices.GetSellWorthSettings().enabled then
    ClearButtonMark(button)
    return
  end
  MarkButton(button, containerItemInfo)
end

local function UpdateBagFrame(frame)
  if not frame:IsShown() then
    return
  end
  for _, button in ipairs(frame.Items) do
    if button:IsShown() then
      UpdateButton(button)
    else
      ClearButtonMark(button)
    end
  end
end

function AuctionPrices.RefreshBagIcons()
  for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
    UpdateBagFrame(frame)
  end
end

local function QueueRefresh()
  if refreshQueued then
    return
  end
  refreshQueued = true
  C_Timer.After(0, function()
    refreshQueued = false
    AuctionPrices.RefreshBagIcons()
  end)
end

local function HookBagFrameOnShow(frame)
  if frame.auctionPricesShowHooked then
    return
  end
  frame.auctionPricesShowHooked = true
  frame:HookScript("OnShow", QueueRefresh)
end

local function OnItemDataLoaded(itemID, success)
  if not pendingItemIDs[itemID] then
    return
  end
  pendingItemIDs[itemID] = nil
  if not success then
    failedItemIDs[itemID] = true
  end
  QueueRefresh()
end

local function OnBagEvent(_, event, itemID, success)
  if event == "ITEM_DATA_LOAD_RESULT" then
    OnItemDataLoaded(itemID, success)
    return
  end
  QueueRefresh()
end

local function HookContainerFrames()
  hooksecurefunc(ContainerFrameMixin, "UpdateItems", UpdateBagFrame)
  hooksecurefunc(ContainerFrameMixin, "UpdateItemLayout", UpdateBagFrame)
  hooksecurefunc(ContainerFrameItemButtonMixin, "UpdateCooldown", UpdateButton)
  hooksecurefunc(ContainerFrameItemButtonMixin, "SetHasItem", function(button, hasItem)
    if not hasItem then
      ClearButtonMark(button)
    end
  end)
  hooksecurefunc("ContainerFrame_GenerateFrame", function(frame)
    HookBagFrameOnShow(frame)
    QueueRefresh()
  end)
  HookBagFrameOnShow(ContainerFrameCombinedBags)
  for _, frame in ContainerFrameUtil_EnumerateContainerFrames() do
    HookBagFrameOnShow(frame)
  end
end

function AuctionPrices.Bags.Install()
  HookContainerFrames()

  local bagListener = CreateFrame("Frame")
  bagListener:RegisterEvent("BAG_OPEN")
  bagListener:RegisterEvent("BAG_UPDATE_DELAYED")
  bagListener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  bagListener:RegisterEvent("PLAYER_REGEN_ENABLED")
  bagListener:SetScript("OnEvent", OnBagEvent)
  AuctionPrices.RefreshBagIcons()
end

AuctionPrices.DatabaseChanged.Register(AuctionPrices.RefreshBagIcons)
AuctionPrices.DoNotSellChanged.Register(AuctionPrices.RefreshBagIcons)
