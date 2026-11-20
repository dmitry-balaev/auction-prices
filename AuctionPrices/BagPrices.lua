AuctionPrices.BagPrices = {}

local START_DELAY_SECONDS = 0.5
local RESULT_SETTLE_SECONDS = 0.3
local RESULT_TIMEOUT_SECONDS = 3
local ITEM_DATA_ATTEMPT_LIMIT = 10
local BATCH_LIMIT = 50
local MIN_OWN_RESULT_RATIO = 0.8
local PRICE_SORTS = {
  { sortOrder = Enum.AuctionHouseSortOrder.Price, reverseSort = false },
}

local queryGeneration = 0
local queue
local batch
local seenPriceKeys = {}
local waitingForItemData = false
local startAttempts = 0
local startScheduled = false
local notedPriceCheck = false
local QueryNext
local ScheduleStart

local function NotifyIfPriceCheckChanged()
  local checkingPrices = startScheduled or queue ~= nil or batch ~= nil or waitingForItemData
  if checkingPrices == notedPriceCheck then
    return
  end
  notedPriceCheck = checkingPrices
  AuctionPrices.PriceCheckChanged.Notify()
end

function AuctionPrices.BagPrices.IsChecking()
  return startScheduled or queue ~= nil or batch ~= nil or waitingForItemData
end

local function PriceQueryBlocked()
  return AuctionPrices.Scan.IsInProgress() or AuctionPrices.Posting.IsActive()
end

function AuctionPrices.BagPrices.Stop()
  queryGeneration = queryGeneration + 1
  queue = nil
  batch = nil
  seenPriceKeys = {}
  waitingForItemData = false
  startAttempts = 0
  startScheduled = false
  NotifyIfPriceCheckChanged()
end

local function ItemKeyToken(itemKey)
  return itemKey.itemID .. ":" .. itemKey.itemLevel .. ":" .. itemKey.itemSuffix .. ":" .. itemKey.battlePetSpeciesID
end

local function SearchItemKey(bagSlot)
  local itemLocation = ItemLocation:CreateFromBagAndSlot(bagSlot.bagID, bagSlot.slotID)
  if not itemLocation:IsValid() then
    return
  end
  local itemKey = C_AuctionHouse.GetItemKeyFromItem(itemLocation)
  if not itemKey then
    return
  end
  return {
    itemID = itemKey.itemID,
    itemLevel = itemKey.itemLevel or 0,
    itemSuffix = itemKey.itemSuffix or 0,
    battlePetSpeciesID = itemKey.battlePetSpeciesID or 0,
  }
end

local function RetryStartForMissingItemData()
  if not waitingForItemData or startAttempts >= ITEM_DATA_ATTEMPT_LIMIT then
    return false
  end
  waitingForItemData = false
  startAttempts = startAttempts + 1
  ScheduleStart()
  return true
end

local function SendNextSearch()
  local itemLinksByKey = {}
  local itemKeys = {}
  while queue[1] and #itemKeys < BATCH_LIMIT do
    local bagSlot = table.remove(queue, 1)
    local itemKey = SearchItemKey(bagSlot)
    if itemKey then
      itemLinksByKey[ItemKeyToken(itemKey)] = bagSlot.itemLink
      table.insert(itemKeys, itemKey)
    end
  end
  if not itemKeys[1] then
    QueryNext()
    NotifyIfPriceCheckChanged()
    return
  end

  local sentBatch = {
    itemLinksByKey = itemLinksByKey,
    changedAt = GetTime(),
    waitingToSettle = false,
  }
  local generation = queryGeneration
  batch = sentBatch
  NotifyIfPriceCheckChanged()
  C_AuctionHouse.SearchForItemKeys(itemKeys, PRICE_SORTS)
  C_Timer.After(RESULT_TIMEOUT_SECONDS, function()
    if generation ~= queryGeneration or batch ~= sentBatch then
      return
    end
    batch = nil
    QueryNext()
  end)
end

QueryNext = function()
  if PriceQueryBlocked() then
    AuctionPrices.BagPrices.Stop()
    return
  end
  if batch then
    return
  end
  if not queue[1] then
    queue = nil
    if not RetryStartForMissingItemData() then
      AuctionPrices.BagPrices.Stop()
    end
    NotifyIfPriceCheckChanged()
    return
  end
  if C_AuctionHouse.IsThrottledMessageSystemReady() then
    SendNextSearch()
  end
  NotifyIfPriceCheckChanged()
end

local function StoreMatchedBrowsePrices()
  local browseResults = C_AuctionHouse.GetBrowseResults()
  local unitPriceByLink = {}
  local matchedResultCount = 0
  for _, browseResult in ipairs(browseResults) do
    local itemLink = batch.itemLinksByKey[ItemKeyToken(browseResult.itemKey)]
    if itemLink then
      matchedResultCount = matchedResultCount + 1
      if browseResult.minPrice > 0 then
        unitPriceByLink[itemLink] = browseResult.minPrice
      end
    end
  end
  if matchedResultCount == 0 or matchedResultCount / #browseResults < MIN_OWN_RESULT_RATIO then
    return
  end
  for itemLink, unitPrice in pairs(unitPriceByLink) do
    AuctionPrices.StoreUnitPrice(itemLink, unitPrice)
  end
  batch = nil
  QueryNext()
end

local function ReadBrowseResultsWhenSettled(generation, currentBatch)
  if generation ~= queryGeneration or batch ~= currentBatch then
    return
  end
  local sinceLastChange = GetTime() - currentBatch.changedAt
  if sinceLastChange < RESULT_SETTLE_SECONDS then
    C_Timer.After(RESULT_SETTLE_SECONDS - sinceLastChange, function()
      ReadBrowseResultsWhenSettled(generation, currentBatch)
    end)
    return
  end
  currentBatch.waitingToSettle = false
  StoreMatchedBrowsePrices()
end

local function OnBrowseResultsChanged()
  if not batch then
    return
  end
  batch.changedAt = GetTime()
  if batch.waitingToSettle then
    return
  end
  batch.waitingToSettle = true
  local generation = queryGeneration
  local currentBatch = batch
  C_Timer.After(RESULT_SETTLE_SECONDS, function()
    ReadBrowseResultsWhenSettled(generation, currentBatch)
  end)
end

local function QueueBagSlot(bagID, slotID)
  local itemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
  if not itemInfo or itemInfo.isLocked then
    return
  end
  local itemLink = itemInfo.hyperlink
  if not C_Item.GetItemInfo(itemLink) then
    waitingForItemData = true
    return
  end
  if AuctionPrices.IsBagItemBound(itemInfo) then
    return
  end
  local priceKey = AuctionPrices.PrimaryPriceKey(itemLink)
  if not priceKey or seenPriceKeys[priceKey] then
    return
  end
  seenPriceKeys[priceKey] = true
  table.insert(queue, { bagID = bagID, slotID = slotID, itemLink = itemLink })
end

local function Start()
  if PriceQueryBlocked() then
    return
  end
  queryGeneration = queryGeneration + 1
  batch = nil
  queue = {}
  waitingForItemData = false
  AuctionPrices.EachCarriedBagSlot(QueueBagSlot)
  if not waitingForItemData then
    startAttempts = 0
  end
  if queue[1] then
    QueryNext()
    NotifyIfPriceCheckChanged()
    return
  end
  queue = nil
  RetryStartForMissingItemData()
  NotifyIfPriceCheckChanged()
end

ScheduleStart = function()
  if startScheduled or queue or batch or PriceQueryBlocked() then
    return
  end
  startScheduled = true
  NotifyIfPriceCheckChanged()
  local generation = queryGeneration
  C_Timer.After(START_DELAY_SECONDS, function()
    if generation ~= queryGeneration then
      return
    end
    startScheduled = false
    Start()
    NotifyIfPriceCheckChanged()
  end)
end

local listener = CreateFrame("Frame")
listener:RegisterEvent("AUCTION_HOUSE_SHOW")
listener:RegisterEvent("AUCTION_HOUSE_CLOSED")
listener:RegisterEvent("BAG_UPDATE_DELAYED")
listener:RegisterEvent("ITEM_DATA_LOAD_RESULT")
listener:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_UPDATED")
listener:RegisterEvent("AUCTION_HOUSE_BROWSE_RESULTS_ADDED")
listener:RegisterEvent("AUCTION_HOUSE_THROTTLED_SYSTEM_READY")
listener:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_SHOW" then
    startAttempts = 0
    ScheduleStart()
  elseif event == "AUCTION_HOUSE_CLOSED" then
    AuctionPrices.BagPrices.Stop()
  elseif event == "BAG_UPDATE_DELAYED" or event == "ITEM_DATA_LOAD_RESULT" then
    if waitingForItemData then
      ScheduleStart()
    end
  elseif event == "AUCTION_HOUSE_THROTTLED_SYSTEM_READY" then
    if queue and not batch then
      QueryNext()
    end
  else
    OnBrowseResultsChanged()
  end
end)
