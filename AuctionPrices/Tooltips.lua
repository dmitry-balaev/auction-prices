if not AuctionPrices or not AuctionPrices.enabled then
  return
end

AuctionPrices.Tooltips = {}

local TRADABLE_BIND_TYPES = {}
local function RememberTradableBindType(bindType)
  if bindType ~= nil then
    TRADABLE_BIND_TYPES[bindType] = true
  end
end
RememberTradableBindType(LE_ITEM_BIND_NONE)
RememberTradableBindType(LE_ITEM_BIND_ON_EQUIP)
RememberTradableBindType(LE_ITEM_BIND_ON_USE)
if Enum and Enum.ItemBind then
  RememberTradableBindType(Enum.ItemBind.None)
  RememberTradableBindType(Enum.ItemBind.OnEquip)
  RememberTradableBindType(Enum.ItemBind.OnUse)
end

local function ItemLinkIsSoulbound(itemLink)
  local itemName, resolvedLink, _, _, _, _, _, _, _, _, _, _, _, bindType = C_Item.GetItemInfo(itemLink)
  if not itemName then
    return false
  end
  if TRADABLE_BIND_TYPES[bindType] then
    if resolvedLink and C_Item.IsItemBindToAccountUntilEquip and C_Item.IsItemBindToAccountUntilEquip(resolvedLink) then
      return true
    end
    return false
  end
  return bindType ~= nil
end

local function ColorTextWhite(text)
  return WHITE_FONT_COLOR:WrapTextInColorCode(text)
end

local function NormalizeStackSize(stackCount)
  stackCount = tonumber(stackCount) or 1
  if stackCount < 1 then
    return 1
  end
  return stackCount
end

local function AddAuctionPriceLine(tooltip, itemLink, stackCount)
  if type(itemLink) ~= "string" or not itemLink:find("item:", 1, true) then
    return
  end
  if tooltip.IsForbidden and tooltip:IsForbidden() then
    return
  end
  if ItemLinkIsSoulbound(itemLink) then
    return
  end

  stackCount = NormalizeStackSize(stackCount)
  local unitPrice = AuctionPrices.GetStoredUnitPrice(itemLink)
  local priceText = unitPrice and AuctionPrices.FormatMoney(unitPrice * stackCount) or AuctionPrices.Text("UNKNOWN")
  tooltip:AddDoubleLine(ColorTextWhite(AuctionPrices.Text("SELL_PRICE")), ColorTextWhite(priceText))
end

local function ShowAuctionPrice(tooltip, itemLink, stackCount)
  if itemLink then
    AddAuctionPriceLine(tooltip, itemLink, stackCount)
  end
end

local function TooltipHandlerFromLinkAndCount(getItemLink, getItemInfo, stackCountReturnIndex)
  return function(tooltip, firstArgument, secondArgument)
    ShowAuctionPrice(tooltip, getItemLink(firstArgument, secondArgument), select(stackCountReturnIndex, getItemInfo(firstArgument, secondArgument)))
  end
end

local function TradeWindowTooltipHandler(getItemLink, getItemInfo)
  return function(tooltip, tradeSlotIndex)
    local itemLink = getItemLink(tradeSlotIndex)
    if itemLink then
      ShowAuctionPrice(tooltip, itemLink, select(3, getItemInfo(tradeSlotIndex)))
    end
  end
end

local tooltipHandlers = {}

tooltipHandlers.SetBagItem = function(tooltip, bagIndex, slotIndex)
  local itemLocation = ItemLocation:CreateFromBagAndSlot(bagIndex, slotIndex)
  if itemLocation and C_Item.DoesItemExist(itemLocation) then
    ShowAuctionPrice(tooltip, C_Item.GetItemLink(itemLocation), C_Item.GetStackCount(itemLocation))
  end
end

tooltipHandlers.SetInventoryItem = function(tooltip, unit, slotIndex)
  local itemLink = GetInventoryItemLink(unit, slotIndex)
  if itemLink then
    local stackCount = GetInventoryItemCount(unit, slotIndex)
    ShowAuctionPrice(tooltip, itemLink, stackCount ~= 0 and stackCount or 1)
  end
end

local function MerchantItemStackCount(merchantIndex)
  if GetMerchantItemInfo then
    return select(4, GetMerchantItemInfo(merchantIndex))
  end
  if C_MerchantFrame and C_MerchantFrame.GetItemInfo then
    local merchantItemInfo = C_MerchantFrame.GetItemInfo(merchantIndex)
    return merchantItemInfo and merchantItemInfo.stackCount
  end
end

tooltipHandlers.SetMerchantItem = function(tooltip, merchantIndex)
  ShowAuctionPrice(tooltip, GetMerchantItemLink(merchantIndex), MerchantItemStackCount(merchantIndex))
end

tooltipHandlers.SetBuybackItem = TooltipHandlerFromLinkAndCount(GetBuybackItemLink, GetBuybackItemInfo, 4)

tooltipHandlers.SetGuildBankItem = function(tooltip, tabIndex, slotIndex)
  local _, stackCount = GetGuildBankItemInfo(tabIndex, slotIndex)
  ShowAuctionPrice(tooltip, GetGuildBankItemLink(tabIndex, slotIndex), stackCount)
end

tooltipHandlers.SetLootItem = function(tooltip, lootSlot)
  if LootSlotHasItem(lootSlot) then
    local itemLink, _, stackCount = GetLootSlotLink(lootSlot)
    ShowAuctionPrice(tooltip, itemLink, stackCount)
  end
end

tooltipHandlers.SetLootRollItem = TooltipHandlerFromLinkAndCount(GetLootRollItemLink, GetLootRollItemInfo, 3)

tooltipHandlers.SetQuestItem = TooltipHandlerFromLinkAndCount(GetQuestItemLink, GetQuestItemInfo, 3)

tooltipHandlers.SetQuestLogItem = function(tooltip, rewardKind, rewardIndex)
  local stackCount
  if rewardKind == "choice" then
    stackCount = select(3, GetQuestLogChoiceInfo(rewardIndex))
  else
    stackCount = select(3, GetQuestLogRewardInfo(rewardIndex))
  end
  ShowAuctionPrice(tooltip, GetQuestLogItemLink(rewardKind, rewardIndex), stackCount)
end

tooltipHandlers.SetSendMailItem = TooltipHandlerFromLinkAndCount(GetSendMailItemLink, GetSendMailItem, 4)

tooltipHandlers.SetInboxItem = function(tooltip, mailIndex, attachmentIndex)
  local resolvedAttachmentIndex = attachmentIndex or 1
  local _, _, _, stackCount = GetInboxItem(mailIndex, resolvedAttachmentIndex)
  ShowAuctionPrice(tooltip, GetInboxItemLink(mailIndex, resolvedAttachmentIndex), stackCount)
end

tooltipHandlers.SetTradePlayerItem = TradeWindowTooltipHandler(GetTradePlayerItemLink, GetTradePlayerItemInfo)
tooltipHandlers.SetTradeTargetItem = TradeWindowTooltipHandler(GetTradeTargetItemLink, GetTradeTargetItemInfo)

tooltipHandlers.SetHyperlink = function(tooltip, itemLink)
  ShowAuctionPrice(tooltip, itemLink, 1)
end

tooltipHandlers.SetItemByID = function(tooltip, itemID)
  if itemID then
    ShowAuctionPrice(tooltip, select(2, C_Item.GetItemInfo(itemID)), 1)
  end
end

if GameTooltip.SetItemKey then
  tooltipHandlers.SetItemKey = function(tooltip, itemID, itemLevel, itemSuffix)
    local itemLink
    if C_TooltipInfo and C_TooltipInfo.GetItemKey then
      local itemKeyTooltipInfo = C_TooltipInfo.GetItemKey(itemID, itemLevel, itemSuffix)
      itemLink = itemKeyTooltipInfo and itemKeyTooltipInfo.hyperlink
    end
    if not itemLink and tooltip.GetItem then
      itemLink = select(2, tooltip:GetItem())
    end
    if itemLink and C_Item.GetItemInfoInstant(itemLink) ~= itemID then
      itemLink = select(2, C_Item.GetItemInfo(itemID))
    end
    ShowAuctionPrice(tooltip, itemLink, 1)
  end
end

local function GetRecipeSchematic(recipeID, recipeLevel)
  local schematicRequestSucceeded, schematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, false, recipeLevel)
  if schematicRequestSucceeded and type(schematic) == "table" then
    return schematic
  end
end

local function GetVisibleProfessionRecipeLevel()
  local craftingPage = ProfessionsFrame and ProfessionsFrame.CraftingPage
  if not craftingPage or not craftingPage:IsVisible() then
    return
  end
  local schematicForm = craftingPage.SchematicForm
  if schematicForm and schematicForm.GetCurrentRecipeLevel then
    return schematicForm:GetCurrentRecipeLevel()
  end
end

if GameTooltip.SetRecipeReagentItem then
  tooltipHandlers.SetRecipeReagentItem = function(tooltip, recipeID, reagentSlotID)
    local schematic = GetRecipeSchematic(recipeID, GetVisibleProfessionRecipeLevel())
    if not schematic or not schematic.reagentSlotSchematics then
      return
    end
    for _, reagentSlot in ipairs(schematic.reagentSlotSchematics) do
      if reagentSlot.dataSlotIndex == reagentSlotID and reagentSlot.reagents and reagentSlot.reagents[1] and reagentSlot.reagents[1].itemID then
        ShowAuctionPrice(tooltip, select(2, C_Item.GetItemInfo(reagentSlot.reagents[1].itemID)), reagentSlot.quantityRequired)
        return
      end
    end
  end
end

if GameTooltip.SetRecipeResultItem then
  tooltipHandlers.SetRecipeResultItem = function(tooltip, recipeID, reagents, allocations, recipeLevel)
    local craftedItemLink
    local outputRequestSucceeded, recipeOutput = pcall(C_TradeSkillUI.GetRecipeOutputItemData, recipeID, reagents, allocations)
    if outputRequestSucceeded and type(recipeOutput) == "table" then
      craftedItemLink = recipeOutput.hyperlink
    elseif outputRequestSucceeded and type(recipeOutput) == "string" then
      craftedItemLink = recipeOutput
    end
    local schematic = GetRecipeSchematic(recipeID, recipeLevel)
    local craftedQuantity = (schematic and schematic.quantityMin) or 1
    ShowAuctionPrice(tooltip, craftedItemLink, craftedQuantity)
  end
end

local function RunTooltipHandler(tooltip, getterName, getterArguments)
  local tooltipHandler = tooltipHandlers[getterName]
  if tooltipHandler then
    tooltipHandler(tooltip, unpack(getterArguments))
  end
end

local function TooltipBelongsToAddon(tooltip)
  if tooltip == GameTooltip or tooltip == ItemRefTooltip then
    return true
  end
  if tooltip.IsForbidden and tooltip:IsForbidden() then
    return false
  end
  local tooltipName = tooltip.GetName and tooltip:GetName() or ""
  return tooltipName:match("^NotGameTooltip") ~= nil
end

local tooltipHookRegistered = false

function AuctionPrices.Tooltips.InstallHooks()
  if tooltipHookRegistered then
    return
  end
  tooltipHookRegistered = true

  if not TooltipDataProcessor or not Enum or not Enum.TooltipDataType then
    return
  end

  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tooltipData)
    if not TooltipBelongsToAddon(tooltip) then
      return
    end
    local tooltipInfo = tooltip.info or tooltip.processingInfo
    if tooltipInfo and tooltipInfo.getterName and not tooltipInfo.excludeLines then
      local handlerName = tooltipInfo.getterName:gsub("^Get", "Set")
      if tooltipHandlers[handlerName] then
        pcall(RunTooltipHandler, tooltip, handlerName, tooltipInfo.getterArgs or {})
        return
      end
    end
    if tooltipData and tooltipData.id then
      ShowAuctionPrice(tooltip, select(2, C_Item.GetItemInfo(tooltipData.id)), 1)
    end
  end)
end
