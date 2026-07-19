local json = {}

local function escape_string(value)
    return value:gsub("[\\\"%z\1-\31]", function(char)
        local replacements = {
            ['\\'] = '\\\\',
            ['"'] = '\\"',
            ['\b'] = '\\b',
            ['\f'] = '\\f',
            ['\n'] = '\\n',
            ['\r'] = '\\r',
            ['\t'] = '\\t',
        }
        return replacements[char] or string.format("\\u%04x", char:byte())
    end)
end

local function is_array(value)
    local count = 0
    local maximum = 0
    for key in pairs(value) do
        if type(key) ~= "number" or key < 1 or key % 1 ~= 0 then
            return false
        end
        count = count + 1
        maximum = math.max(maximum, key)
    end
    return maximum == count
end

local function encode(value, stack)
    local value_type = type(value)

    if value_type == "nil" then return "null" end
    if value_type == "boolean" or value_type == "number" then return tostring(value) end
    if value_type == "string" then return '"' .. escape_string(value) .. '"' end
    if value_type ~= "table" then error("Unsupported JSON type: " .. value_type) end
    if stack[value] then error("Cannot encode a cyclic table") end

    stack[value] = true
    local parts = {}

    if is_array(value) then
        for index = 1, #value do
            parts[#parts + 1] = encode(value[index], stack)
        end
        stack[value] = nil
        return "[" .. table.concat(parts, ",") .. "]"
    end

    local keys = {}
    for key in pairs(value) do
        if type(key) ~= "string" then
            error("JSON object keys must be strings")
        end
        keys[#keys + 1] = key
    end

    table.sort(keys)

    for _, key in ipairs(keys) do
        parts[#parts + 1] = encode(key, stack) .. ":" .. encode(value[key], stack)
    end

    stack[value] = nil
    return "{" .. table.concat(parts, ",") .. "}"
end

function json.encode(value)
    return encode(value, {})
end

local function decoder_error(source, index, message)
    error(string.format("JSON error at character %d: %s", index, message))
end

local function skip_whitespace(source, index)
    while true do
        local char = source:sub(index, index)
        if char == " " or char == "\t" or char == "\r" or char == "\n" then
            index = index + 1
        else
            return index
        end
    end
end

local parse_value

local function parse_string(source, index)
    index = index + 1
    local parts = {}

    while index <= #source do
        local char = source:sub(index, index)

        if char == '"' then
            return table.concat(parts), index + 1
        end

        if char == "\\" then
            local escaped = source:sub(index + 1, index + 1)
            local replacements = {
                ['"'] = '"',
                ['\\'] = '\\',
                ['/'] = '/',
                ['b'] = '\b',
                ['f'] = '\f',
                ['n'] = '\n',
                ['r'] = '\r',
                ['t'] = '\t',
            }

            if replacements[escaped] then
                parts[#parts + 1] = replacements[escaped]
                index = index + 2
            elseif escaped == "u" then
                local hex = source:sub(index + 2, index + 5)
                if not hex:match("^%x%x%x%x$") then
                    decoder_error(source, index, "Invalid unicode escape")
                end

                local code = tonumber(hex, 16)

                if code <= 0x7F then
                    parts[#parts + 1] = string.char(code)
                elseif code <= 0x7FF then
                    parts[#parts + 1] = string.char(
                        0xC0 + math.floor(code / 0x40),
                        0x80 + (code % 0x40)
                    )
                else
                    parts[#parts + 1] = string.char(
                        0xE0 + math.floor(code / 0x1000),
                        0x80 + (math.floor(code / 0x40) % 0x40),
                        0x80 + (code % 0x40)
                    )
                end

                index = index + 6
            else
                decoder_error(source, index, "Invalid escape sequence")
            end
        else
            parts[#parts + 1] = char
            index = index + 1
        end
    end

    decoder_error(source, index, "Unterminated string")
end

local function parse_number(source, index)
    local start_index = index
    local allowed = {
        ["-"] = true, ["+"] = true, ["."] = true,
        ["e"] = true, ["E"] = true,
    }

    while index <= #source do
        local char = source:sub(index, index)
        if char:match("%d") or allowed[char] then
            index = index + 1
        else
            break
        end
    end

    local raw = source:sub(start_index, index - 1)
    local value = tonumber(raw)

    if value == nil then
        decoder_error(source, start_index, "Invalid number")
    end

    return value, index
end

local function parse_array(source, index)
    local result = {}
    index = skip_whitespace(source, index + 1)

    if source:sub(index, index) == "]" then
        return result, index + 1
    end

    while true do
        local value
        value, index = parse_value(source, index)
        result[#result + 1] = value
        index = skip_whitespace(source, index)

        local char = source:sub(index, index)

        if char == "]" then
            return result, index + 1
        end

        if char ~= "," then
            decoder_error(source, index, "Expected ',' or ']'")
        end

        index = skip_whitespace(source, index + 1)
    end
end

local function parse_object(source, index)
    local result = {}
    index = skip_whitespace(source, index + 1)

    if source:sub(index, index) == "}" then
        return result, index + 1
    end

    while true do
        if source:sub(index, index) ~= '"' then
            decoder_error(source, index, "Expected object key")
        end

        local key
        key, index = parse_string(source, index)
        index = skip_whitespace(source, index)

        if source:sub(index, index) ~= ":" then
            decoder_error(source, index, "Expected ':'")
        end

        index = skip_whitespace(source, index + 1)

        local value
        value, index = parse_value(source, index)
        result[key] = value
        index = skip_whitespace(source, index)

        local char = source:sub(index, index)

        if char == "}" then
            return result, index + 1
        end

        if char ~= "," then
            decoder_error(source, index, "Expected ',' or '}'")
        end

        index = skip_whitespace(source, index + 1)
    end
end

parse_value = function(source, index)
    index = skip_whitespace(source, index)
    local char = source:sub(index, index)

    if char == '"' then
        return parse_string(source, index)
    elseif char == "{" then
        return parse_object(source, index)
    elseif char == "[" then
        return parse_array(source, index)
    elseif char == "-" or char:match("%d") then
        return parse_number(source, index)
    elseif source:sub(index, index + 3) == "true" then
        return true, index + 4
    elseif source:sub(index, index + 4) == "false" then
        return false, index + 5
    elseif source:sub(index, index + 3) == "null" then
        return nil, index + 4
    end

    decoder_error(source, index, "Unexpected token")
end

function json.decode(source)
    if type(source) ~= "string" then
        error("JSON source must be a string")
    end

    local value, index = parse_value(source, 1)
    index = skip_whitespace(source, index)

    if index <= #source then
        decoder_error(source, index, "Unexpected trailing data")
    end

    return value
end

return json
