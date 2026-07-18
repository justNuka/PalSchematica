local preview = {}

local logger = require("logger")

local preview_actor = nil

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

local function find_player_character()
    local candidates = {
        "PalPlayerCharacter",
        "BP_Player_Female_C",
        "BP_Player_Male_C",
    }

    for _, class_name in ipairs(candidates) do
        local ok, object = pcall(function()
            return FindFirstOf(class_name)
        end)

        if ok and safe_is_valid(object) then
            logger.log(
                "Player resolved with FindFirstOf("
                .. class_name
                .. "): "
                .. tostring(safe_full_name(object))
            )
            return object
        end
    end

    return nil
end

local function load_mesh(asset_path)
    logger.log("Loading preview mesh asset: " .. tostring(asset_path))

    local loaded_asset = nil

    local load_ok, load_result = pcall(function()
        return LoadAsset(asset_path)
    end)

    if load_ok and safe_is_valid(load_result) then
        loaded_asset = load_result
        logger.log(
            "LoadAsset returned a valid object: "
            .. tostring(safe_full_name(loaded_asset))
        )
    elseif not load_ok then
        logger.log("LoadAsset failed: " .. tostring(load_result))
    else
        logger.log(
            "LoadAsset returned no directly usable object; "
            .. "trying StaticFindObject."
        )
    end

    if safe_is_valid(loaded_asset) then
        return loaded_asset
    end

    local find_attempts = {
        asset_path,
        "StaticMesh " .. asset_path,
    }

    for _, object_path in ipairs(find_attempts) do
        local ok, object = pcall(function()
            return StaticFindObject(object_path)
        end)

        if ok and safe_is_valid(object) then
            logger.log(
                "Preview mesh resolved with StaticFindObject: "
                .. tostring(safe_full_name(object))
            )
            return object
        end
    end

    return nil
end

local function resolve_static_mesh_actor_class()
    local attempts = {
        "/Script/Engine.StaticMeshActor",
        "Class /Script/Engine.StaticMeshActor",
    }

    for _, path in ipairs(attempts) do
        local ok, class_object = pcall(function()
            return StaticFindObject(path)
        end)

        if ok and safe_is_valid(class_object) then
            logger.log(
                "StaticMeshActor class resolved: "
                .. tostring(safe_full_name(class_object))
            )
            return class_object
        end
    end

    return nil
end

local function get_actor_location(actor)
    local ok, value = pcall(function()
        return actor:K2_GetActorLocation()
    end)

    if not ok or not value then
        return nil
    end

    return value
end

local function get_actor_rotation(actor)
    local ok, value = pcall(function()
        return actor:K2_GetActorRotation()
    end)

    if not ok or not value then
        return nil
    end

    return value
end

local function get_forward_vector(actor)
    local ok, value = pcall(function()
        return actor:GetActorForwardVector()
    end)

    if not ok or not value then
        return nil
    end

    return value
end

local function make_vector_like(template, x, y, z)
    local ok, value = pcall(function()
        local result = template
        result.X = x
        result.Y = y
        result.Z = z
        return result
    end)

    return ok and value or nil
end

local function get_static_mesh_component(actor)
    local property_attempts = {
        "StaticMeshComponent",
        "StaticMeshComponent0",
    }

    for _, property_name in ipairs(property_attempts) do
        local ok, component = pcall(function()
            return actor[property_name]
        end)

        if ok and safe_is_valid(component) then
            logger.log(
                "StaticMeshComponent resolved through property "
                .. property_name
                .. ": "
                .. tostring(safe_full_name(component))
            )
            return component
        end
    end

    local method_attempts = {
        {
            name = "GetStaticMeshComponent",
            call = function()
                return actor:GetStaticMeshComponent()
            end,
        },
        {
            name = "K2_GetComponentsByClass",
            call = function()
                local component_class =
                    StaticFindObject("/Script/Engine.StaticMeshComponent")
                local components =
                    actor:K2_GetComponentsByClass(component_class)

                if components then
                    for _, component in pairs(components) do
                        if safe_is_valid(component) then
                            return component
                        end
                    end
                end

                return nil
            end,
        },
    }

    for _, attempt in ipairs(method_attempts) do
        local ok, component = pcall(attempt.call)

        if ok and safe_is_valid(component) then
            logger.log(
                "StaticMeshComponent resolved through "
                .. attempt.name
                .. ": "
                .. tostring(safe_full_name(component))
            )
            return component
        end

        logger.log(
            "StaticMeshComponent strategy failed: "
            .. attempt.name
            .. " | "
            .. tostring(component)
        )
    end

    return nil
end

local function set_component_movable(component)
    local attempts = {
        {
            name = "SetMobility(2)",
            call = function()
                component:SetMobility(2)
                return true
            end,
        },
        {
            name = "direct Mobility property = 2",
            call = function()
                component.Mobility = 2
                return true
            end,
        },
    }

    for _, attempt in ipairs(attempts) do
        local ok, result = pcall(attempt.call)

        if ok then
            logger.log(
                "Component mobility update succeeded with "
                .. attempt.name
            )
            return true
        end

        logger.log(
            "Component mobility update failed with "
            .. attempt.name
            .. " | "
            .. tostring(result)
        )
    end

    return false
end

local function get_assigned_mesh(component)
    local attempts = {
        {
            name = "GetStaticMesh",
            call = function()
                return component:GetStaticMesh()
            end,
        },
        {
            name = "StaticMesh property",
            call = function()
                return component.StaticMesh
            end,
        },
    }

    for _, attempt in ipairs(attempts) do
        local ok, assigned_mesh = pcall(attempt.call)

        if ok and safe_is_valid(assigned_mesh) then
            logger.log(
                "Assigned mesh verified with "
                .. attempt.name
                .. ": "
                .. tostring(safe_full_name(assigned_mesh))
            )
            return assigned_mesh
        end

        logger.log(
            "Assigned mesh verification failed with "
            .. attempt.name
            .. " | "
            .. tostring(assigned_mesh)
        )
    end

    return nil
end

local function refresh_component(component)
    local attempts = {
        {
            name = "ReregisterComponent",
            call = function()
                component:ReregisterComponent()
            end,
        },
        {
            name = "UnregisterComponent + RegisterComponent",
            call = function()
                component:UnregisterComponent()
                component:RegisterComponent()
            end,
        },
        {
            name = "RecreateRenderState_Concurrent",
            call = function()
                component:RecreateRenderState_Concurrent()
            end,
        },
    }

    for _, attempt in ipairs(attempts) do
        local ok, error_message = pcall(attempt.call)

        if ok then
            logger.log(
                "Component refresh succeeded with "
                .. attempt.name
            )
            return true
        end

        logger.log(
            "Component refresh failed with "
            .. attempt.name
            .. " | "
            .. tostring(error_message)
        )
    end

    return false
end

local function set_mesh(component, mesh)
    set_component_movable(component)

    local ok, result = pcall(function()
        return component:SetStaticMesh(mesh)
    end)

    if ok then
        logger.log(
            "SetStaticMesh returned: "
            .. tostring(result)
        )
    else
        logger.log(
            "SetStaticMesh raised an error: "
            .. tostring(result)
        )
    end

    -- SetStaticMesh doit réellement renvoyer true.
    if ok and result == true then
        local assigned_mesh = get_assigned_mesh(component)

        if assigned_mesh then
            refresh_component(component)
            return true
        end
    end

    logger.log(
        "SetStaticMesh did not assign the mesh; "
        .. "trying direct StaticMesh property assignment."
    )

    local property_ok, property_error = pcall(function()
        component.StaticMesh = mesh
    end)

    if not property_ok then
        logger.log(
            "Direct StaticMesh property assignment failed: "
            .. tostring(property_error)
        )
        return false
    end

    local assigned_mesh = get_assigned_mesh(component)

    if not assigned_mesh then
        logger.log(
            "Direct property assignment completed without Lua error, "
            .. "but no mesh is readable afterward."
        )
        return false
    end

    refresh_component(component)
    return true
end

local function force_visible(actor, component)
    local actor_calls = {
        {
            name = "SetActorHiddenInGame(false)",
            call = function()
                actor:SetActorHiddenInGame(false)
            end,
        },
        {
            name = "SetActorEnableCollision(false)",
            call = function()
                actor:SetActorEnableCollision(false)
            end,
        },
    }

    for _, attempt in ipairs(actor_calls) do
        local ok, error_message = pcall(attempt.call)

        logger.log(
            attempt.name
            .. (ok and " succeeded" or " failed: " .. tostring(error_message))
        )
    end

    local component_calls = {
        {
            name = "SetVisibility(true, true)",
            call = function()
                component:SetVisibility(true, true)
            end,
        },
        {
            name = "SetHiddenInGame(false, true)",
            call = function()
                component:SetHiddenInGame(false, true)
            end,
        },
        {
            name = "SetCollisionEnabled(0)",
            call = function()
                component:SetCollisionEnabled(0)
            end,
        },
    }

    for _, attempt in ipairs(component_calls) do
        local ok, error_message = pcall(attempt.call)

        logger.log(
            attempt.name
            .. (ok and " succeeded" or " failed: " .. tostring(error_message))
        )
    end
end

local function log_actor_transform(label, actor)
    local location_ok, location = pcall(function()
        return actor:K2_GetActorLocation()
    end)

    local rotation_ok, rotation = pcall(function()
        return actor:K2_GetActorRotation()
    end)

    local scale_ok, scale = pcall(function()
        return actor:GetActorScale3D()
    end)

    if location_ok and location then
        logger.log(string.format(
            "%s location | X=%.3f Y=%.3f Z=%.3f",
            label,
            location.X or 0,
            location.Y or 0,
            location.Z or 0
        ))
    else
        logger.log(
            label
            .. " location unavailable: "
            .. tostring(location)
        )
    end

    if rotation_ok and rotation then
        logger.log(string.format(
            "%s rotation | Pitch=%.3f Yaw=%.3f Roll=%.3f",
            label,
            rotation.Pitch or 0,
            rotation.Yaw or 0,
            rotation.Roll or 0
        ))
    else
        logger.log(
            label
            .. " rotation unavailable: "
            .. tostring(rotation)
        )
    end

    if scale_ok and scale then
        logger.log(string.format(
            "%s scale | X=%.3f Y=%.3f Z=%.3f",
            label,
            scale.X or 0,
            scale.Y or 0,
            scale.Z or 0
        ))
    else
        logger.log(
            label
            .. " scale unavailable: "
            .. tostring(scale)
        )
    end
end

local function force_actor_transform(
    actor,
    target_location,
    target_rotation,
    scale_value
)
    local location_attempts = {
        {
            name = "K2_SetActorLocation",
            call = function()
                return actor:K2_SetActorLocation(
                    target_location,
                    false,
                    {},
                    true
                )
            end,
        },
        {
            name = "SetActorLocation",
            call = function()
                return actor:SetActorLocation(
                    target_location,
                    false,
                    {},
                    true
                )
            end,
        },
    }

    local location_applied = false

    for _, attempt in ipairs(location_attempts) do
        local ok, result = pcall(attempt.call)

        logger.log(
            attempt.name
            .. (ok
                and " completed | result: " .. tostring(result)
                or " failed: " .. tostring(result))
        )

        if ok then
            location_applied = true
            break
        end
    end

    local rotation_attempts = {
        {
            name = "K2_SetActorRotation",
            call = function()
                return actor:K2_SetActorRotation(
                    target_rotation,
                    true
                )
            end,
        },
        {
            name = "SetActorRotation",
            call = function()
                return actor:SetActorRotation(
                    target_rotation,
                    true
                )
            end,
        },
    }

    local rotation_applied = false

    for _, attempt in ipairs(rotation_attempts) do
        local ok, result = pcall(attempt.call)

        logger.log(
            attempt.name
            .. (ok
                and " completed | result: " .. tostring(result)
                or " failed: " .. tostring(result))
        )

        if ok then
            rotation_applied = true
            break
        end
    end

    local scale_attempts = {
        {
            name = "SetActorScale3D",
            call = function()
                local current_scale = actor:GetActorScale3D()
                current_scale.X = scale_value
                current_scale.Y = scale_value
                current_scale.Z = scale_value
                actor:SetActorScale3D(current_scale)
                return true
            end,
        },
        {
            name = "RootComponent.RelativeScale3D",
            call = function()
                local root = actor.RootComponent
                local current_scale = root.RelativeScale3D
                current_scale.X = scale_value
                current_scale.Y = scale_value
                current_scale.Z = scale_value
                root.RelativeScale3D = current_scale
                return true
            end,
        },
    }

    local scale_applied = false

    for _, attempt in ipairs(scale_attempts) do
        local ok, result = pcall(attempt.call)

        logger.log(
            attempt.name
            .. (ok
                and " completed"
                or " failed: " .. tostring(result))
        )

        if ok then
            scale_applied = true
            break
        end
    end

    return location_applied, rotation_applied, scale_applied
end

function preview.spawn(config)
    if safe_is_valid(preview_actor) then
        return false, "A preview already exists. Press F5 first."
    end

    local player = find_player_character()

    if not player then
        return false, "Unable to resolve the local player."
    end

    local player_location = get_actor_location(player)
    local player_rotation = get_actor_rotation(player)
    local forward = get_forward_vector(player)

    if not player_location or not player_rotation or not forward then
        return false, "Unable to read the player transform."
    end

    local target_x =
        player_location.X + forward.X * config.preview.distance
    local target_y =
        player_location.Y + forward.Y * config.preview.distance
    local target_z =
        player_location.Z
        + forward.Z * config.preview.distance
        + config.preview.height_offset

    local target_location = make_vector_like(
        player_location,
        target_x,
        target_y,
        target_z
    )

    if not target_location then
        return false, "Unable to construct target FVector."
    end

    local mesh = load_mesh(config.preview.mesh_asset_path)

    if not mesh then
        return false, "Unable to load SM_Floor_Wood."
    end

    local actor_class = resolve_static_mesh_actor_class()

    if not actor_class then
        return false, "Unable to resolve StaticMeshActor class."
    end

    local world_ok, world = pcall(function()
        return player:GetWorld()
    end)

    if not world_ok or not safe_is_valid(world) then
        return false, "Unable to resolve UWorld."
    end

    logger.log(string.format(
        "Preview target | X=%.3f Y=%.3f Z=%.3f | Yaw=%.3f",
        target_x,
        target_y,
        target_z,
        player_rotation.Yaw or 0
    ))

    local spawn_ok, actor_or_error = pcall(function()
        return world:SpawnActor(
            actor_class,
            target_location,
            player_rotation
        )
    end)

    if not spawn_ok or not safe_is_valid(actor_or_error) then
        return false,
            "StaticMeshActor spawn failed: "
            .. tostring(actor_or_error)
    end

    preview_actor = actor_or_error

    logger.log(
        "Neutral StaticMeshActor spawned: "
        .. tostring(safe_full_name(preview_actor))
    )

    log_actor_transform("Immediately after SpawnActor", preview_actor)

    local location_applied, rotation_applied, scale_applied =
        force_actor_transform(
            preview_actor,
            target_location,
            player_rotation,
            config.preview.scale or 1.0
        )

    logger.log(string.format(
        "Forced transform summary | location=%s rotation=%s scale=%s",
        tostring(location_applied),
        tostring(rotation_applied),
        tostring(scale_applied)
    ))

    log_actor_transform("After forced transform", preview_actor)

    local component = get_static_mesh_component(preview_actor)

    if not component then
        preview.destroy()
        return false,
            "StaticMeshActor exists, but its StaticMeshComponent "
            .. "could not be resolved."
    end

    if not set_mesh(component, mesh) then
        preview.destroy()
        return false, "Unable to assign SM_Floor_Wood."
    end

    force_visible(preview_actor, component)

    log_actor_transform("Final preview actor", preview_actor)

    logger.log(
        "WOOD FOUNDATION PREVIEW CREATED. "
        .. "This is a neutral StaticMeshActor, not a Palworld "
        .. "construction. Press F5 to remove it."
    )

    return true, nil
end

function preview.destroy()
    if not safe_is_valid(preview_actor) then
        preview_actor = nil
        return false, "No valid preview exists."
    end

    local name = safe_full_name(preview_actor) or "<unknown>"

    local ok, error_message = pcall(function()
        preview_actor:K2_DestroyActor()
    end)

    if not ok then
        return false,
            "Unable to destroy preview: "
            .. tostring(error_message)
    end

    preview_actor = nil
    logger.log("Preview destroyed: " .. tostring(name))

    return true, nil
end

return preview
