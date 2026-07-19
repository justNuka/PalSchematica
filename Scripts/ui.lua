local ui = {}

local logger = require("logger")

local cached_controller = nil

local function is_valid_object(object)
    if object == nil then
        return false
    end

    local ok, valid = pcall(function()
        return object:IsValid()
    end)

    if ok then
        return valid == true
    end

    return true
end

local function resolve_controller()
    if is_valid_object(cached_controller) then
        return cached_controller
    end

    local controller_class_candidates = {
        "BP_PalPlayerController_C",
        "PalPlayerController",
        "PlayerController",
    }

    for _, class_name in ipairs(controller_class_candidates) do
        local ok, controller = pcall(function()
            return FindFirstOf(class_name)
        end)

        if ok and is_valid_object(controller) then
            cached_controller = controller
            logger.log(
                "In-game UI controller resolved through "
                .. tostring(class_name)
            )
            return controller
        end
    end

    local player_class_candidates = {
        "BP_Player_Female_C",
        "BP_Player_Male_C",
        "BP_PlayerBase_C",
    }

    for _, class_name in ipairs(player_class_candidates) do
        local ok, player = pcall(function()
            return FindFirstOf(class_name)
        end)

        if ok and is_valid_object(player) then
            local controller = nil

            local property_ok = pcall(function()
                controller = player.Controller
            end)

            if property_ok and is_valid_object(controller) then
                cached_controller = controller
                logger.log(
                    "In-game UI controller resolved from player "
                    .. tostring(class_name)
                )
                return controller
            end

            local method_ok = pcall(function()
                controller = player:GetController()
            end)

            if method_ok and is_valid_object(controller) then
                cached_controller = controller
                logger.log(
                    "In-game UI controller resolved with GetController from "
                    .. tostring(class_name)
                )
                return controller
            end
        end
    end

    return nil
end

local function send_client_message(controller, message, duration)
    local attempts = {
        function()
            controller:ClientMessage(
                message,
                FName("PalSchematica"),
                duration
            )
        end,
        function()
            controller:ClientMessage(
                message,
                "PalSchematica",
                duration
            )
        end,
        function()
            controller:ClientMessage(message)
        end,
    }

    local last_error = nil

    for _, attempt in ipairs(attempts) do
        local ok, error_message = pcall(attempt)

        if ok then
            return true, nil
        end

        last_error = error_message
    end

    return false, last_error
end

function ui.show(message, duration)
    ExecuteInGameThread(function()
        local controller = resolve_controller()

        if not controller then
            logger.log(
                "In-game UI unavailable: local PlayerController not found"
            )
            return
        end

        local ok, error_message =
            send_client_message(
                controller,
                tostring(message),
                tonumber(duration) or 6.0
            )

        if not ok then
            cached_controller = nil
            logger.log(
                "In-game UI ClientMessage failed: "
                .. tostring(error_message)
            )
        end
    end)
end

local function format_status(status)
    if status == "compatible" then
        return "OK"
    elseif status == "partial" then
        return "PARTIAL"
    end

    return "INVALID"
end

function ui.show_library(view, config, preview_visible)
    local lines = {
        "PALSCHEMATICA - LIBRARY",
    }

    if not view or view.count == 0 then
        lines[#lines + 1] = "No .palschem file found"
        lines[#lines + 1] = "F10: refresh | F6: preview"
        ui.show(
            table.concat(lines, "\n"),
            config.ui.library_duration_seconds
        )
        return
    end

    lines[#lines + 1] = string.format(
        "Selected %d/%d: %s",
        view.selected_index,
        view.count,
        tostring(view.display_name)
    )

    lines[#lines + 1] = string.format(
        "%s | %d pieces | %s",
        format_status(view.status),
        tonumber(view.piece_count) or 0,
        tostring(view.filename)
    )

    if view.author and view.author ~= "" then
        lines[#lines + 1] =
            "Author: " .. tostring(view.author)
    end

    lines[#lines + 1] =
        preview_visible
        and "Preview: VISIBLE"
        or "Preview: HIDDEN"

    lines[#lines + 1] =
        "F10: next | F6: preview | F8 x2: delete"

    ui.show(
        table.concat(lines, "\n"),
        config.ui.library_duration_seconds
    )
end

function ui.show_preview_state(visible, view, config)
    local name = view
        and view.display_name
        or "No schematic"

    local message = visible
        and ("Preview shown: " .. tostring(name))
        or ("Preview hidden: " .. tostring(name))

    ui.show(
        message,
        config.ui.notification_duration_seconds
    )
end

function ui.show_delete_message(message, config)
    ui.show(
        tostring(message),
        config.ui.notification_duration_seconds
    )
end

return ui
