local diagnostic = {}

local logger = require("logger")
local storage = require("storage")

local function safe_tostring(value)
    local ok, result = pcall(function()
        return tostring(value)
    end)

    if ok then
        return result
    end

    return "<unprintable>"
end

local function contains_interesting_marker(value, markers)
    if type(value) ~= "string" then
        return false
    end

    local lower_value = value:lower()

    for _, marker in ipairs(markers) do
        if lower_value:find(
            tostring(marker):lower(),
            1,
            true
        ) then
            return true
        end
    end

    return false
end

local function read_field(object, field_name)
    local ok, value = pcall(function()
        return object[field_name]
    end)

    if ok then
        return value
    end

    return nil
end

local function describe_directory(directory)
    local absolute_path =
        read_field(directory, "__absolute_path")
        or read_field(directory, "absolute_path")
        or read_field(directory, "Path")
        or read_field(directory, "path")

    local name =
        read_field(directory, "__name")
        or read_field(directory, "name")
        or read_field(directory, "Name")

    local files =
        read_field(directory, "__files")
        or read_field(directory, "files")
        or read_field(directory, "Files")

    local directories =
        read_field(directory, "__directories")
        or read_field(directory, "directories")
        or read_field(directory, "Directories")

    return {
        absolute_path = absolute_path,
        name = name,
        files = files,
        directories = directories,
    }
end

local function count_table_entries(value)
    if type(value) ~= "table" then
        return 0
    end

    local count = 0

    for _ in pairs(value) do
        count = count + 1
    end

    return count
end

local function log_files(files, config)
    if type(files) ~= "table" then
        return
    end

    local count = 0

    for key, value in pairs(files) do
        count = count + 1

        if count
            > config.diagnostics.maximum_logged_files_per_directory
        then
            logger.log(
                "    ... file log limit reached"
            )
            break
        end

        logger.log(
            "    FILE key="
            .. safe_tostring(key)
            .. " value="
            .. safe_tostring(value)
        )
    end
end

local function try_iterate_game_directories()
    if type(IterateGameDirectories) ~= "function" then
        return nil,
            "IterateGameDirectories is unavailable"
    end

    local ok, result = pcall(function()
        return IterateGameDirectories()
    end)

    if not ok then
        return nil, safe_tostring(result)
    end

    return result, nil
end

local function inspect_iteration_result(result, config)
    local logged = 0
    local visited = 0
    local candidates = {}

    local function inspect_one(key, directory)
        visited = visited + 1

        local description =
            describe_directory(directory)

        local path =
            description.absolute_path
            or description.name
            or safe_tostring(key)

        local interesting =
            contains_interesting_marker(
                safe_tostring(path),
                config.diagnostics.interesting_markers
            )

        local file_count =
            count_table_entries(
                description.files
            )

        local directory_count =
            count_table_entries(
                description.directories
            )

        if interesting then
            candidates[#candidates + 1] = {
                path = safe_tostring(path),
                file_count = file_count,
                directory_count = directory_count,
            }
        end

        if interesting
            or logged
                < config.diagnostics.maximum_logged_directories
        then
            logged = logged + 1

            logger.log(string.format(
                "DIR #%d | key=%s | name=%s | path=%s | files=%d | subdirs=%d | interesting=%s",
                visited,
                safe_tostring(key),
                safe_tostring(description.name),
                safe_tostring(description.absolute_path),
                file_count,
                directory_count,
                tostring(interesting)
            ))

            if interesting then
                log_files(
                    description.files,
                    config
                )
            end
        end
    end

    if type(result) == "table" then
        for key, directory in pairs(result) do
            inspect_one(key, directory)
        end
    elseif type(result) == "function" then
        while true do
            local ok, key, directory = pcall(result)

            if not ok then
                logger.log(
                    "Directory iterator call failed: "
                    .. safe_tostring(key)
                )
                break
            end

            if key == nil and directory == nil then
                break
            end

            inspect_one(key, directory)
        end
    else
        logger.log(
            "Unexpected IterateGameDirectories result type: "
            .. type(result)
            .. " | "
            .. safe_tostring(result)
        )
    end

    return visited, candidates
end

local function test_known_paths()
    local paths = {
        {
            label = "Current mod Schematics",
            path = storage.get_schematics_directory(),
        },
        {
            label = "Current mod root",
            path = storage.get_mod_directory(),
        },
    }

    logger.log(
        "=== DIRECT FILE ACCESS TESTS ==="
    )

    for _, entry in ipairs(paths) do
        local index_path =
            entry.path .. "index.txt"

        local file = io.open(
            index_path,
            "r"
        )

        if file then
            file:close()

            logger.log(
                entry.label
                .. " readable | "
                .. index_path
            )
        else
            logger.log(
                entry.label
                .. " not readable through index test | "
                .. index_path
            )
        end
    end
end

local function log_candidate_summary(candidates)
    logger.log(
        "=== INTERESTING DIRECTORY SUMMARY ==="
    )

    if #candidates == 0 then
        logger.log(
            "No interesting directory candidate was found."
        )
        return
    end

    table.sort(
        candidates,
        function(left, right)
            return left.path:lower()
                < right.path:lower()
        end
    )

    for index, candidate in ipairs(candidates) do
        logger.log(string.format(
            "CANDIDATE #%d | %s | files=%d | subdirs=%d",
            index,
            candidate.path,
            candidate.file_count,
            candidate.directory_count
        ))
    end
end

function diagnostic.run(config)
    logger.log(
        "=== UE4SS DIRECTORY DIAGNOSTIC START ==="
    )

    test_known_paths()

    logger.log(
        "Calling IterateGameDirectories()..."
    )

    local result, iterate_error =
        try_iterate_game_directories()

    if not result then
        logger.log(
            "IterateGameDirectories failed: "
            .. safe_tostring(iterate_error)
        )

        logger.log(
            "=== UE4SS DIRECTORY DIAGNOSTIC END ==="
        )

        return false, iterate_error
    end

    logger.log(
        "IterateGameDirectories returned type: "
        .. type(result)
    )

    local visited, candidates =
        inspect_iteration_result(
            result,
            config
        )

    logger.log(
        "Visited directory entries: "
        .. tostring(visited)
    )

    log_candidate_summary(candidates)

    logger.log(
        "Recommended next decision:"
    )

    local found_schematics = false
    local found_saved = false

    for _, candidate in ipairs(candidates) do
        local lower_path =
            candidate.path:lower()

        if lower_path:find(
            "palschematica",
            1,
            true
        )
            or lower_path:find(
                "schematics",
                1,
                true
            )
        then
            found_schematics = true
        end

        if lower_path:find(
            "saved",
            1,
            true
        )
        then
            found_saved = true
        end
    end

    if found_schematics then
        logger.log(
            "Current PalSchematica/Schematics path appears visible. "
            .. "Next phase can scan it natively."
        )
    elseif found_saved then
        logger.log(
            "Current mod folder is not visible, but a Saved path is. "
            .. "Next phase should move persistent data there."
        )
    else
        logger.log(
            "Neither the current mod folder nor a useful Saved path "
            .. "was found. A small native filesystem helper may be required."
        )
    end

    logger.log(
        "=== UE4SS DIRECTORY DIAGNOSTIC END ==="
    )

    return true, nil
end

return diagnostic
