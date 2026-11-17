local BUILD = select(4, GetBuildInfo())
local CAMELOT = WOW_PROJECT_CAMELOT
local MIN_BUILD = 16000
local MAX_BUILD = 20000
AuctionPrices.enabled = CAMELOT ~= nil and WOW_PROJECT_ID == CAMELOT and BUILD >= MIN_BUILD and BUILD < MAX_BUILD

if not AuctionPrices.enabled then
  return
end

function AuctionPrices.EnsureSavedDatabase()
  if type(AUCTION_PRICES_DB) ~= "table" then
    AUCTION_PRICES_DB = {}
  end
  if type(AUCTION_PRICES_DB.realms) ~= "table" then
    AUCTION_PRICES_DB.realms = {}
  end
end

local GOLD_ICON = "|TInterface\\MoneyFrame\\UI-GoldIcon:12:12:0:0|t"
local SILVER_ICON = "|TInterface\\MoneyFrame\\UI-SilverIcon:12:12:0:0|t"
local COPPER_ICON = "|TInterface\\MoneyFrame\\UI-CopperIcon:12:12:0:0|t"

local function FormatCoinAmount(coinCount, coinIcon, padToTwoDigits)
  local coinText = tostring(coinCount)
  if padToTwoDigits and coinCount < 10 then
    coinText = "0" .. coinText
  end
  return coinText .. " " .. coinIcon
end

function AuctionPrices.FormatMoney(copperAmount)
  copperAmount = math.floor(copperAmount or 0)
  if copperAmount < 0 then
    copperAmount = 0
  end

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

local addonLoadListener = CreateFrame("Frame")
addonLoadListener:RegisterEvent("ADDON_LOADED")
addonLoadListener:RegisterEvent("PLAYER_LOGIN")
addonLoadListener:SetScript("OnEvent", function(_, event, addonName)
  if event == "ADDON_LOADED" and addonName == "AuctionPrices" then
    AuctionPrices.EnsureSavedDatabase()
    AuctionPrices.SetupOptionsPanel()
  elseif event == "PLAYER_LOGIN" then
    AuctionPrices.Tooltips.InstallHooks()
  end
end)
