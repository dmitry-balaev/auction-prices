AuctionPrices.Posting = {}

local SERVER_REPLY_TIMEOUT_SECONDS = 5
local LOCKED_ITEM_TIMEOUT_LIMIT = 3
local POST_WARNING_POPUP = "AUCTION_HOUSE_POST_WARNING"

local SENT = "sent"
local KEPT_IN_QUEUE = "keptInQueue"
local SKIPPED = "skipped"

local STAGE_SENT = "sent"
local STAGE_CONFIRM = "confirm"

local ITEM_LEFT_BAGS = "leftBags"
local ITEM_LOCKED = "locked"
local ITEM_IN_BAGS = "inBags"

local postingActive = false
local queue
local activityCallback
local inFlight
local inFlightGeneration = 0
local unacknowledgedCreates = 0
local chosenSlotKey
local PostableSlots

local function NotifyActivity()
  activityCallback()
end

local function SlotKey(slot)
  return slot.bagID .. ":" .. slot.slotID .. ":" .. slot.itemLink
end

function AuctionPrices.Posting.ChosenAmong(slots)
  if not chosenSlotKey then
    return
  end
  for _, slot in ipairs(slots) do
    if SlotKey(slot) == chosenSlotKey then
      return slot
    end
  end
end

function AuctionPrices.Posting.ChooseForSale(slot)
  chosenSlotKey = SlotKey(slot)
  if postingActive and not inFlight then
    queue = PostableSlots()
  end
  NotifyActivity()
end

local function AuctionUnitPrice(unitPrice)
  if not unitPrice then
    return 0
  end
  unitPrice = math.floor(unitPrice)
  if C_AuctionHouse.SupportsCopperValues() then
    return unitPrice
  end
  return math.ceil(unitPrice / COPPER_PER_SILVER) * COPPER_PER_SILVER
end

local function SaleStatus(itemLocation, itemLink)
  local status = C_AuctionHouse.GetItemCommodityStatus(itemLocation)
  if status == Enum.ItemCommodityStatus.Commodity or status == Enum.ItemCommodityStatus.Item then
    return status
  end
  local equipLocation = select(9, C_Item.GetItemInfo(itemLink))
  if equipLocation and equipLocation ~= "" then
    return Enum.ItemCommodityStatus.Item
  end
  return Enum.ItemCommodityStatus.Commodity
end

local function AuctionDeposit(commodity, itemLocation, duration, quantity)
  if commodity then
    return C_AuctionHouse.CalculateCommodityDeposit(C_Item.GetItemID(itemLocation), duration, quantity)
  end
  return C_AuctionHouse.CalculateItemDeposit(itemLocation, duration, quantity)
end

function AuctionPrices.Posting.DescribeLot(slot)
  local itemInfo = C_Container.GetContainerItemInfo(slot.bagID, slot.slotID)
  if not itemInfo or itemInfo.hyperlink ~= slot.itemLink then
    return
  end
  local itemLocation = ItemLocation:CreateFromBagAndSlot(slot.bagID, slot.slotID)
  local commodity = SaleStatus(itemLocation, slot.itemLink) == Enum.ItemCommodityStatus.Commodity
  local duration = tonumber(GetCVar("auctionHouseDurationDropdown"))
  return {
    itemLocation = itemLocation,
    itemLink = slot.itemLink,
    quantity = itemInfo.stackCount,
    isLocked = itemInfo.isLocked,
    unitPrice = AuctionUnitPrice(AuctionPrices.GetStoredUnitPrice(slot.itemLink)),
    commodity = commodity,
    duration = duration,
    deposit = AuctionDeposit(commodity, itemLocation, duration, itemInfo.stackCount),
  }
end

function AuctionPrices.Posting.IsActive()
  return postingActive
end

function AuctionPrices.Posting.IsWaitingForServer()
  return inFlight ~= nil and inFlight.stage == STAGE_SENT
end

function AuctionPrices.Posting.GetCurrentSlot()
  if not postingActive then
    return
  end
  if inFlight then
    return inFlight.slot
  end
  return queue[1]
end

function AuctionPrices.Posting.SetActivityCallback(callback)
  activityCallback = callback
end

function AuctionPrices.Posting.Stop()
  if not postingActive then
    return
  end
  postingActive = false
  queue = nil
  inFlight = nil
  NotifyActivity()
end

local function BagItemCount(itemLink)
  return C_Item.GetItemCount(C_Item.GetItemInfoInstant(itemLink))
end

local function InFlightItemState()
  local slot = inFlight.slot
  if BagItemCount(slot.itemLink) <= inFlight.countBefore - inFlight.quantity then
    return ITEM_LEFT_BAGS
  end
  local itemInfo = C_Container.GetContainerItemInfo(slot.bagID, slot.slotID)
  if itemInfo and itemInfo.isLocked then
    return ITEM_LOCKED
  end
  return ITEM_IN_BAGS
end

local function StopIfQueueEmpty()
  if inFlight or queue[1] then
    NotifyActivity()
    return
  end
  AuctionPrices.Posting.Stop()
end

local function CompleteInFlight()
  inFlight = nil
  if postingActive then
    StopIfQueueEmpty()
  end
end

local function ReturnInFlightToQueue()
  if not inFlight then
    return
  end
  local returnedSlot = inFlight.slot
  inFlight = nil
  if postingActive then
    table.insert(queue, 1, returnedSlot)
    NotifyActivity()
  end
end

local function CompleteInFlightIfItemLeftBags()
  if inFlight and InFlightItemState() == ITEM_LEFT_BAGS then
    unacknowledgedCreates = unacknowledgedCreates + 1
    CompleteInFlight()
  end
end

local function WatchServerReply(generation)
  C_Timer.After(SERVER_REPLY_TIMEOUT_SECONDS, function()
    if not inFlight or inFlight.generation ~= generation or inFlight.stage ~= STAGE_SENT then
      return
    end
    local itemState = InFlightItemState()
    if itemState == ITEM_LEFT_BAGS then
      CompleteInFlightIfItemLeftBags()
      return
    end
    inFlight.timeouts = inFlight.timeouts + 1
    if itemState == ITEM_LOCKED and inFlight.timeouts < LOCKED_ITEM_TIMEOUT_LIMIT then
      WatchServerReply(generation)
      return
    end
    AuctionPrices.Print("NO_SERVER_REPLY", inFlight.slot.itemLink)
    ReturnInFlightToQueue()
  end)
end

local function MarkInFlightSent()
  inFlight.stage = STAGE_SENT
  inFlight.timeouts = 0
  WatchServerReply(inFlight.generation)
  NotifyActivity()
end

local function OnConfirmationAccepted()
  if inFlight and inFlight.stage == STAGE_CONFIRM then
    MarkInFlightSent()
  end
end

local function OnConfirmationCancelled()
  if inFlight and inFlight.stage == STAGE_CONFIRM then
    ReturnInFlightToQueue()
  end
end

local function CachePendingPost(lot)
  if lot.commodity then
    AuctionHouseFrame.CommoditiesSellFrame:CachePendingPost(lot.itemLocation, lot.duration, lot.quantity, lot.unitPrice)
    return
  end
  AuctionHouseFrame.ItemSellFrame:CachePendingPost(lot.itemLocation, lot.duration, lot.quantity, nil, lot.unitPrice * lot.quantity)
end

local function PostLot(lot)
  if lot.commodity then
    return C_AuctionHouse.PostCommodity(lot.itemLocation, lot.duration, lot.quantity, lot.unitPrice)
  end
  return C_AuctionHouse.PostItem(lot.itemLocation, lot.duration, lot.quantity, nil, lot.unitPrice * lot.quantity)
end

local function SendAuction(slot, lot)
  local countBefore = BagItemCount(lot.itemLink)
  local needsConfirmation = PostLot(lot)
  inFlightGeneration = inFlightGeneration + 1
  inFlight = {
    slot = slot,
    quantity = lot.quantity,
    countBefore = countBefore,
    generation = inFlightGeneration,
    timeouts = 0,
  }
  if needsConfirmation then
    inFlight.stage = STAGE_CONFIRM
    CachePendingPost(lot)
    NotifyActivity()
    return
  end
  MarkInFlightSent()
end

local function TryPostSlot(slot)
  local lot = AuctionPrices.Posting.DescribeLot(slot)
  if not lot then
    AuctionPrices.Print("ITEM_MOVED_POST_AGAIN", slot.itemLink)
    return SKIPPED
  end
  if lot.unitPrice == 0 then
    AuctionPrices.Print("NO_PRICE_IN_DATABASE", slot.itemLink)
    return SKIPPED
  end
  if GetMoney() < lot.deposit then
    AuctionPrices.Print("NOT_ENOUGH_FOR_DEPOSIT", slot.itemLink, AuctionPrices.FormatMoney(lot.deposit))
    return SKIPPED
  end
  if lot.isLocked then
    return KEPT_IN_QUEUE
  end
  SendAuction(slot, lot)
  return SENT
end

local function PostFirstPostableSlot()
  while queue[1] do
    local slot = table.remove(queue, 1)
    local outcome = TryPostSlot(slot)
    if outcome == KEPT_IN_QUEUE then
      table.insert(queue, 1, slot)
      NotifyActivity()
      return
    end
    if outcome == SENT then
      return
    end
  end
  StopIfQueueEmpty()
end

local function ResolveClosedConfirmation()
  local itemState = InFlightItemState()
  if itemState == ITEM_LEFT_BAGS then
    CompleteInFlightIfItemLeftBags()
  elseif itemState == ITEM_LOCKED then
    MarkInFlightSent()
  else
    ReturnInFlightToQueue()
  end
end

function AuctionPrices.Posting.PostNext()
  if inFlight and inFlight.stage == STAGE_CONFIRM and not StaticPopup_Visible(POST_WARNING_POPUP) then
    ResolveClosedConfirmation()
  end
  if postingActive and not inFlight then
    PostFirstPostableSlot()
  end
end

local function IsInFlightSlot(slot)
  return inFlight ~= nil and inFlight.slot.bagID == slot.bagID and inFlight.slot.slotID == slot.slotID
end

PostableSlots = function()
  local slots = {}
  local chosenSlot
  for _, slot in ipairs(AuctionPrices.CollectWorthAuctionSlots()) do
    if not AuctionPrices.IsDoNotSell(slot.itemLink) and not IsInFlightSlot(slot) then
      if SlotKey(slot) == chosenSlotKey then
        chosenSlot = slot
      else
        table.insert(slots, slot)
      end
    end
  end
  if chosenSlot then
    table.insert(slots, 1, chosenSlot)
  end
  return slots
end

local function RebuildQueue()
  if not postingActive then
    return
  end
  queue = PostableSlots()
  StopIfQueueEmpty()
end

function AuctionPrices.Posting.Start()
  queue = PostableSlots()
  if not queue[1] then
    queue = nil
    return
  end
  AuctionPrices.BagPrices.Stop()
  postingActive = true
  PostFirstPostableSlot()
  NotifyActivity()
end

local function HookConfirmationPopup()
  local popup = StaticPopupDialogs[POST_WARNING_POPUP]
  hooksecurefunc(popup, "OnAccept", OnConfirmationAccepted)
  if popup.OnCancel then
    hooksecurefunc(popup, "OnCancel", OnConfirmationCancelled)
  end
end

local function OnAuctionCreated()
  if unacknowledgedCreates > 0 then
    unacknowledgedCreates = unacknowledgedCreates - 1
    return
  end
  if inFlight then
    CompleteInFlight()
  end
end

AuctionPrices.AuctionHouseUILoaded.Register(HookConfirmationPopup)
AuctionPrices.DoNotSellChanged.Register(RebuildQueue)

local listener = CreateFrame("Frame")
listener:RegisterEvent("AUCTION_HOUSE_SHOW")
listener:RegisterEvent("AUCTION_HOUSE_CLOSED")
listener:RegisterEvent("AUCTION_HOUSE_AUCTION_CREATED")
listener:RegisterEvent("AUCTION_HOUSE_POST_ERROR")
listener:RegisterEvent("BAG_UPDATE_DELAYED")
listener:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    unacknowledgedCreates = 0
  elseif event == "AUCTION_HOUSE_CLOSED" then
    chosenSlotKey = nil
    AuctionPrices.Posting.Stop()
  elseif event == "AUCTION_HOUSE_AUCTION_CREATED" then
    OnAuctionCreated()
  elseif event == "AUCTION_HOUSE_POST_ERROR" then
    if inFlight then
      AuctionPrices.Print("AUCTION_REJECTED_LOT", inFlight.slot.itemLink)
    end
    ReturnInFlightToQueue()
  else
    CompleteInFlightIfItemLeftBags()
  end
end)
