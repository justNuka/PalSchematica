local spawn_test = {}

local logger = require("logger")

local spawned_actor = nil

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
    local candidate_class_names = {
        "PalPlayerCharacter",
        "BP_PlayerBase_C",
        "PalCharacter",
    }

    for _, class_name in ipairs(candidate_class_names) do
        local ok, object = pcall(function()
            return FindFirstOf(class_name)
        end)

        if ok and safe_is_valid(object) then
            logger.log(
                "Player candidate resolved with FindFirstOf("
                .. class_name
                .. "): "
                .. tostring(safe_full_name(object))
            )
            return object
        end
    end

    return nil
end

local function get_actor_location(actor)
    local ok, value = pcall(function()
        return actor:K2_GetActorLocation()
    end)

    if not ok or not value then
        return nil, tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
        raw = value,
    }, nil
end

local function get_actor_rotation(actor)
    local ok, value = pcall(function()
        return actor:K2_GetActorRotation()
    end)

    if not ok or not value then
        return nil, tostring(value)
    end

    return {
        pitch = value.Pitch,
        yaw = value.Yaw,
        roll = value.Roll,
        raw = value,
    }, nil
end

local function get_forward_vector(actor)
    local ok, value = pcall(function()
        return actor:GetActorForwardVector()
    end)

    if not ok or not value then
        return nil, tostring(value)
    end

    return {
        x = value.X,
        y = value.Y,
        z = value.Z,
        raw = value,
    }, nil
end

local function make_vector_like(template, x, y, z)
    local ok, result = pcall(function()
        local value = template
        value.X = x
        value.Y = y
        value.Z = z
        return value
    end)

    if ok then
        return result
    end

    return nil
end

local function disable_actor_collision(actor)
    local ok, error_message = pcall(function()
        actor:SetActorEnableCollision(false)
    end)

    if ok then
        logger.log("Collision disabled on spawned test actor")
    else
        logger.log(
            "Unable to disable collision on spawned actor: "
            .. tostring(error_message)
        )
    end
end

local function get_world(actor)
    local ok, world = pcall(function()
        return actor:GetWorld()
    end)

    if ok and safe_is_valid(world) then
        return world
    end

    return nil
end

local function spawn_with_world(world, class_object, location, rotation)
    local attempts = {
        {
            name = "World:SpawnActor(class, location, rotation)",
            call = function()
                return world:SpawnActor(class_object, location, rotation)
            end,
        },
        {
            name = "World:SpawnActor(class, location, rotation, nil)",
            call = function()
                return world:SpawnActor(class_object, location, rotation, nil)
            end,
        },
    }

    for _, attempt in ipairs(attempts) do
        logger.log("Trying spawn strategy: " .. attempt.name)

        local ok, actor_or_error = pcall(attempt.call)

        if ok and safe_is_valid(actor_or_error) then
            logger.log(
                "Spawn strategy succeeded: "
                .. attempt.name
                .. " -> "
                .. tostring(safe_full_name(actor_or_error))
            )
            return actor_or_error, nil
        end

        logger.log(
            "Spawn strategy failed: "
            .. attempt.name
            .. " | "
            .. tostring(actor_or_error)
        )
    end

    return nil, "All World:SpawnActor strategies failed"
end

function spawn_test.has_spawned_actor()
    return safe_is_valid(spawned_actor)
end

function spawn_test.spawn(class_object, config)
    if safe_is_valid(spawned_actor) then
        return nil, "A test actor is already spawned. Press F5 first."
    end

    if not safe_is_valid(class_object) then
        return nil, "The resolved class object is invalid."
    end

    local player = find_player_character()

    if not player then
        return nil, "Unable to resolve the local player character."
    end

    local player_location, location_error = get_actor_location(player)
    if not player_location then
        return nil, "Unable to read player location: " .. tostring(location_error)
    end

    local player_rotation, rotation_error = get_actor_rotation(player)
    if not player_rotation then
        return nil, "Unable to read player rotation: " .. tostring(rotation_error)
    end

    local forward, forward_error = get_forward_vector(player)
    if not forward then
        return nil, "Unable to read player forward vector: " .. tostring(forward_error)
    end

    local target_x =
        player_location.x + forward.x * config.spawn_distance
    local target_y =
        player_location.y + forward.y * config.spawn_distance
    local target_z =
        player_location.z
        + forward.z * config.spawn_distance
        + config.spawn_height_offset

    local target_location = make_vector_like(
        player_location.raw,
        target_x,
        target_y,
        target_z
    )

    if not target_location then
        return nil, "Unable to construct the target FVector."
    end

    logger.log(string.format(
        "Spawn target | X=%.3f Y=%.3f Z=%.3f | "
        .. "Pitch=%.3f Yaw=%.3f Roll=%.3f",
        target_x,
        target_y,
        target_z,
        player_rotation.pitch,
        player_rotation.yaw,
        player_rotation.roll
    ))

    local world = get_world(player)

    if not world then
        return nil, "Unable to resolve UWorld from the player character."
    end

    local actor, spawn_error = spawn_with_world(
        world,
        class_object,
        target_location,
        player_rotation.raw
    )

    if not actor then
        return nil, spawn_error
    end

    spawned_actor = actor
    disable_actor_collision(spawned_actor)

    logger.log(
        "TEST ACTOR SPAWNED. "
        .. "This is a real Palworld Blueprint actor, not an hologram. "
        .. "Press F5 to destroy it."
    )

    return spawned_actor, nil
end

function spawn_test.destroy()
    if not safe_is_valid(spawned_actor) then
        spawned_actor = nil
        return false, "No valid test actor is currently spawned."
    end

    local actor_name = safe_full_name(spawned_actor) or "<unknown>"

    local ok, error_message = pcall(function()
        spawned_actor:K2_DestroyActor()
    end)

    if not ok then
        return false, "K2_DestroyActor failed: " .. tostring(error_message)
    end

    spawned_actor = nil
    logger.log("Test actor destroyed: " .. actor_name)

    return true, nil
end

return spawn_test
