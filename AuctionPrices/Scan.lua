AuctionPrices.Scan = {}

local SCAN_COOLDOWN_SECONDS = 15 * 60
local REPLICATE_BATCH_SIZE = 250
local AUCTION_BATCH_DELAY_SECONDS = 0.01
local UNRESOLVED_AUCTION_TIMEOUT_SECONDS = 8
local ITEM_DATA_RETRY_SECONDS = 0.4
local MAX_SHOWN_PROCESSING_PERCENT = 99
local REPLICATE_STACK_COUNT_INDEX = 3
local REPLICATE_BUYOUT_INDEX = 10
local REPLICATE_ITEM_ID_INDEX = 17
local REPLICATE_ITEM_DATA_READY_INDEX = 18

local scanInProgress = false
local waitingForAuctionList = false
local scanGeneration = 0
local scanStatusCallback
local lastShownProcessingPercent

local pendingItemDataCallbacks = {}
local itemDataLoadFrame = CreateFrame("Frame")
local replicateEventFrame = CreateFrame("Frame")

itemDataLoadFrame:SetScript("OnEvent", function(_, _, itemID)
  local callbacks = pendingItemDataCallbacks[itemID]
  if not callbacks then
    return
  end
  pendingItemDataCallbacks[itemID] = nil
  for _, callback in ipairs(callbacks) do
    callback()
  end
end)

local elapsedSinceItemDataRetry = 0

local function RetryPendingItemDataLoads(_, elapsed)
  if next(pendingItemDataCallbacks) == nil then
    elapsedSinceItemDataRetry = 0
    itemDataLoadFrame:SetScript("OnUpdate", nil)
    itemDataLoadFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
    return
  end
  elapsedSinceItemDataRetry = elapsedSinceItemDataRetry + elapsed
  if elapsedSinceItemDataRetry <= ITEM_DATA_RETRY_SECONDS then
    return
  end
  elapsedSinceItemDataRetry = 0
  for itemID in pairs(pendingItemDataCallbacks) do
    C_Item.RequestLoadItemDataByID(itemID)
  end
end

local function LoadItemDataThen(itemID, callback)
  if not pendingItemDataCallbacks[itemID] then
    pendingItemDataCallbacks[itemID] = {}
  end
  table.insert(pendingItemDataCallbacks[itemID], callback)
  itemDataLoadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  itemDataLoadFrame:SetScript("OnUpdate", RetryPendingItemDataLoads)
  C_Item.RequestLoadItemDataByID(itemID)
end

local function ReportScanStatus(statusText)
  scanStatusCallback(statusText)
end

local function ReportProcessingPercent(processedCount, auctionCount)
  local percent = math.min(math.floor(processedCount / auctionCount * 100), MAX_SHOWN_PROCESSING_PERCENT)
  if percent == lastShownProcessingPercent then
    return
  end
  lastShownProcessingPercent = percent
  ReportScanStatus(AuctionPrices.Text("PROCESSING", percent))
end

local function IsCurrentScan(generationToken)
  return scanInProgress and generationToken == scanGeneration
end

local function SecondsUntilNextScan()
  local lastAttemptTime = AuctionPrices.GetRealmPriceDatabase().lastAttempt or 0
  return math.max(SCAN_COOLDOWN_SECONDS - (time() - lastAttemptTime), 0)
end

local function FinishScan(collectedPrices)
  waitingForAuctionList = false
  if not scanInProgress then
    return
  end
  scanInProgress = false
  scanGeneration = scanGeneration + 1
  replicateEventFrame:UnregisterAllEvents()
  if collectedPrices and next(collectedPrices) then
    AuctionPrices.ReplaceStoredPrices(collectedPrices, time())
  end
  ReportScanStatus(nil)
  AuctionPrices.PriceCheckChanged.Notify()
end

local function StoreCheapestUnitPrice(collectedPrices, priceKeys, unitPrice)
  for _, priceKey in ipairs(priceKeys) do
    local cheapestUnitPrice = collectedPrices[priceKey]
    if not cheapestUnitPrice or unitPrice < cheapestUnitPrice then
      collectedPrices[priceKey] = unitPrice
    end
  end
end

local function ReadBuyoutAuction(replicateIndex)
  local replicateItemInfo = { C_AuctionHouse.GetReplicateItemInfo(replicateIndex) }
  local stackCount = replicateItemInfo[REPLICATE_STACK_COUNT_INDEX]
  local stackBuyout = replicateItemInfo[REPLICATE_BUYOUT_INDEX]
  local itemID = replicateItemInfo[REPLICATE_ITEM_ID_INDEX]
  if not itemID or not stackCount or stackCount <= 0 or not stackBuyout or stackBuyout <= 0 then
    return
  end
  if not C_Item.DoesItemExistByID(itemID) then
    return
  end
  local unitPrice = math.floor(stackBuyout / stackCount)
  if unitPrice <= 0 then
    return
  end
  return itemID, unitPrice, replicateItemInfo[REPLICATE_ITEM_DATA_READY_INDEX]
end

local function PriceKeysForAuction(itemLink, itemID)
  local priceKeys = itemLink and AuctionPrices.PriceKeysForItemLink(itemLink) or {}
  if not priceKeys[1] then
    return { tostring(itemID) }
  end
  return priceKeys
end

local function FinishBatchIfComplete(batch)
  if IsCurrentScan(batch.generationToken) and batch.allQueued and batch.unfinishedCount == 0 then
    FinishScan(batch.collectedPrices)
  end
end

local function MarkAuctionProcessed(batch)
  batch.unfinishedCount = batch.unfinishedCount - 1
  batch.processedCount = batch.processedCount + 1
  ReportProcessingPercent(batch.processedCount, batch.auctionCount)
  FinishBatchIfComplete(batch)
end

local function StoreAuctionPrice(batch, replicateIndex, itemID, unitPrice)
  if not IsCurrentScan(batch.generationToken) then
    return
  end
  local itemLink = C_AuctionHouse.GetReplicateItemLink(replicateIndex)
  StoreCheapestUnitPrice(batch.collectedPrices, PriceKeysForAuction(itemLink, itemID), unitPrice)
  MarkAuctionProcessed(batch)
end

local function QueueAuction(batch, replicateIndex)
  batch.unfinishedCount = batch.unfinishedCount + 1
  local itemID, unitPrice, itemDataIsLoaded = ReadBuyoutAuction(replicateIndex)
  if not itemID then
    MarkAuctionProcessed(batch)
    return
  end
  if itemDataIsLoaded then
    StoreAuctionPrice(batch, replicateIndex, itemID, unitPrice)
    return
  end
  LoadItemDataThen(itemID, function()
    StoreAuctionPrice(batch, replicateIndex, itemID, unitPrice)
  end)
end

local function FinishUnresolvedAuctionsLater(batch)
  C_Timer.After(UNRESOLVED_AUCTION_TIMEOUT_SECONDS, function()
    if IsCurrentScan(batch.generationToken) then
      FinishScan(batch.collectedPrices)
    end
  end)
end

local function ProcessAuctionBatch(batch, firstAuctionIndex)
  if not IsCurrentScan(batch.generationToken) then
    return
  end
  local lastAuctionIndex = math.min(firstAuctionIndex + REPLICATE_BATCH_SIZE, batch.auctionCount) - 1
  for replicateIndex = firstAuctionIndex, lastAuctionIndex do
    QueueAuction(batch, replicateIndex)
  end
  if lastAuctionIndex < batch.auctionCount - 1 then
    C_Timer.After(AUCTION_BATCH_DELAY_SECONDS, function()
      ProcessAuctionBatch(batch, lastAuctionIndex + 1)
    end)
    return
  end
  batch.allQueued = true
  FinishBatchIfComplete(batch)
  FinishUnresolvedAuctionsLater(batch)
end

local function ProcessReplicateList()
  waitingForAuctionList = false
  local auctionCount = C_AuctionHouse.GetNumReplicateItems()
  if auctionCount == 0 then
    FinishScan()
    return
  end

  lastShownProcessingPercent = nil
  ProcessAuctionBatch({
    generationToken = scanGeneration,
    collectedPrices = {},
    auctionCount = auctionCount,
    unfinishedCount = 0,
    processedCount = 0,
    allQueued = false,
  }, 0)
end

replicateEventFrame:SetScript("OnEvent", function(_, event)
  if event == "AUCTION_HOUSE_CLOSED" then
    FinishScan()
    return
  end
  replicateEventFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  ProcessReplicateList()
end)

function AuctionPrices.Scan.SetStatusCallback(callback)
  scanStatusCallback = callback
end

function AuctionPrices.Scan.IsInProgress()
  return scanInProgress
end

function AuctionPrices.Scan.IsWaitingForAuctionList()
  return waitingForAuctionList
end

function AuctionPrices.Scan.CanStart()
  return not scanInProgress and SecondsUntilNextScan() == 0
end

function AuctionPrices.Scan.CooldownMessage()
  local secondsRemaining = SecondsUntilNextScan()
  return AuctionPrices.Text("NEXT_SCAN", math.floor(secondsRemaining / 60), secondsRemaining % 60)
end

function AuctionPrices.Scan.Start()
  scanGeneration = scanGeneration + 1
  scanInProgress = true
  waitingForAuctionList = true
  AuctionPrices.BagPrices.Stop()
  AuctionPrices.GetRealmPriceDatabase().lastAttempt = time()
  ReportScanStatus(AuctionPrices.Text("FETCHING"))
  AuctionPrices.PriceCheckChanged.Notify()

  replicateEventFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  replicateEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
  C_AuctionHouse.ReplicateItems()
end
