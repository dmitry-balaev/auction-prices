if not AuctionPrices or not AuctionPrices.enabled then
  return
end

AuctionPrices.Scan = {}

local SCAN_COOLDOWN_SECONDS = 15 * 60
local REPLICATE_BATCH_SIZE = 250
local AUCTION_BATCH_DELAY_SECONDS = 0.01
local UNRESOLVED_AUCTION_TIMEOUT_SECONDS = 8
local ITEM_DATA_RETRY_SECONDS = 0.4
local REPLICATE_STACK_COUNT_INDEX = 3
local REPLICATE_BUYOUT_INDEX = 10
local REPLICATE_ITEM_ID_INDEX = 17
local REPLICATE_ITEM_DATA_READY_INDEX = 18

local scanInProgress = false
local waitingForAuctionList = false
local scanGeneration = 0
local scanStatusCallback
local lastShownProcessingPercent = -1

local pendingItemDataCallbacks = {}
local itemDataLoadFrame = CreateFrame("Frame")
itemDataLoadFrame.elapsed = 0

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

local function RetryPendingItemDataLoads(_, elapsed)
  itemDataLoadFrame.elapsed = itemDataLoadFrame.elapsed + elapsed
  if itemDataLoadFrame.elapsed > ITEM_DATA_RETRY_SECONDS then
    for itemID in pairs(pendingItemDataCallbacks) do
      C_Item.RequestLoadItemDataByID(itemID)
    end
    itemDataLoadFrame.elapsed = 0
  end
  if next(pendingItemDataCallbacks) == nil then
    itemDataLoadFrame.elapsed = 0
    itemDataLoadFrame:SetScript("OnUpdate", nil)
    itemDataLoadFrame:UnregisterEvent("ITEM_DATA_LOAD_RESULT")
  end
end

local function RequestItemDataThen(itemID, callback)
  if not C_Item.RequestLoadItemDataByID then
    callback()
    return
  end
  pendingItemDataCallbacks[itemID] = pendingItemDataCallbacks[itemID] or {}
  table.insert(pendingItemDataCallbacks[itemID], callback)
  itemDataLoadFrame:RegisterEvent("ITEM_DATA_LOAD_RESULT")
  itemDataLoadFrame:SetScript("OnUpdate", RetryPendingItemDataLoads)
  C_Item.RequestLoadItemDataByID(itemID)
end

local function ReportScanStatus(statusText)
  if scanStatusCallback then
    scanStatusCallback(statusText or "")
  end
end

local function ReportProcessingPercent(percent)
  percent = math.floor(percent)
  if percent < 0 then
    percent = 0
  elseif percent > 99 then
    percent = 99
  end
  if percent == lastShownProcessingPercent then
    return
  end
  lastShownProcessingPercent = percent
  ReportScanStatus(AuctionPrices.Text("PROCESSING", percent))
end

local replicateEventFrame = CreateFrame("Frame")

local function UnregisterScanEvents()
  replicateEventFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  replicateEventFrame:UnregisterEvent("AUCTION_HOUSE_CLOSED")
end

local function IsCurrentScan(generationToken)
  return scanInProgress and generationToken == scanGeneration
end

local function SecondsUntilNextScan()
  local lastAttemptTime = AuctionPrices.GetRealmPriceDatabase().lastAttempt or 0
  local secondsRemaining = SCAN_COOLDOWN_SECONDS - (time() - lastAttemptTime)
  if secondsRemaining < 0 then
    return 0
  end
  return secondsRemaining
end

local function CountCollectedPriceKeys(collectedPrices)
  local collectedPriceCount = 0
  for _ in pairs(collectedPrices) do
    collectedPriceCount = collectedPriceCount + 1
  end
  return collectedPriceCount
end

local function FinishScan(collectedPrices)
  waitingForAuctionList = false
  if not scanInProgress then
    return
  end
  local pricesToSave = collectedPrices
  local hasCollectedPrices = pricesToSave and CountCollectedPriceKeys(pricesToSave) > 0
  scanInProgress = false
  scanGeneration = scanGeneration + 1
  UnregisterScanEvents()
  if hasCollectedPrices then
    AuctionPrices.ReplaceStoredPrices(pricesToSave, time())
  end
  ReportScanStatus("")
end

local function StoreCheapestUnitPrice(collectedPrices, priceKeys, unitPrice)
  for _, priceKey in ipairs(priceKeys) do
    local currentUnitPrice = collectedPrices[priceKey]
    if not currentUnitPrice or unitPrice < currentUnitPrice then
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
  if #priceKeys == 0 then
    priceKeys = { tostring(itemID) }
  end
  return priceKeys
end

local function ProcessReplicateList(generationToken)
  if not IsCurrentScan(generationToken) then
    return
  end
  waitingForAuctionList = false

  local auctionCount = C_AuctionHouse.GetNumReplicateItems()
  if not auctionCount or auctionCount <= 0 then
    FinishScan()
    return
  end

  local collectedPrices = {}
  local unfinishedAuctionCount = 0
  local processedAuctionCount = 0
  local allAuctionsQueued = false

  lastShownProcessingPercent = -1

  local function UpdateProcessingPercent()
    local percent = processedAuctionCount / auctionCount * 100
    if processedAuctionCount < auctionCount and percent > 99 then
      percent = 99
    end
    ReportProcessingPercent(percent)
  end

  local function FinishWhenAllAuctionsProcessed()
    if not IsCurrentScan(generationToken) or not allAuctionsQueued or unfinishedAuctionCount > 0 then
      return
    end
    FinishScan(collectedPrices)
  end

  local function MarkAuctionProcessed()
    unfinishedAuctionCount = unfinishedAuctionCount - 1
    processedAuctionCount = processedAuctionCount + 1
    UpdateProcessingPercent()
    FinishWhenAllAuctionsProcessed()
  end

  local function StoreAuctionPrice(itemID, unitPrice, itemLink)
    if not IsCurrentScan(generationToken) then
      return
    end
    StoreCheapestUnitPrice(collectedPrices, PriceKeysForAuction(itemLink, itemID), unitPrice)
    MarkAuctionProcessed()
  end

  local function QueueAuctionAtIndex(replicateIndex)
    if not IsCurrentScan(generationToken) then
      return
    end
    unfinishedAuctionCount = unfinishedAuctionCount + 1

    local itemID, unitPrice, itemDataIsLoaded = ReadBuyoutAuction(replicateIndex)
    if not itemID then
      MarkAuctionProcessed()
      return
    end

    if not itemDataIsLoaded then
      RequestItemDataThen(itemID, function()
        StoreAuctionPrice(itemID, unitPrice, C_AuctionHouse.GetReplicateItemLink(replicateIndex))
      end)
      return
    end
    StoreAuctionPrice(itemID, unitPrice, C_AuctionHouse.GetReplicateItemLink(replicateIndex))
  end

  local function ProcessAuctionBatch(firstAuctionIndex)
    if not IsCurrentScan(generationToken) then
      return
    end
    local lastAuctionIndex = math.min(firstAuctionIndex + REPLICATE_BATCH_SIZE - 1, auctionCount - 1)
    for replicateIndex = firstAuctionIndex, lastAuctionIndex do
      QueueAuctionAtIndex(replicateIndex)
    end
    if lastAuctionIndex >= auctionCount - 1 then
      allAuctionsQueued = true
      FinishWhenAllAuctionsProcessed()
      C_Timer.After(UNRESOLVED_AUCTION_TIMEOUT_SECONDS, function()
        if not IsCurrentScan(generationToken) then
          return
        end
        FinishScan(collectedPrices)
      end)
      return
    end
    C_Timer.After(AUCTION_BATCH_DELAY_SECONDS, function()
      ProcessAuctionBatch(lastAuctionIndex + 1)
    end)
  end

  ProcessAuctionBatch(0)
end

replicateEventFrame:SetScript("OnEvent", function(_, event)
  if event == "REPLICATE_ITEM_LIST_UPDATE" then
    replicateEventFrame:UnregisterEvent("REPLICATE_ITEM_LIST_UPDATE")
    ProcessReplicateList(scanGeneration)
  elseif event == "AUCTION_HOUSE_CLOSED" then
    FinishScan()
  end
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
  return not scanInProgress and SecondsUntilNextScan() <= 0
end

function AuctionPrices.Scan.CooldownMessage()
  local secondsRemaining = SecondsUntilNextScan()
  return AuctionPrices.Text("NEXT_SCAN", math.floor(secondsRemaining / 60), math.floor(secondsRemaining % 60))
end

function AuctionPrices.Scan.Start()
  if not AuctionHouseFrame or not AuctionHouseFrame:IsShown() then
    return
  end
  if not AuctionPrices.Scan.CanStart() then
    return
  end
  if not C_AuctionHouse or not C_AuctionHouse.ReplicateItems then
    return
  end

  scanGeneration = scanGeneration + 1
  local generationToken = scanGeneration
  scanInProgress = true
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  realmDatabase.lastAttempt = time()
  lastShownProcessingPercent = -1
  waitingForAuctionList = true
  ReportScanStatus(AuctionPrices.Text("FETCHING"))

  replicateEventFrame:RegisterEvent("REPLICATE_ITEM_LIST_UPDATE")
  replicateEventFrame:RegisterEvent("AUCTION_HOUSE_CLOSED")
  local replicateRequestAccepted = pcall(C_AuctionHouse.ReplicateItems)
  if not replicateRequestAccepted or generationToken ~= scanGeneration then
    realmDatabase.lastAttempt = nil
    FinishScan()
  end
end
