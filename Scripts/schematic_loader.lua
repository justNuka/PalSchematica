local schematic_loader = {}

local json = require("json")
local logger = require("logger")
local storage = require("storage")

local function validate_vector(value, field_name)
    if type(value) ~= "table" then
        return false, field_name .. " must be an object"
    end

    for _, axis in ipairs({"x", "y", "z"}) do
        if type(value[axis]) ~= "number" then
            return false, field_name .. "." .. axis .. " must be a number"
        end
    end

    return true
end

local function validate_rotation(value, field_name)
    if type(value) ~= "table" then
        return false, field_name .. " must be an object"
    end

    for _, axis in ipairs({"pitch", "yaw", "roll"}) do
        if type(value[axis]) ~= "number" then
            return false, field_name .. "." .. axis .. " must be a number"
        end
    end

    return true
end

local function validate_document(document)
    if type(document) ~= "table" then
        return false, "Root JSON value must be an object"
    end

    if document.format ~= "PalSchematica" then
        return false, "Unsupported format: " .. tostring(document.format)
    end

    if document.formatVersion ~= 1 then
        return false, "Unsupported formatVersion: " .. tostring(document.formatVersion)
    end

    if type(document.pieces) ~= "table" or #document.pieces == 0 then
        return false, "The schematic contains no pieces"
    end

    for index, piece in ipairs(document.pieces) do
        if type(piece) ~= "table" then
            return false, string.format("pieces[%d] must be an object", index)
        end

        if type(piece.class) ~= "string" or piece.class == "" then
            return false, string.format("pieces[%d].class is required", index)
        end

        if type(piece.classPath) ~= "string" or piece.classPath == "" then
            return false, string.format("pieces[%d].classPath is required", index)
        end

        local ok, error_message = validate_vector(
            piece.relativeLocation,
            string.format("pieces[%d].relativeLocation", index)
        )
        if not ok then return false, error_message end

        ok, error_message = validate_rotation(
            piece.relativeRotation,
            string.format("pieces[%d].relativeRotation", index)
        )
        if not ok then return false, error_message end

        ok, error_message = validate_vector(
            piece.scale,
            string.format("pieces[%d].scale", index)
        )
        if not ok then return false, error_message end
    end

    return true
end

local function strip_type_prefix(full_name)
    return full_name:gsub("^BlueprintGeneratedClass%s+", "")
end

local function blueprint_asset_path(class_path)
    -- /Game/X/BP_Name.BP_Name_C -> /Game/X/BP_Name.BP_Name
    return class_path:gsub("_C$", "")
end

function schematic_loader.load(filename)
    local content, read_error, path = storage.read_text_file(filename)

    if not content then
        return nil, "Unable to read schematic: " .. tostring(read_error), path
    end

    local ok, document = pcall(function()
        return json.decode(content)
    end)

    if not ok then
        return nil, "Unable to decode JSON: " .. tostring(document), path
    end

    local valid, validation_error = validate_document(document)

    if not valid then
        return nil, "Invalid schematic: " .. tostring(validation_error), path
    end

    return document, nil, path
end

function schematic_loader.resolve_piece_class(piece)
    local class_path = strip_type_prefix(piece.classPath)

    local ok, class_object = pcall(function()
        return StaticFindObject(class_path)
    end)

    if ok and class_object and class_object:IsValid() then
        return class_object, "already_loaded", nil
    end

    local asset_path = blueprint_asset_path(class_path)

    local load_ok, loaded_asset = pcall(function()
        return LoadAsset(asset_path)
    end)

    if not load_ok then
        return nil, "load_failed", tostring(loaded_asset)
    end

    ok, class_object = pcall(function()
        return StaticFindObject(class_path)
    end)

    if ok and class_object and class_object:IsValid() then
        return class_object, "loaded_on_demand", nil
    end

    local loaded_name = "<nil>"
    if loaded_asset and loaded_asset:IsValid() then
        local name_ok, name = pcall(function()
            return loaded_asset:GetFullName()
        end)
        if name_ok then
            loaded_name = name
        end
    end

    return nil, "not_found_after_load", "Loaded asset: " .. loaded_name
end

function schematic_loader.log_summary(document, path)
    logger.log("Schematic loaded: " .. tostring(path))
    logger.log(string.format(
        "Name: %s | pieces: %d | format version: %s",
        tostring(document.metadata and document.metadata.name or "<unnamed>"),
        #document.pieces,
        tostring(document.formatVersion)
    ))

    local first_piece = document.pieces[1]

    logger.log(string.format(
        "First piece: %s | relative location: X=%.3f Y=%.3f Z=%.3f | relative yaw=%.3f",
        tostring(first_piece.class),
        first_piece.relativeLocation.x,
        first_piece.relativeLocation.y,
        first_piece.relativeLocation.z,
        first_piece.relativeRotation.yaw
    ))
end

return schematic_loader
