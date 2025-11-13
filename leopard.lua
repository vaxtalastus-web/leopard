local config = { spaces = 3 }
local str = string
local sub, format, rep, byte, match, gsub = str.sub, str.format, str.rep, str.byte, str.match, str.gsub
local info = debug.info
local huge = math.huge
local Type, Pairs, Tostring, concat = type, pairs, tostring, table.concat
local Tab = rep(" ", config.spaces or 4)
local Serialize, SerializeCompress

local function SerializeArgs(...)
    local Serialized = {}
    for i, v in Pairs({...}) do
        local valueType = Type(v)
        local SerializeIndex = #Serialized + 1
        if valueType == "string" then
            Serialized[SerializeIndex] = format("\"%s\"", v)
        elseif valueType == "table" then
            Serialized[SerializeIndex] = Serialize(v, 0)
        else
            Serialized[SerializeIndex] = Tostring(v)
        end
    end
    return concat(Serialized, ", ")
end

local function FormatString(str)
    local Pos, String = 1, {}
    while Pos <= #str do
        local Key = sub(str, Pos, Pos)
        if Key == "\n" then
            String[Pos] = "\\n"
        elseif Key == "\t" then
            String[Pos] = "\\t"
        elseif Key == "\"" then
            String[Pos] = "\\\""
        else
            local Code = byte(Key)
            if Code < 32 or Code > 126 then
                String[Pos] = format("\\%d", Code)
            else
                String[Pos] = Key
            end
        end
        Pos += 1
    end
    return concat(String)
end

local function FormatNumber(numb)
    if numb == huge then return "math.huge" end
    if numb == -huge then return "-math.huge" end
    return Tostring(numb)
end

local function FormatFunction(func, checked)
    if info(func, "s") == "[C]" then return "C Function" end
    local getupvalues = getupvalues or (debug and debug.getupvalues) or function() return {} end
    local getconstants = getconstants or (debug and debug.getconstants) or function() return {} end
    local getfunctionhash = getfunctionhash or (debug and debug.getfunctionhash) or function() return "doesnt exist, cannot" end

    local funcData = {}
    local upvalues = getupvalues(func)
    if #upvalues > 0 then funcData.Upvalues = upvalues end
    local constants = getconstants(func)
    if #constants > 0 then funcData.Constants = constants end
    local hash = getfunctionhash(func)
    if hash then funcData.Hash = hash end

    return SerializeCompress(funcData, checked)
end

local function FormatIndex(idx, scope, checked)
    local indexType = Type(idx)
    local finishedFormat = idx
    if indexType == "string" then
        if match(idx, "[^_%a%d]+") then
            finishedFormat = format("\"%s\"", FormatString(idx))
        else
            return idx
        end
    elseif indexType == "table" then
        finishedFormat = scope and Serialize(idx, scope + 1, checked) or SerializeCompress(idx, checked)
    elseif indexType == "number" or indexType == "boolean" then
        finishedFormat = FormatNumber(idx)
    elseif indexType == "function" then
        finishedFormat = FormatFunction(idx, checked)
    end
    return format("[%s]", finishedFormat)
end

SerializeCompress = function(tbl, checked)
    checked = checked or {}
    if checked[tbl] then return format("\"%s -- recursive table\"", Tostring(tbl)) end
    checked[tbl] = true
    local Serialized, numericIndex = {}, 1

    for i, v in Pairs(tbl) do
        local formattedIndex = FormatIndex(i, nil, checked)
        local valueType = Type(v)
        local SerializeIndex = #Serialized + 1
        local isArrayKey = Type(i) == "number" and i == numericIndex
        local prefix = isArrayKey and "" or formattedIndex .. " = "

        if valueType == "string" then
            Serialized[SerializeIndex] = format("%s\"%s\",", prefix, FormatString(v))
        elseif valueType == "number" or valueType == "boolean" then
            Serialized[SerializeIndex] = format("%s%s,", prefix, FormatNumber(v))
        elseif valueType == "table" then
            Serialized[SerializeIndex] = format("%s%s,", prefix, SerializeCompress(v, checked))
        elseif valueType == "userdata" then
            Serialized[SerializeIndex] = format("%snewproxy(),", prefix)
        elseif valueType == "function" then
            Serialized[SerializeIndex] = format("%s%s,", prefix, FormatFunction(v, checked))
        else
            Serialized[SerializeIndex] = format("%s%s,", prefix, Tostring(valueType))
        end

        if isArrayKey then numericIndex += 1 end
    end

    local lastValue = Serialized[#Serialized]
    if lastValue then Serialized[#Serialized] = sub(lastValue, 0, -2) end
    return format("{%s}", concat(Serialized))
end

Serialize = function(tbl, scope, checked)
    checked = checked or {}
    if checked[tbl] then return format("\"%s -- recursive table\"", Tostring(tbl)) end
    checked[tbl] = true
    scope = scope or 0
    local Serialized, scopeTab, scopeTab2, numericIndex = {}, rep(Tab, scope), rep(Tab, scope + 1), 1

    for i, v in Pairs(tbl) do
        local formattedIndex = FormatIndex(i, scope, checked)
        local valueType = Type(v)
        local SerializeIndex = #Serialized + 1
        local isArrayKey = Type(i) == "number" and i == numericIndex
        local prefix = isArrayKey and "" or formattedIndex .. " = "

        if valueType == "string" then
            Serialized[SerializeIndex] = format("%s%s\"%s\",\n", scopeTab2, prefix, FormatString(v))
        elseif valueType == "number" or valueType == "boolean" then
            Serialized[SerializeIndex] = format("%s%s%s,\n", scopeTab2, prefix, FormatNumber(v))
        elseif valueType == "table" then
            Serialized[SerializeIndex] = format("%s%s%s,\n", scopeTab2, prefix, Serialize(v, scope + 1, checked))
        elseif valueType == "userdata" then
            Serialized[SerializeIndex] = format("%s%snewproxy(),\n", scopeTab2, prefix)
        elseif valueType == "function" then
            Serialized[SerializeIndex] = format("%s%s%s,\n", scopeTab2, prefix, FormatFunction(v, checked))
        else
            Serialized[SerializeIndex] = format("%s%s%s,\n", scopeTab2, prefix, Tostring(valueType))
        end

        if isArrayKey then numericIndex += 1 end
    end

    local lastValue = Serialized[#Serialized]
    if lastValue then Serialized[#Serialized] = sub(lastValue, 0, -3) .. "\n" end

    if #Serialized > 0 then
        if scope < 1 then return format("{\n%s}", concat(Serialized)) end
        return format("{\n%s%s}", concat(Serialized), scopeTab)
    else
        return "{}"
    end
end

local Serializer = {}

function Serializer.Serialize(tbl)
    if Type(tbl) ~= "table" then error("invalid argument #1 to 'Serialize' (table expected)") end
    return Serialize(tbl)
end

function Serializer.SerializeCompress(tbl)
    if Type(tbl) ~= "table" then error("invalid argument #1 to 'SerializeCompress' (table expected)") end
    return SerializeCompress(tbl)
end

function Serializer.FormatArguments(...) return SerializeArgs(...) end
function Serializer.FormatString(str)
    if Type(str) ~= "string" then error("invalid argument #1 to 'FormatString' (string expected)") end
    return FormatString(str)
end

function Serializer.UpdateConfig(options)
    if Type(options) ~= "table" then error("invalid argument #1 to 'UpdateConfig' (table expected)") end
    config.spaces = options.spaces or 4
    Tab = rep(" ", config.spaces)
end

return Serializer
