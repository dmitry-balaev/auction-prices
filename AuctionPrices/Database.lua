local GEAR_ITEM_CLASSES = {
  [Enum.ItemClass.Weapon] = true,
  [Enum.ItemClass.Armor] = true,
  [Enum.ItemClass.Profession] = true,
}

AuctionPrices.DatabaseChanged = AuctionPrices.CreateNotifier()
AuctionPrices.DoNotSellChanged = AuctionPrices.CreateNotifier()

function AuctionPrices.InitializeDatabase()
  AUCTION_PRICES_DB = AUCTION_PRICES_DB or {}
  AUCTION_PRICES_DB.realms = AUCTION_PRICES_DB.realms or {}
  AUCTION_PRICES_DB.doNotSell = AUCTION_PRICES_DB.doNotSell or {}
  AUCTION_PRICES_DB.settings = AUCTION_PRICES_DB.settings or {}
end

function AuctionPrices.GetRealmPriceDatabase()
  local realmName = GetRealmName()
  local realmDatabase = AUCTION_PRICES_DB.realms[realmName]
  if not realmDatabase then
    realmDatabase = { prices = {} }
    AUCTION_PRICES_DB.realms[realmName] = realmDatabase
  end
  return realmDatabase
end

function AuctionPrices.PriceKeysForItemLink(itemLink)
  local itemID = itemLink:match("item:(%d+)")
  if not itemID then
    return {}
  end

  local priceKeys = { itemID }
  local classID = select(6, C_Item.GetItemInfoInstant(itemLink))
  if not GEAR_ITEM_CLASSES[classID] then
    return priceKeys
  end
  local itemLevel = C_Item.GetDetailedItemLevelInfo(itemLink)
  if itemLevel and itemLevel > 0 then
    table.insert(priceKeys, 1, itemID .. ":" .. itemLevel)
  end
  return priceKeys
end

function AuctionPrices.PrimaryPriceKey(itemLink)
  return AuctionPrices.PriceKeysForItemLink(itemLink)[1]
end

function AuctionPrices.GetStoredUnitPrice(itemLink)
  local prices = AuctionPrices.GetRealmPriceDatabase().prices
  for _, priceKey in ipairs(AuctionPrices.PriceKeysForItemLink(itemLink)) do
    if prices[priceKey] then
      return prices[priceKey]
    end
  end
end

function AuctionPrices.CountStoredPrices()
  return AuctionPrices.CountKeys(AuctionPrices.GetRealmPriceDatabase().prices)
end

function AuctionPrices.ClearStoredPrices()
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  realmDatabase.prices = {}
  realmDatabase.lastScan = nil
  AuctionPrices.DatabaseChanged.Notify()
end

function AuctionPrices.StoreUnitPrice(itemLink, unitPrice)
  local priceKey = AuctionPrices.PrimaryPriceKey(itemLink)
  local prices = AuctionPrices.GetRealmPriceDatabase().prices
  unitPrice = math.floor(unitPrice)
  if prices[priceKey] == unitPrice then
    return
  end
  prices[priceKey] = unitPrice
  AuctionPrices.DatabaseChanged.Notify()
end

function AuctionPrices.ReplaceStoredPrices(collectedPrices, scanTime)
  local realmDatabase = AuctionPrices.GetRealmPriceDatabase()
  realmDatabase.prices = collectedPrices
  realmDatabase.lastScan = scanTime
  AuctionPrices.DatabaseChanged.Notify()
end

local function RealmDoNotSellList()
  local realmName = GetRealmName()
  local doNotSell = AUCTION_PRICES_DB.doNotSell[realmName]
  if not doNotSell then
    doNotSell = {}
    AUCTION_PRICES_DB.doNotSell[realmName] = doNotSell
  end
  return doNotSell
end

function AuctionPrices.IsDoNotSell(itemLink)
  return RealmDoNotSellList()[AuctionPrices.PrimaryPriceKey(itemLink)] == true
end

function AuctionPrices.AddDoNotSell(itemLink)
  RealmDoNotSellList()[AuctionPrices.PrimaryPriceKey(itemLink)] = true
  AuctionPrices.DoNotSellChanged.Notify()
end

function AuctionPrices.RemoveDoNotSell(itemLink)
  RealmDoNotSellList()[AuctionPrices.PrimaryPriceKey(itemLink)] = nil
  AuctionPrices.DoNotSellChanged.Notify()
end

function AuctionPrices.CountDoNotSell()
  return AuctionPrices.CountKeys(RealmDoNotSellList())
end

function AuctionPrices.ClearDoNotSell()
  AUCTION_PRICES_DB.doNotSell[GetRealmName()] = {}
  AuctionPrices.DoNotSellChanged.Notify()
end
