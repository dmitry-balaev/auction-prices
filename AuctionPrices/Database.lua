if not AuctionPrices or not AuctionPrices.enabled then
  return
end

local GEAR_ITEM_CLASSES = {}
local ITEM_CLASS = Enum and Enum.ItemClass
if ITEM_CLASS then
  for _, classID in ipairs({ ITEM_CLASS.Weapon, ITEM_CLASS.Armor, ITEM_CLASS.Profession }) do
    if classID then
      GEAR_ITEM_CLASSES[classID] = true
    end
  end
end

local databaseChangedCallback

function AuctionPrices.RegisterDatabaseChangedCallback(callback)
  databaseChangedCallback = callback
end

local function NotifyDatabaseChanged()
  if databaseChangedCallback then
    databaseChangedCallback()
  end
end

function AuctionPrices.GetRealmPriceDatabase()
  if type(AUCTION_PRICES_DB) ~= "table" or type(AUCTION_PRICES_DB.realms) ~= "table" then
    AuctionPrices.EnsureSavedDatabase()
  end

  local realmName = GetRealmName() or "unknown"
  local realmDatabase = AUCTION_PRICES_DB.realms[realmName]
  if not realmDatabase then
    realmDatabase = { prices = {}, lastScan = nil, lastAttempt = nil }
    AUCTION_PRICES_DB.realms[realmName] = realmDatabase
  end
  realmDatabase.prices = realmDatabase.prices or {}
  return realmDatabase
end

function AuctionPrices.PriceKeysForItemLink(itemLink)
  if type(itemLink) ~= "string" then
    return {}
  end
  local itemID = itemLink:match("item:(%d+)")
  if not itemID then
    return {}
  end

  local priceKeys = { itemID }
  local classID = select(6, C_Item.GetItemInfoInstant(itemLink))
  if classID and GEAR_ITEM_CLASSES[classID] and C_Item.GetDetailedItemLevelInfo then
    local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
    if itemLevel and itemLevel > 0 then
      table.insert(priceKeys, 1, itemID .. ":" .. itemLevel)
    end
  end
  return priceKeys
end

function AuctionPrices.GetStoredUnitPrice(itemLink)
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  for _, priceKey in ipairs(AuctionPrices.PriceKeysForItemLink(itemLink)) do
    local unitPrice = realmDatabase.prices[priceKey]
    if unitPrice then
      return unitPrice
    end
  end
end

function AuctionPrices.CountStoredPrices()
  local storedPriceCount = 0
  for _ in pairs(AuctionPrices.GetRealmPriceDatabase().prices) do
    storedPriceCount = storedPriceCount + 1
  end
  return storedPriceCount
end

function AuctionPrices.ClearStoredPrices()
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  realmDatabase.prices = {}
  realmDatabase.lastScan = nil
  NotifyDatabaseChanged()
end

function AuctionPrices.ReplaceStoredPrices(collectedPrices, scanTime)
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  realmDatabase.prices = collectedPrices
  realmDatabase.lastScan = scanTime
  NotifyDatabaseChanged()
end
