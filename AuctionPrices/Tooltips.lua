AuctionPrices.Tooltips = {}

local function StackSize(stackCount)
  if not stackCount or stackCount < 1 then
    return 1
  end
  return stackCount
end

local function ShowAuctionPrice(tooltip, itemLink, stackCount)
  if not itemLink or not itemLink:find("item:", 1, true) or AuctionPrices.ItemLinkIsSoulbound(itemLink) then
    return
  end
  local unitPrice = AuctionPrices.GetStoredUnitPrice(itemLink)
  local priceText = unitPrice and AuctionPrices.FormatMoney(unitPrice * StackSize(stackCount)) or AuctionPrices.Text("UNKNOWN")
  tooltip:AddLine(WHITE_FONT_COLOR:WrapTextInColorCode(AuctionPrices.Text("AUCTION_PRICE") .. " " .. priceText))
end

local function ItemLinkByID(itemID)
  return select(2, C_Item.GetItemInfo(itemID))
end

local function LinkAndCountHandler(getItemLink, getItemInfo, stackCountReturnIndex)
  return function(tooltip, firstArgument, secondArgument)
    local stackCount = select(stackCountReturnIndex, getItemInfo(firstArgument, secondArgument))
    ShowAuctionPrice(tooltip, getItemLink(firstArgument, secondArgument), stackCount)
  end
end

local function RecipeLevelOfOpenProfession()
  local craftingPage = ProfessionsFrame and ProfessionsFrame.CraftingPage
  if craftingPage and craftingPage:IsVisible() then
    return craftingPage.SchematicForm:GetCurrentRecipeLevel()
  end
end

local function ReagentInSlot(schematic, reagentSlotID)
  for _, reagentSlot in ipairs(schematic.reagentSlotSchematics) do
    if reagentSlot.dataSlotIndex == reagentSlotID then
      return reagentSlot.reagents[1], reagentSlot.quantityRequired
    end
  end
end

local tooltipHandlers = {}

tooltipHandlers.SetBagItem = function(tooltip, bagID, slotID)
  local containerItemInfo = C_Container.GetContainerItemInfo(bagID, slotID)
  if containerItemInfo and not AuctionPrices.IsBagItemBound(containerItemInfo) then
    ShowAuctionPrice(tooltip, containerItemInfo.hyperlink, containerItemInfo.stackCount)
  end
end

tooltipHandlers.SetInventoryItem = function(tooltip, unit, slotID)
  ShowAuctionPrice(tooltip, GetInventoryItemLink(unit, slotID), GetInventoryItemCount(unit, slotID))
end

tooltipHandlers.SetMerchantItem = function(tooltip, merchantIndex)
  local merchantItem = C_MerchantFrame.GetItemInfo(merchantIndex)
  ShowAuctionPrice(tooltip, GetMerchantItemLink(merchantIndex), merchantItem and merchantItem.stackCount)
end

tooltipHandlers.SetBuybackItem = LinkAndCountHandler(GetBuybackItemLink, GetBuybackItemInfo, 4)
tooltipHandlers.SetLootRollItem = LinkAndCountHandler(GetLootRollItemLink, GetLootRollItemInfo, 3)
tooltipHandlers.SetQuestItem = LinkAndCountHandler(GetQuestItemLink, GetQuestItemInfo, 3)
tooltipHandlers.SetSendMailItem = LinkAndCountHandler(GetSendMailItemLink, GetSendMailItem, 4)
tooltipHandlers.SetTradePlayerItem = LinkAndCountHandler(GetTradePlayerItemLink, GetTradePlayerItemInfo, 3)
tooltipHandlers.SetTradeTargetItem = LinkAndCountHandler(GetTradeTargetItemLink, GetTradeTargetItemInfo, 3)

tooltipHandlers.SetGuildBankItem = function(tooltip, tabID, slotID)
  local _, stackCount = GetGuildBankItemInfo(tabID, slotID)
  ShowAuctionPrice(tooltip, GetGuildBankItemLink(tabID, slotID), stackCount)
end

tooltipHandlers.SetLootItem = function(tooltip, lootSlot)
  if not LootSlotHasItem(lootSlot) then
    return
  end
  local itemLink, _, stackCount = GetLootSlotLink(lootSlot)
  ShowAuctionPrice(tooltip, itemLink, stackCount)
end

tooltipHandlers.SetQuestLogItem = function(tooltip, rewardKind, rewardIndex)
  local getRewardInfo = rewardKind == "choice" and GetQuestLogChoiceInfo or GetQuestLogRewardInfo
  local stackCount = select(3, getRewardInfo(rewardIndex))
  ShowAuctionPrice(tooltip, GetQuestLogItemLink(rewardKind, rewardIndex), stackCount)
end

tooltipHandlers.SetInboxItem = function(tooltip, mailIndex, attachmentIndex)
  attachmentIndex = attachmentIndex or 1
  local _, _, _, stackCount = GetInboxItem(mailIndex, attachmentIndex)
  ShowAuctionPrice(tooltip, GetInboxItemLink(mailIndex, attachmentIndex), stackCount)
end

tooltipHandlers.SetHyperlink = function(tooltip, itemLink)
  ShowAuctionPrice(tooltip, itemLink, 1)
end

tooltipHandlers.SetItemByID = function(tooltip, itemID)
  ShowAuctionPrice(tooltip, ItemLinkByID(itemID), 1)
end

tooltipHandlers.SetItemKey = function(tooltip, itemID, itemLevel, itemSuffix)
  local itemKeyInfo = C_TooltipInfo.GetItemKey(itemID, itemLevel, itemSuffix)
  local itemLink = itemKeyInfo and itemKeyInfo.hyperlink or select(2, tooltip:GetItem())
  if not itemLink or C_Item.GetItemInfoInstant(itemLink) ~= itemID then
    itemLink = ItemLinkByID(itemID)
  end
  ShowAuctionPrice(tooltip, itemLink, 1)
end

tooltipHandlers.SetRecipeReagentItem = function(tooltip, recipeID, reagentSlotID)
  local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false, RecipeLevelOfOpenProfession())
  local reagent, quantityRequired = ReagentInSlot(schematic, reagentSlotID)
  if reagent then
    ShowAuctionPrice(tooltip, ItemLinkByID(reagent.itemID), quantityRequired)
  end
end

tooltipHandlers.SetRecipeResultItem = function(tooltip, recipeID, reagents, allocations, recipeLevel)
  local schematic = C_TradeSkillUI.GetRecipeSchematic(recipeID, false, recipeLevel)
  local recipeOutput = C_TradeSkillUI.GetRecipeOutputItemData(recipeID, reagents, allocations)
  ShowAuctionPrice(tooltip, recipeOutput and recipeOutput.hyperlink, schematic.quantityMin)
end

local function AddAuctionPrice(tooltip, tooltipData)
  local tooltipInfo = tooltip.info or tooltip.processingInfo
  local handlerName = tooltipInfo and tooltipInfo.getterName and tooltipInfo.getterName:gsub("^Get", "Set")
  local tooltipHandler = handlerName and not tooltipInfo.excludeLines and tooltipHandlers[handlerName]
  if tooltipHandler then
    tooltipHandler(tooltip, unpack(tooltipInfo.getterArgs or {}))
    return
  end
  if tooltipData.id then
    ShowAuctionPrice(tooltip, ItemLinkByID(tooltipData.id), 1)
  end
end

local function IsPriceTooltip(tooltip)
  if tooltip == GameTooltip or tooltip == ItemRefTooltip then
    return true
  end
  local tooltipName = tooltip:GetName()
  return tooltipName ~= nil and tooltipName:match("^NotGameTooltip") ~= nil
end

function AuctionPrices.Tooltips.InstallHooks()
  TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Item, function(tooltip, tooltipData)
    if tooltip:IsForbidden() or not IsPriceTooltip(tooltip) then
      return
    end
    AddAuctionPrice(tooltip, tooltipData)
  end)
end
