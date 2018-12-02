WebBanking {
  version = 1.0,
  country = "de",
  url = "http://deutschlandcard.de",
  services    = {"Deutschlandcard-Punkte"},
  description = string.format(MM.localizeText("Get points of %s"), "Deutschlandcard account")
}

function SupportsBank (protocol, bankCode)
  return bankCode == "Deutschlandcard-Punkte" and protocol == ProtocolWebBanking
end


local function dump(o)
  if type(o) == 'table' then
     local s = '{ '
     for k,v in pairs(o) do
        if type(k) ~= 'number' then k = '"'..k..'"' end
        s = s .. '['..k..'] = ' .. dump(v) .. ','
     end
     return s .. '} '
  else
     return tostring(o)
  end
end


-- ---------------------------------------------------------------------------------------------------------------------
-- Data Converters
-- ---------------------------------------------------------------------------------------------------------------------

-- "+26 Punkte" -> 0.26
local function PointstringToCurrency(points)
  print(points)
  local pointvalue = string.match(points, "[-+]%d+")
  local pointnumber = tonumber(pointvalue)
  return pointvalue / 100.0
end

local monthMappingTable = {
  [" Januar "] = "01.",
  [" Februar "] = "02.",
  [" März "] = "03.",
  [" April "] = "04.",
  [" Mai "] = "05.",
  [" Juni "] = "06.",
  [" Juli "] = "07.",
  [" August "] = "08.",
  [" September "] = "09.",
  [" Oktober "] = "10.",
  [" November "] = "11.",
  [" Dezember "] = "12.",
}

local function DatestringToPosixTime(date)
  for key,value in pairs(monthMappingTable) do 
    date = date:gsub(key,value)
  end

  day, month, year = string.match(date,"(%d%d)%.(%d%d)%.(%d%d%d%d)")

  return os.time{year=year, month=month, day=day, hour=0}
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Session Handling
-- ---------------------------------------------------------------------------------------------------------------------

local connection
local accountNumber

function InitializeSession (protocol, bankCode, username, username2, password, username3)
  connection = Connection()

  formData = "redirect_obj_id=7306&login-method=pin&cardnumber=" .. username .. "&pin=" .. password

  content, charset, mimeType = connection:request("POST",
                                                  "https://www.deutschlandcard.de/participant/authenticateAsync",
                                                  formData,
                                                  "application/x-www-form-urlencoded; charset=UTF-8")

  accountNumber = username
  return nil
end

function EndSession ()
  content, charset, mimeType = connection:get("https://www.deutschlandcard.de/participant/logout")

  return nil
end

-- ---------------------------------------------------------------------------------------------------------------------
-- Account Handling
-- ---------------------------------------------------------------------------------------------------------------------
local function loadFile(filename)
  local file = assert(io.open("/Users/christianbecker/Library/Containers/com.moneymoney-app.retail/Data/Library/Application Support/MoneyMoney/Extensions/" .. filename, "r"))
  local content = file:read("*all")
  file:close()
  return content
end


function ListAccounts (knownAccounts)
  content = connection:get("https://www.deutschlandcard.de")
  html = HTML(content)
  userName = html:xpath('//span[@class="my-name"]')

  -- Return array of accounts.
  local account = {
    name = "Deutschlandcard Punkte",
    owner = userName:text(),
    accountNumber = accountNumber,
    currency = "EUR",
    type = AccountTypeOther
  }
  return {account}
end


-- curl "https://www.deutschlandcard.de/participant/get_points_json
--       ?dateto=31.07.2018&datefrom=01.07.2018"
local function LoadTransactions(fromDate)
  local to = os.time(os.date('*t'))
  local toDate = os.date('%d.%m.%Y', to)
  local params = "datefrom='" .. fromDate .. "'&dateto='" .. toDate .. "'"

  local uri = "https://www.deutschlandcard.de/participant/get_points_json" .. "?" .. params

  local content, charset, mimeType = connection:request("GET",
                                                        uri,
                                                        "Accept: application/json")
  return content
end


function RefreshAccount (account, since)
  -- Load Balances
  content = connection:get("https://www.deutschlandcard.de")
  local html = HTML(content)
  local pointstring = html:xpath('//span[@class="my-points"]'):text()
  local points = string.match(pointstring, "%d+")
  local pointvalue = tonumber(points) / 100.0

  -- Load Transactions
  local json = LoadTransactions(os.date('%d.%m.%Y', since))
  local fields = JSON(json):dictionary()

  local transactions = {}

  for i,t in ipairs(fields["text"]) do
    items = t["items"]
    if (type(items) == "table") then
      for j, item in ipairs(items) do
        local transaction = {
          name = item["partner"],
          amount = PointstringToCurrency(item["amount"]),
          purpose = item["bookingType"],
          bookingDate = DatestringToPosixTime(item["shoppingDate"]),
          valueDate = DatestringToPosixTime(item["bookingDate"])
        }

        table.insert(transactions, transaction)
      end
    end
  end

  return {balance=pointvalue, transactions=transactions}
end
