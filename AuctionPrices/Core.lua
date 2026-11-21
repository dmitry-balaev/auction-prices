local CHAT_PREFIX = "|cff33ff99AuctionPrices:|r "
local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:2:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:2:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:2:0|t"
local STALE_SCAN_SECONDS = 3 * 24 * 60 * 60

local NOT_SOULBOUND_BIND_TYPES = {
  [Enum.ItemBind.None] = true,
  [Enum.ItemBind.OnEquip] = true,
  [Enum.ItemBind.OnUse] = true,
}

function AuctionPrices.Print(textKey, ...)
  print(CHAT_PREFIX .. AuctionPrices.Text(textKey, ...))
end

local function PrintReminder(textKey)
  AuctionPrices.Print(textKey)
end

function AuctionPrices.CountKeys(keyedTable)
  local keyCount = 0
  for _ in pairs(keyedTable) do
    keyCount = keyCount + 1
  end
  return keyCount
end

function AuctionPrices.CreateNotifier()
  local callbacks = {}
  local notifier = {}

  function notifier.Register(callback)
    table.insert(callbacks, callback)
  end

  function notifier.Notify()
    for _, callback in ipairs(callbacks) do
      callback()
    end
  end

  return notifier
end

AuctionPrices.AuctionHouseUILoaded = AuctionPrices.CreateNotifier()
AuctionPrices.PriceCheckChanged = AuctionPrices.CreateNotifier()

function AuctionPrices.IsCarriedBag(bagID)
  return bagID >= BACKPACK_CONTAINER and bagID <= NUM_TOTAL_EQUIPPED_BAG_SLOTS
end

function AuctionPrices.EachCarriedBagSlot(visitSlot)
  for bagID = BACKPACK_CONTAINER, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
    for slotID = 1, C_Container.GetContainerNumSlots(bagID) do
      visitSlot(bagID, slotID)
    end
  end
end

function AuctionPrices.ItemLinkIsSoulbound(itemLink)
  local itemName, _, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemLink)
  if not itemName then
    return false
  end
  if NOT_SOULBOUND_BIND_TYPES[bindType] then
    return C_Item.IsItemBindToAccountUntilEquip(itemLink)
  end
  return bindType ~= nil
end

function AuctionPrices.IsBagItemBound(containerItemInfo)
  return containerItemInfo.isBound or AuctionPrices.ItemLinkIsSoulbound(containerItemInfo.hyperlink)
end

local function FormatCoinAmount(coinCount, coinIcon, padToTwoDigits)
  if padToTwoDigits then
    return string.format("%02d", coinCount) .. coinIcon
  end
  return coinCount .. coinIcon
end

function AuctionPrices.FormatMoney(copperAmount)
  copperAmount = math.floor(copperAmount)
  local copper = copperAmount % 100
  local silver = math.floor(copperAmount / 100) % 100
  local gold = math.floor(copperAmount / 10000)
  local showSilver = gold > 0 or silver > 0
  local moneyParts = { FormatCoinAmount(copper, COPPER_ICON, showSilver) }

  if showSilver then
    table.insert(moneyParts, 1, FormatCoinAmount(silver, SILVER_ICON, gold > 0))
  end
  if gold > 0 then
    table.insert(moneyParts, 1, FormatCoinAmount(gold, GOLD_ICON, false))
  end
  return table.concat(moneyParts, " ")
end

local function RemindAboutScan()
  local lastScanTime = AuctionPrices.GetRealmPriceDatabase().lastScan
  if not lastScanTime or AuctionPrices.CountStoredPrices() == 0 then
    PrintReminder("PRICE_DATABASE_MISSING")
    return
  end
  if time() - lastScanTime > STALE_SCAN_SECONDS then
    PrintReminder("PRICES_ARE_STALE")
  end
end

local startupListener = CreateFrame("Frame")
startupListener:RegisterEvent("ADDON_LOADED")
startupListener:RegisterEvent("PLAYER_LOGIN")
startupListener:SetScript("OnEvent", function(_, event, addonName)
  if event == "PLAYER_LOGIN" then
    AuctionPrices.Tooltips.InstallHooks()
    AuctionPrices.Bags.Install()
    RemindAboutScan()
    return
  end
  if addonName ~= "AuctionPrices" then
    return
  end
  AuctionPrices.InitializeDatabase()
  AuctionPrices.InitializeSettings()
  AuctionPrices.SetupOptionsPanel()
  EventUtil.ContinueOnAddOnLoaded("Blizzard_AuctionHouseUI", AuctionPrices.AuctionHouseUILoaded.Notify)
end)
