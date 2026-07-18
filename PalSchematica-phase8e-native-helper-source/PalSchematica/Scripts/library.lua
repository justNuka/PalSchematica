local library = {}

local json = require("json")
local logger = require("logger")
local storage = require("storage")
local build_catalog = require("build_catalog")

local entries = {}
local selected_index = 0
local pending_delete_path = nil
local pending_delete_time = 0

local function file_extension(filename)
    return filename:match("%.([^%.\\/]+)$")
end

local function basename(path)
    return path:match("([^\\/]+)$") or path
end

local function read_manifest(config)
    local directory =
        storage.get_schematics_directory()

    local manifest_path =
        directory
        .. config.library.manifest_filename

    local file = io.open(manifest_path, "rb")

    if not file then
        return nil,
            "Native manifest not found: "
            .. tostring(manifest_path)
            .. ". Ensure PalSchematicaFilesystem is enabled."
    end

    local content = file:read("*a")
    file:close()

    local decode_ok, document = pcall(function()
        return json.decode(content)
    end)

    if not decode_ok or type(document) ~= "table" then
        return nil,
            "Invalid library manifest JSON: "
            .. tostring(document)
    end

    if document.format
        ~= config.library.manifest_format
    then
        return nil,
            "Unexpected manifest format: "
            .. tostring(document.format)
    end

    if document.formatVersion
        ~= config.library.manifest_format_version
    then
        return nil,
            "Unsupported manifest version: "
            .. tostring(document.formatVersion)
    end

    if type(document.schematics) ~= "table" then
        return nil,
            "Manifest schematics must be an array"
    end

    return document, nil
end

local function list_palschem_files(config)
    local manifest, manifest_error =
        read_manifest(config)

    if not manifest then
        return nil, manifest_error
    end

    local filenames = {}
    local seen = {}

    for _, record in ipairs(
        manifest.schematics
    ) do
        local filename = nil

        if type(record) == "table" then
            filename = record.file
        elseif type(record) == "string" then
            filename = record
        end

        if type(filename) == "string"
            and filename ~= ""
        then
            filename = basename(filename)

            local extension =
                file_extension(filename)

            if extension
                and extension:lower()
                    == "palschem"
                and not seen[
                    filename:lower()
                ]
            then
                seen[filename:lower()] =
                    true

                filenames[
                    #filenames + 1
                ] = filename
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

local function get_file_size(path)
    local file = io.open(path, "rb")

    if not file then
        return nil
    end

    local size = file:seek("end")
    file:close()

    return size
end

local function validate_vector(value, name)
    if type(value) ~= "table" then
        return false, name .. " must be an object"
    end

    for _, axis in ipairs({"x", "y", "z"}) do
        local number = value[axis]

        if type(number) ~= "number"
            or number ~= number
            or number == math.huge
            or number == -math.huge
        then
            return false,
                name .. "." .. axis .. " must be a finite number"
        end
    end

    return true
end

local function validate_rotation(value, name)
    if type(value) ~= "table" then
        return false, name .. " must be an object"
    end

    for _, axis in ipairs({"pitch", "yaw", "roll"}) do
        local number = value[axis]

        if type(number) ~= "number"
            or number ~= number
            or number == math.huge
            or number == -math.huge
        then
            return false,
                name .. "." .. axis .. " must be a finite number"
        end
    end

    return true
end

local function analyze_document(document)
    local analysis = {
        valid = false,
        fatal_errors = {},
        warnings = {},
        piece_count = 0,
        compatible_piece_count = 0,
        unknown_piece_count = 0,
        class_counts = {},
        unknown_classes = {},
    }

    local function fatal(message)
        analysis.fatal_errors[
            #analysis.fatal_errors + 1
        ] = message
    end

    local function warning(message)
        analysis.warnings[
            #analysis.warnings + 1
        ] = message
    end

    if type(document) ~= "table" then
        fatal("Root JSON value must be an object")
        return analysis
    end

    if document.format ~= "PalSchematica" then
        fatal(
            "Unsupported format: "
            .. tostring(document.format)
        )
    end

    if type(document.formatVersion) ~= "number" then
        fatal("formatVersion must be a number")
    elseif document.formatVersion > 1 then
        fatal(
            "File format is newer than this mod: "
            .. tostring(document.formatVersion)
        )
    elseif document.formatVersion < 1 then
        fatal(
            "Unsupported old format version: "
            .. tostring(document.formatVersion)
        )
    end

    if type(document.metadata) ~= "table" then
        warning("metadata is absent")
    end

    if type(document.pieces) ~= "table" then
        fatal("pieces must be an array")
        return analysis
    end

    if #document.pieces == 0 then
        fatal("The schematic contains no pieces")
        return analysis
    end

    analysis.piece_count = #document.pieces

    for index, piece in ipairs(document.pieces) do
        local prefix = "pieces[" .. tostring(index) .. "]"

        if type(piece) ~= "table" then
            fatal(prefix .. " must be an object")
        else
            if type(piece.class) ~= "string"
                or piece.class == ""
            then
                fatal(prefix .. ".class is required")
            end

            if type(piece.classPath) ~= "string"
                or piece.classPath == ""
                or not piece.classPath:find(
                    "^/Game/Pal/",
                    1
                )
            then
                fatal(
                    prefix
                    .. ".classPath must reference /Game/Pal/"
                )
            end

            local ok, error_message =
                validate_vector(
                    piece.relativeLocation,
                    prefix .. ".relativeLocation"
                )

            if not ok then fatal(error_message) end

            ok, error_message =
                validate_rotation(
                    piece.relativeRotation,
                    prefix .. ".relativeRotation"
                )

            if not ok then fatal(error_message) end

            ok, error_message =
                validate_vector(
                    piece.scale,
                    prefix .. ".scale"
                )

            if not ok then
                fatal(error_message)
            elseif piece.scale.x <= 0
                or piece.scale.y <= 0
                or piece.scale.z <= 0
            then
                fatal(prefix .. ".scale must be positive")
            end

            if type(piece.class) == "string"
                and piece.class ~= ""
            then
                analysis.class_counts[piece.class] =
                    (analysis.class_counts[piece.class] or 0)
                    + 1

                local meshes =
                    build_catalog[piece.class]

                if meshes and #meshes > 0 then
                    analysis.compatible_piece_count =
                        analysis.compatible_piece_count + 1
                else
                    analysis.unknown_piece_count =
                        analysis.unknown_piece_count + 1
                    analysis.unknown_classes[piece.class] =
                        true
                end
            end
        end
    end

    if analysis.unknown_piece_count > 0 then
        warning(
            tostring(analysis.unknown_piece_count)
            .. " piece(s) use unknown build classes"
        )
    end

    analysis.valid =
        #analysis.fatal_errors == 0

    return analysis
end

local function inspect_file(filename, config)
    local directory =
        storage.get_schematics_directory()
    local path = directory .. filename

    local entry = {
        filename = filename,
        path = path,
        display_name = filename,
        status = "invalid",
        valid = false,
        document = nil,
        analysis = nil,
        size_bytes = nil,
        error = nil,
    }

    if file_extension(filename):lower() ~= "palschem" then
        entry.error = "Invalid extension"
        return entry
    end

    local size = get_file_size(path)
    entry.size_bytes = size

    if not size then
        entry.error = "File does not exist or is unreadable"
        return entry
    end

    if size <= 0 then
        entry.error = "File is empty"
        return entry
    end

    if size > config.library.maximum_file_size_bytes then
        entry.error =
            "File exceeds maximum size of "
            .. tostring(
                config.library.maximum_file_size_bytes
            )
            .. " bytes"
        return entry
    end

    local content, read_error =
        storage.read_text_file(filename)

    if not content then
        entry.error =
            "Unable to read file: "
            .. tostring(read_error)
        return entry
    end

    local decode_ok, document = pcall(function()
        return json.decode(content)
    end)

    if not decode_ok then
        entry.error =
            "Invalid JSON: "
            .. tostring(document)
        return entry
    end

    local analysis = analyze_document(document)

    entry.document = document
    entry.analysis = analysis
    entry.valid = analysis.valid

    if document.metadata
        and type(document.metadata.name) == "string"
        and document.metadata.name ~= ""
    then
        entry.display_name = document.metadata.name
    end

    if analysis.valid
        and analysis.unknown_piece_count == 0
    then
        entry.status = "compatible"
    elseif analysis.valid then
        entry.status = "partial"
    else
        entry.status = "invalid"
        entry.error =
            analysis.fatal_errors[1]
            or "Unknown validation error"
    end

    return entry
end

local function status_label(entry)
    if entry.status == "compatible" then
        return "COMPATIBLE"
    elseif entry.status == "partial" then
        return "PARTIAL"
    end

    return "INVALID"
end

local function reset_delete_confirmation()
    pending_delete_path = nil
    pending_delete_time = 0
end

function library.refresh(config)
    local filenames, list_error =
        list_palschem_files(config)

    entries = {}
    reset_delete_confirmation()

    if not filenames then
        selected_index = 0
        return false, list_error
    end

    for _, filename in ipairs(filenames) do
        entries[#entries + 1] =
            inspect_file(filename, config)
    end

    if #entries == 0 then
        selected_index = 0
    elseif selected_index < 1
        or selected_index > #entries
    then
        selected_index = 1
    end

    logger.log(
        "Library refreshed: "
        .. tostring(#entries)
        .. " .palschem file(s)"
    )

    library.log_list()
    return true, nil
end

function library.log_list()
    if #entries == 0 then
        logger.log(
            "SCHEMATIC LIBRARY IS EMPTY"
        )
        return
    end

    logger.log("=== SCHEMATIC LIBRARY ===")

    for index, entry in ipairs(entries) do
        local marker =
            index == selected_index and ">" or " "

        local piece_count =
            entry.analysis
            and entry.analysis.piece_count
            or 0

        logger.log(string.format(
            "%s [%d/%d] %s | file=%s | status=%s | pieces=%d | size=%s",
            marker,
            index,
            #entries,
            tostring(entry.display_name),
            tostring(entry.filename),
            status_label(entry),
            piece_count,
            tostring(entry.size_bytes or "?")
        ))
    end

    logger.log("=========================")
end

function library.get_selected()
    return entries[selected_index]
end

function library.select_previous()
    if #entries == 0 then
        return nil, "Library is empty"
    end

    selected_index = selected_index - 1

    if selected_index < 1 then
        selected_index = #entries
    end

    reset_delete_confirmation()
    library.log_selected_short()
    return entries[selected_index], nil
end

function library.select_next()
    if #entries == 0 then
        return nil, "Library is empty"
    end

    selected_index = selected_index + 1

    if selected_index > #entries then
        selected_index = 1
    end

    reset_delete_confirmation()
    library.log_selected_short()
    return entries[selected_index], nil
end

function library.log_selected_short()
    local entry = library.get_selected()

    if not entry then
        logger.log("No schematic selected")
        return
    end

    logger.log(string.format(
        "SELECTED [%d/%d] %s | %s | %s",
        selected_index,
        #entries,
        tostring(entry.display_name),
        tostring(entry.filename),
        status_label(entry)
    ))
end

function library.log_selected_details()
    local entry = library.get_selected()

    if not entry then
        return false, "No schematic selected"
    end

    logger.log("=== SELECTED SCHEMATIC DETAILS ===")
    logger.log("Name: " .. tostring(entry.display_name))
    logger.log("File: " .. tostring(entry.filename))
    logger.log("Path: " .. tostring(entry.path))
    logger.log("Status: " .. status_label(entry))
    logger.log("Size: " .. tostring(entry.size_bytes) .. " bytes")

    if entry.error then
        logger.log("Error: " .. tostring(entry.error))
    end

    if entry.document then
        logger.log(
            "Format: "
            .. tostring(entry.document.format)
            .. " v"
            .. tostring(entry.document.formatVersion)
        )

        local metadata = entry.document.metadata or {}

        logger.log(
            "Author: "
            .. tostring(metadata.author or "<unknown>")
        )
        logger.log(
            "Created at: "
            .. tostring(metadata.createdAt or "<unknown>")
        )
    end

    local analysis = entry.analysis

    if analysis then
        logger.log(string.format(
            "Pieces: %d | compatible=%d | unknown=%d",
            analysis.piece_count,
            analysis.compatible_piece_count,
            analysis.unknown_piece_count
        ))

        local class_names = {}

        for class_name in pairs(
            analysis.class_counts
        ) do
            class_names[#class_names + 1] =
                class_name
        end

        table.sort(class_names)

        logger.log("--- CONSTRUCTION COUNTS ---")

        for _, class_name in ipairs(class_names) do
            logger.log(string.format(
                "%s = %d",
                class_name,
                analysis.class_counts[class_name]
            ))
        end

        if analysis.unknown_piece_count > 0 then
            local unknown = {}

            for class_name in pairs(
                analysis.unknown_classes
            ) do
                unknown[#unknown + 1] =
                    class_name
            end

            table.sort(unknown)
            logger.log("--- UNKNOWN CLASSES ---")

            for _, class_name in ipairs(unknown) do
                logger.log(class_name)
            end
        end

        for _, warning in ipairs(
            analysis.warnings
        ) do
            logger.log("Warning: " .. warning)
        end

        for _, fatal_error in ipairs(
            analysis.fatal_errors
        ) do
            logger.log("Fatal: " .. fatal_error)
        end
    end

    logger.log(
        "Materials: unavailable until the "
        .. "Palworld recipe catalog is generated."
    )

    logger.log("==================================")
    return true, nil
end

function library.load_selected()
    local entry = library.get_selected()

    if not entry then
        return nil, "No schematic selected"
    end

    if not entry.valid then
        return nil,
            "Selected schematic is invalid: "
            .. tostring(entry.error)
    end

    if not entry.document then
        return nil,
            "Selected schematic has no decoded document"
    end

    logger.log(
        "Selected schematic loaded into memory: "
        .. tostring(entry.display_name)
    )

    return entry.document, nil
end

function library.delete_selected(config)
    local entry = library.get_selected()

    if not entry then
        return false, "No schematic selected"
    end

    local now = os.time()

    if pending_delete_path ~= entry.path
        or now - pending_delete_time
            > config.library
                .deletion_confirmation_seconds
    then
        pending_delete_path = entry.path
        pending_delete_time = now

        return false,
            "Deletion armed for "
            .. entry.filename
            .. ". Press F8 again within "
            .. tostring(
                config.library
                    .deletion_confirmation_seconds
            )
            .. " seconds to permanently delete it."
    end

    local removed, remove_error =
        os.remove(entry.path)

    reset_delete_confirmation()

    if not removed then
        return false,
            "Unable to delete file: "
            .. tostring(remove_error)
    end

    logger.log(
        "SCHEMATIC FILE DELETED: "
        .. tostring(entry.path)
    )

    local refresh_ok, refresh_error =
        library.refresh(config)

    if not refresh_ok then
        return true,
            "File deleted, but library refresh failed: "
            .. tostring(refresh_error)
    end

    return true, nil
end

return library
