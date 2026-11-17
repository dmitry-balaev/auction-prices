AuctionPrices = AuctionPrices or {}

local LOCALE = {
  SCAN = "Сканировать",
  FETCHING = "Получение лотов...",
  FETCHING_TOOLTIP = "Получение лотов с сервера может занимать до одной минуты, пожалуйста, подождите.",
  PROCESSING = "Обработка лотов (%d%%)",
  SCAN_TOOLTIP = "Считать цены всех лотов",
  NEXT_SCAN = "Следующее сканирование доступно через %d мин %d сек",
  SELL_PRICE = "Цена на аукционе:",
  UNKNOWN = "Неизвестно",
  CLEAR_DB = "Очистить базу",
  ITEM_COUNT = "Записей в базе: %d",
  LAST_SCAN = "Последнее сканирование: %s",
  NEVER = "никогда",
}

function AuctionPrices.Text(key, ...)
  local localizedText = LOCALE[key] or key
  if select("#", ...) > 0 then
    return localizedText:format(...)
  end
  return localizedText
end
