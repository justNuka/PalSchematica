local storage = {}

local scripts_directory = debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])")
local mod_directory = scripts_directory:gsub("[Ss]cripts[\\/]$", "")
local schematics_directory = mod_directory .. "Schematics/"

function storage.get_schematics_directory()
    return schematics_directory
end

function storage.read_text_file(filename)
    local path = schematics_directory .. filename
    local file, error_message = io.open(path, "rb")

    if not file then
        return nil, error_message, path
    end

    local content = file:read("*a")
    file:close()

    if not content then
        return nil, "Unable to read file content", path
    end

    return content, nil, path
end

return storage
