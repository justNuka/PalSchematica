local logger = {}

local scripts_directory = debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])")
local mod_directory = scripts_directory:gsub("[Ss]cripts[\\/]$", "")
local log_path = mod_directory .. "PalSchematica.log"

local function timestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

function logger.get_path()
    return log_path
end

function logger.clear()
    local file, error_message = io.open(log_path, "w")
    if not file then
        print(string.format(
            "[PalSchematica] Unable to clear dedicated log: %s\n",
            tostring(error_message)
        ))
        return false
    end

    file:write(string.format("[%s] PalSchematica log started\n", timestamp()))
    file:close()
    return true
end

function logger.log(message)
    local plain_message = tostring(message)
    print(string.format("[PalSchematica] %s\n", plain_message))

    local file, error_message = io.open(log_path, "a")
    if not file then
        print(string.format(
            "[PalSchematica] Unable to write dedicated log: %s\n",
            tostring(error_message)
        ))
        return false
    end

    file:write(string.format("[%s] %s\n", timestamp(), plain_message))
    file:flush()
    file:close()
    return true
end

return logger
