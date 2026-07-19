local schematic_preview = {}

local build_catalog = require("build_catalog")
local logger = require("logger")

local spawned_actors = {}

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
                "Player resolved: "
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
            return class_object
        end
    end

    return nil
end

local function load_mesh(asset_path)
    local ok, mesh = pcall(function()
        return LoadAsset(asset_path)
    end)

    if ok and safe_is_valid(mesh) then
        return mesh
    end

    local attempts = {
        asset_path,
        "StaticMesh " .. asset_path,
    }

    for _, path in ipairs(attempts) do
        local find_ok, object = pcall(function()
            return StaticFindObject(path)
        end)

        if find_ok and safe_is_valid(object) then
            return object
        end
    end

    return nil
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
            return component
        end
    end

    return nil
end

local function make_vector_like(template, x, y, z)
    local ok, result = pcall(function()
        local value = template
        value.X = x
        value.Y = y
        value.Z = z
        return value
    end)

    return ok and result or nil
end

local function make_rotation_like(
    template,
    pitch,
    yaw,
    roll
)
    local ok, result = pcall(function()
        local value = template
        value.Pitch = pitch
        value.Yaw = yaw
        value.Roll = roll
        return value
    end)

    return ok and result or nil
end

local function make_scale_like(template, x, y, z)
    local ok, result = pcall(function()
        local value = template
        value.X = x
        value.Y = y
        value.Z = z
        return value
    end)

    return ok and result or nil
end

local function rotate_xy(x, y, yaw_degrees)
    local radians = math.rad(yaw_degrees)
    local cosine = math.cos(radians)
    local sine = math.sin(radians)

    return
        x * cosine - y * sine,
        x * sine + y * cosine
end

local function configure_actor(
    actor,
    component,
    mesh,
    scale
)
    local mobility_ok, mobility_error = pcall(function()
        component:SetMobility(2)
    end)

    if not mobility_ok then
        logger.log(
            "SetMobility failed: "
            .. tostring(mobility_error)
        )
    end

    local mesh_ok, mesh_result = pcall(function()
        return component:SetStaticMesh(mesh)
    end)

    if not mesh_ok or mesh_result ~= true then
        return false,
            "SetStaticMesh failed or returned false: "
            .. tostring(mesh_result)
    end

    pcall(function()
        actor:SetActorEnableCollision(false)
    end)

    pcall(function()
        actor:SetActorHiddenInGame(false)
    end)

    pcall(function()
        component:SetCollisionEnabled(0)
    end)

    pcall(function()
        component:SetVisibility(true, true)
    end)

    pcall(function()
        component:SetHiddenInGame(false, true)
    end)

    local current_scale_ok, current_scale = pcall(function()
        return actor:GetActorScale3D()
    end)

    if current_scale_ok and current_scale then
        local target_scale = make_scale_like(
            current_scale,
            scale.x,
            scale.y,
            scale.z
        )

        if target_scale then
            pcall(function()
                actor:SetActorScale3D(target_scale)
            end)
        end
    end

    return true, nil
end

local function spawn_single_mesh(
    world,
    actor_class,
    mesh_path,
    location,
    rotation,
    scale
)
    local mesh = load_mesh(mesh_path)

    if not mesh then
        return nil,
            "Unable to load mesh: "
            .. tostring(mesh_path)
    end

    local spawn_ok, actor_or_error = pcall(function()
        return world:SpawnActor(
            actor_class,
            location,
            rotation
        )
    end)

    if not spawn_ok or not safe_is_valid(actor_or_error) then
        return nil,
            "StaticMeshActor spawn failed: "
            .. tostring(actor_or_error)
    end

    local actor = actor_or_error
    local component = get_static_mesh_component(actor)

    if not component then
        pcall(function()
            actor:K2_DestroyActor()
        end)

        return nil,
            "StaticMeshComponent unavailable for "
            .. tostring(mesh_path)
    end

    local configured, configure_error =
        configure_actor(
            actor,
            component,
            mesh,
            scale
        )

    if not configured then
        pcall(function()
            actor:K2_DestroyActor()
        end)

        return nil, configure_error
    end

    return actor, nil
end

function schematic_preview.destroy_all()
    local destroyed = 0

    for _, actor in ipairs(spawned_actors) do
        if safe_is_valid(actor) then
            local ok = pcall(function()
                actor:K2_DestroyActor()
            end)

            if ok then
                destroyed = destroyed + 1
            end
        end
    end

    spawned_actors = {}

    logger.log(
        "Full schematic preview destroyed: "
        .. tostring(destroyed)
        .. " actor(s)"
    )

    return destroyed
end

function schematic_preview.spawn(document, config)
    if #spawned_actors > 0 then
        return false,
            "A schematic preview already exists. "
            .. "Press F5 first."
    end

    if not document or not document.pieces then
        return false, "No loaded schematic document."
    end

    local player = find_player_character()

    if not player then
        return false, "Unable to resolve the local player."
    end

    local location_ok, player_location = pcall(function()
        return player:K2_GetActorLocation()
    end)

    local rotation_ok, player_rotation = pcall(function()
        return player:K2_GetActorRotation()
    end)

    local forward_ok, forward = pcall(function()
        return player:GetActorForwardVector()
    end)

    if not location_ok
        or not rotation_ok
        or not forward_ok
        or not player_location
        or not player_rotation
        or not forward
    then
        return false, "Unable to read player transform."
    end

    local world_ok, world = pcall(function()
        return player:GetWorld()
    end)

    if not world_ok or not safe_is_valid(world) then
        return false, "Unable to resolve UWorld."
    end

    local actor_class =
        resolve_static_mesh_actor_class()

    if not actor_class then
        return false,
            "Unable to resolve StaticMeshActor class."
    end

    local anchor_x =
        player_location.X
        + forward.X
        * config.full_preview.anchor_distance

    local anchor_y =
        player_location.Y
        + forward.Y
        * config.full_preview.anchor_distance

    local anchor_z =
        player_location.Z
        + config.full_preview.height_offset

    local anchor_yaw = player_rotation.Yaw or 0
    local spawned_mesh_count = 0
    local skipped_piece_count = 0
    local failed_mesh_count = 0

    logger.log(string.format(
        "Full preview anchor | X=%.3f Y=%.3f Z=%.3f | Yaw=%.3f",
        anchor_x,
        anchor_y,
        anchor_z,
        anchor_yaw
    ))

    for piece_index, piece in ipairs(document.pieces) do
        local mesh_paths = build_catalog[piece.class]

        if not mesh_paths or #mesh_paths == 0 then
            skipped_piece_count =
                skipped_piece_count + 1

            logger.log(
                "No mesh catalog entry for piece #"
                .. tostring(piece_index)
                .. ": "
                .. tostring(piece.class)
            )
        else
            local offset_x, offset_y =
                rotate_xy(
                    piece.relativeLocation.x,
                    piece.relativeLocation.y,
                    anchor_yaw
                )

            local world_x = anchor_x + offset_x
            local world_y = anchor_y + offset_y
            local world_z =
                anchor_z
                + piece.relativeLocation.z

            local world_yaw =
                anchor_yaw
                + piece.relativeRotation.yaw

            local location = make_vector_like(
                player_location,
                world_x,
                world_y,
                world_z
            )

            local rotation = make_rotation_like(
                player_rotation,
                piece.relativeRotation.pitch,
                world_yaw,
                piece.relativeRotation.roll
            )

            local scale = {
                x =
                    piece.scale.x
                    * config.full_preview.scale,
                y =
                    piece.scale.y
                    * config.full_preview.scale,
                z =
                    piece.scale.z
                    * config.full_preview.scale,
            }

            if location and rotation then
                for _, mesh_path in ipairs(mesh_paths) do
                    if spawned_mesh_count
                        >= config.full_preview.maximum_spawned_meshes
                    then
                        logger.log(
                            "Maximum spawned mesh limit reached: "
                            .. tostring(
                                config.full_preview
                                    .maximum_spawned_meshes
                            )
                        )

                        logger.log(string.format(
                            "Full preview partial result | spawned=%d skippedPieces=%d failedMeshes=%d",
                            spawned_mesh_count,
                            skipped_piece_count,
                            failed_mesh_count
                        ))

                        return true, nil
                    end

                    local actor, spawn_error =
                        spawn_single_mesh(
                            world,
                            actor_class,
                            mesh_path,
                            location,
                            rotation,
                            scale
                        )

                    if actor then
                        spawned_actors[
                            #spawned_actors + 1
                        ] = actor

                        spawned_mesh_count =
                            spawned_mesh_count + 1
                    else
                        failed_mesh_count =
                            failed_mesh_count + 1

                        logger.log(string.format(
                            "Mesh spawn failed | piece #%d | class=%s | mesh=%s | error=%s",
                            piece_index,
                            tostring(piece.class),
                            tostring(mesh_path),
                            tostring(spawn_error)
                        ))
                    end
                end
            else
                failed_mesh_count =
                    failed_mesh_count
                    + #mesh_paths

                logger.log(
                    "Unable to create transform for piece #"
                    .. tostring(piece_index)
                )
            end
        end
    end

    logger.log(string.format(
        "FULL SCHEMATIC PREVIEW CREATED | pieces=%d spawnedMeshes=%d skippedPieces=%d failedMeshes=%d",
        #document.pieces,
        spawned_mesh_count,
        skipped_piece_count,
        failed_mesh_count
    ))

    return true, nil
end

return schematic_preview
