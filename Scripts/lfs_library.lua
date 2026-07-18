local lfs_library = {}

local json = require("json")
local logger = require("logger")
local storage = require("storage")

local function normalize_path(path)
    return tostring(path):gsub("\\", "/")
end

local function ends_with_ignore_case(value, suffix)
    value = tostring(value):lower()
    suffix = tostring(suffix):lower()

    return value:sub(-#suffix) == suffix
end

local function safe_require_lfs()
    local ok, module_or_error = pcall(function()
        return require("lfs")
    end)

    if not ok then
        return nil, tostring(module_or_error)
    end

    if type(module_or_error) ~= "table" then
        return nil,
            "require('lfs') returned unexpected type: "
            .. type(module_or_error)
    end

    if type(module_or_error.dir) ~= "function" then
        return nil,
            "LuaFileSystem module does not expose lfs.dir"
    end

    return module_or_error, nil
end

local function read_manifest(path)
    local file = io.open(path, "rb")

    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()

    local ok, document = pcall(function()
        return json.decode(content)
    end)

    if not ok or type(document) ~= "table" then
        return nil
    end

    return document
end

local function write_manifest(path, document)
    local encoded = json.encode(document)

    local file, open_error =
        io.open(path, "wb")

    if not file then
        return false, tostring(open_error)
    end

    file:write(encoded)
    file:close()

    return true, nil
end

local function get_attributes(lfs, path)
    local ok, attributes = pcall(function()
        return lfs.attributes(path)
    end)

    if ok and type(attributes) == "table" then
        return attributes
    end

    return nil
end

local function scan_directory(lfs, directory, config)
    local filenames = {}
    local logged = 0

    logger.log(
        "Scanning directory with lfs.dir: "
        .. normalize_path(directory)
    )

    local ok, iterator_or_error, directory_object =
        pcall(function()
            return lfs.dir(directory)
        end)

    if not ok then
        return nil, tostring(iterator_or_error)
    end

    local iterator = iterator_or_error

    if type(iterator) ~= "function" then
        return nil,
            "lfs.dir returned unexpected iterator type: "
            .. type(iterator)
    end

    while true do
        local next_ok, filename =
            pcall(iterator, directory_object)

        if not next_ok then
            return nil,
                "lfs.dir iterator failed: "
                .. tostring(filename)
        end

        if filename == nil then
            break
        end

        if filename ~= "."
            and filename ~= ".."
        then
            logged = logged + 1

            if logged
                <= config.diagnostics
                    .maximum_logged_files
            then
                logger.log(
                    "LFS ENTRY: "
                    .. tostring(filename)
                )
            end

            if ends_with_ignore_case(
                filename,
                ".palschem"
            ) then
                filenames[#filenames + 1] =
                    filename
            end
        end
    end

    table.sort(
        filenames,
        function(left, right)
            return left:lower()
                < right:lower()
        end
    )

    return filenames, nil
end

local function build_manifest(
    lfs,
    directory,
    filenames,
    config
)
    local previous_manifest =
        read_manifest(
            directory
            .. config.library.manifest_filename
        )

    local selected_file = nil

    if previous_manifest
        and type(previous_manifest.selectedFile)
            == "string"
    then
        selected_file =
            previous_manifest.selectedFile
    end

    local schematics = {}

    for _, filename in ipairs(filenames) do
        local path = directory .. filename
        local attributes =
            get_attributes(lfs, path)

        schematics[#schematics + 1] = {
            file = filename,
            size =
                attributes
                and attributes.size
                or nil,
            modifiedAt =
                attributes
                and attributes.modification
                or nil,
        }
    end

    if not selected_file
        and #filenames > 0
    then
        selected_file = filenames[1]
    end

    local selected_still_exists = false

    for _, filename in ipairs(filenames) do
        if filename == selected_file then
            selected_still_exists = true
            break
        end
    end

    if not selected_still_exists then
        selected_file = filenames[1]
    end

    return {
        format =
            config.library.manifest_format,
        formatVersion =
            config.library.manifest_format_version,
        generatedAt = os.time(),
        selectedFile = selected_file,
        schematicCount = #filenames,
        schematics = schematics,
    }
end

function lfs_library.run(config)
    logger.log(
        "=== LUAFILESYSTEM LIBRARY TEST START ==="
    )

    local lfs, lfs_error =
        safe_require_lfs()

    if not lfs then
        logger.log(
            "LuaFileSystem unavailable: "
            .. tostring(lfs_error)
        )

        logger.log(
            "RESULT: LFS_UNAVAILABLE"
        )

        logger.log(
            "=== LUAFILESYSTEM LIBRARY TEST END ==="
        )

        return false, lfs_error
    end

    logger.log(
        "LuaFileSystem loaded successfully"
    )

    local directory =
        storage.get_schematics_directory()

    local filenames, scan_error =
        scan_directory(
            lfs,
            directory,
            config
        )

    if not filenames then
        logger.log(
            "LuaFileSystem directory scan failed: "
            .. tostring(scan_error)
        )

        logger.log(
            "RESULT: LFS_PRESENT_BUT_SCAN_FAILED"
        )

        logger.log(
            "=== LUAFILESYSTEM LIBRARY TEST END ==="
        )

        return false, scan_error
    end

    logger.log(
        "LuaFileSystem discovered "
        .. tostring(#filenames)
        .. " .palschem file(s)"
    )

    for index, filename in ipairs(filenames) do
        logger.log(string.format(
            "FOUND [%d/%d] %s",
            index,
            #filenames,
            filename
        ))
    end

    local manifest =
        build_manifest(
            lfs,
            directory,
            filenames,
            config
        )

    local manifest_path =
        directory
        .. config.library.manifest_filename

    local written, write_error =
        write_manifest(
            manifest_path,
            manifest
        )

    if not written then
        logger.log(
            "Manifest write failed: "
            .. tostring(write_error)
        )

        logger.log(
            "RESULT: LFS_SCAN_OK_MANIFEST_WRITE_FAILED"
        )

        logger.log(
            "=== LUAFILESYSTEM LIBRARY TEST END ==="
        )

        return false, write_error
    end

    logger.log(
        "Manifest generated successfully: "
        .. normalize_path(manifest_path)
    )

    logger.log(
        "Manifest schematic count: "
        .. tostring(manifest.schematicCount)
    )

    logger.log(
        "Manifest selected file: "
        .. tostring(manifest.selectedFile)
    )

    logger.log(
        "RESULT: LFS_FULL_SUCCESS"
    )

    logger.log(
        "=== LUAFILESYSTEM LIBRARY TEST END ==="
    )

    return true, manifest
end

return lfs_library
