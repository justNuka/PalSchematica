local inspector = {}

local logger = require("logger")

local last_foundation = nil

local function safe_is_valid(object)
    if not object then
        return false
    end

    local ok, result = pcall(function()
        return object:IsValid()
    end)

    return ok and result == true
end

local function safe_full_name(object)
    if not safe_is_valid(object) then
        return nil
    end

    local ok, value = pcall(function()
        return object:GetFullName()
    end)

    return ok and value or nil
end

local function safe_class_name(object)
    if not safe_is_valid(object) then
        return nil
    end

    local ok, value = pcall(function()
        return object:GetClass():GetFullName()
    end)

    return ok and value or nil
end

local function contains_marker(name, markers)
    if not name then
        return false
    end

    for _, marker in ipairs(markers) do
        if name:find(marker, 1, true) then
            return true
        end
    end

    return false
end

local function safe_property(object, property_name)
    if not safe_is_valid(object) then
        return nil, "invalid object"
    end

    local ok, value = pcall(function()
        return object[property_name]
    end)

    if not ok then
        return nil, tostring(value)
    end

    return value, nil
end

local function log_object(label, object)
    if safe_is_valid(object) then
        logger.log(string.format(
            "%s | object: %s | class: %s",
            label,
            tostring(safe_full_name(object)),
            tostring(safe_class_name(object))
        ))
    else
        logger.log(label .. " | <invalid or nil>")
    end
end

local function log_transform_component(component)
    local relative_location, location_error =
        safe_property(component, "RelativeLocation")
    local relative_rotation, rotation_error =
        safe_property(component, "RelativeRotation")
    local relative_scale, scale_error =
        safe_property(component, "RelativeScale3D")

    if relative_location then
        logger.log(string.format(
            "  RelativeLocation: X=%.3f Y=%.3f Z=%.3f",
            relative_location.X or 0,
            relative_location.Y or 0,
            relative_location.Z or 0
        ))
    else
        logger.log(
            "  RelativeLocation unavailable: "
            .. tostring(location_error)
        )
    end

    if relative_rotation then
        logger.log(string.format(
            "  RelativeRotation: Pitch=%.3f Yaw=%.3f Roll=%.3f",
            relative_rotation.Pitch or 0,
            relative_rotation.Yaw or 0,
            relative_rotation.Roll or 0
        ))
    else
        logger.log(
            "  RelativeRotation unavailable: "
            .. tostring(rotation_error)
        )
    end

    if relative_scale then
        logger.log(string.format(
            "  RelativeScale3D: X=%.3f Y=%.3f Z=%.3f",
            relative_scale.X or 0,
            relative_scale.Y or 0,
            relative_scale.Z or 0
        ))
    else
        logger.log(
            "  RelativeScale3D unavailable: "
            .. tostring(scale_error)
        )
    end
end

local function log_static_mesh(component)
    local mesh, error_message = safe_property(component, "StaticMesh")

    if safe_is_valid(mesh) then
        log_object("  StaticMesh", mesh)
    else
        logger.log(
            "  StaticMesh unavailable or empty: "
            .. tostring(error_message)
        )
    end
end

local function inspect_component(component, index)
    log_object("Component #" .. tostring(index), component)
    log_transform_component(component)
    log_static_mesh(component)
end

local function resolve_static_mesh_component_class()
    local attempts = {
        "/Script/Engine.StaticMeshComponent",
        "Class /Script/Engine.StaticMeshComponent",
    }

    for _, path in ipairs(attempts) do
        local ok, class_object = pcall(function()
            return StaticFindObject(path)
        end)

        if ok and safe_is_valid(class_object) then
            logger.log(
                "StaticMeshComponent class resolved: "
                .. tostring(safe_full_name(class_object))
            )
            return class_object
        end
    end

    return nil
end

local function get_components_by_class(actor, component_class)
    local attempts = {
        {
            name = "GetComponentsByClass",
            call = function()
                return actor:GetComponentsByClass(component_class)
            end,
        },
        {
            name = "K2_GetComponentsByClass",
            call = function()
                return actor:K2_GetComponentsByClass(component_class)
            end,
        },
    }

    for _, attempt in ipairs(attempts) do
        logger.log("Trying component query: " .. attempt.name)

        local ok, components_or_error = pcall(attempt.call)

        if ok and components_or_error then
            logger.log(
                "Component query succeeded: "
                .. attempt.name
            )
            return components_or_error, nil
        end

        logger.log(
            "Component query failed: "
            .. attempt.name
            .. " | "
            .. tostring(components_or_error)
        )
    end

    return nil, "No component query strategy succeeded"
end

function inspector.watch_new_build_actors(config, is_enabled)
    NotifyOnNewObject("/Script/Engine.Actor", function(actor)
        if not is_enabled() then
            return
        end

        local name = safe_full_name(actor)

        if not contains_marker(name, config.build_name_markers) then
            return
        end

        logger.log("New build-like actor: " .. tostring(name))

        if name
            and name:find(
                "BP_BuildObject_Wood_Foundation_C",
                1,
                true
            )
        then
            last_foundation = actor
            logger.log(
                "Last real wooden foundation reference updated: "
                .. tostring(name)
            )
        end
    end)
end

function inspector.inspect_last_foundation()
    if not safe_is_valid(last_foundation) then
        return false,
            "No valid wooden foundation has been detected yet. "
            .. "Place one normally, then press F3."
    end

    logger.log("=== FOUNDATION COMPONENT INSPECTION START ===")
    log_object("Foundation actor", last_foundation)

    local root_component, root_error =
        safe_property(last_foundation, "RootComponent")

    if safe_is_valid(root_component) then
        log_object("RootComponent", root_component)
        log_transform_component(root_component)
        log_static_mesh(root_component)
    else
        logger.log(
            "RootComponent unavailable: "
            .. tostring(root_error)
        )
    end

    local static_mesh_component_class =
        resolve_static_mesh_component_class()

    if not static_mesh_component_class then
        logger.log(
            "Unable to resolve /Script/Engine.StaticMeshComponent"
        )
        logger.log("=== FOUNDATION COMPONENT INSPECTION END ===")
        return false, "StaticMeshComponent class resolution failed"
    end

    local components, query_error =
        get_components_by_class(
            last_foundation,
            static_mesh_component_class
        )

    if not components then
        logger.log("Component query error: " .. tostring(query_error))
        logger.log("=== FOUNDATION COMPONENT INSPECTION END ===")
        return false, query_error
    end

    local count = 0

    for index, component in pairs(components) do
        if safe_is_valid(component) then
            count = count + 1
            inspect_component(component, index)
        end
    end

    logger.log(
        "StaticMeshComponent count: "
        .. tostring(count)
    )
    logger.log("=== FOUNDATION COMPONENT INSPECTION END ===")

    return true, nil
end

return inspector
