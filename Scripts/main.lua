local scripts_directory =
    debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])")

package.path =
    scripts_directory
    .. "?.lua;"
    .. package.path

local config = require("config")
local library = require("library")
local logger = require("logger")
local schematic_preview = require("schematic_preview")
local ui = require("ui")

local loaded_document = nil
local library_opened = false
local preview_visible = false

local function current_view()
    return library.get_view_model()
end

local function show_library_ui()
    ui.show_library(
        current_view(),
        config,
        preview_visible
    )
end

local function load_selected(show_ui)
    local document, error_message =
        library.load_selected()

    if not document then
        loaded_document = nil

        logger.log(
            "Unable to load selected schematic: "
            .. tostring(error_message)
        )

        if show_ui then
            ui.show(
                "PalSchematica error: "
                .. tostring(error_message),
                config.ui.notification_duration_seconds
            )
        end

        return false
    end

    loaded_document = document
    library.log_selected_details()

    logger.log(
        "Selected schematic ready. "
        .. "Press F6 to show/hide it."
    )

    if show_ui then
        show_library_ui()
    end

    return true
end

local function refresh_library(show_ui)
    local success, error_message =
        library.refresh(config)

    if not success then
        logger.log(
            "Library refresh failed: "
            .. tostring(error_message)
        )

        if show_ui then
            ui.show(
                "Library refresh failed: "
                .. tostring(error_message),
                config.ui.library_duration_seconds
            )
        end

        return false
    end

    return load_selected(show_ui)
end

RegisterKeyBind(
    config.keys.manage_library,
    function()
        if not library_opened then
            logger.log("In-game library opened/refreshed")
            library_opened = true
            refresh_library(false)
            ui.open_library(current_view(), config, preview_visible)
            return
        end

        local _, select_error = library.select_next()
        if select_error then
            logger.log(select_error)
            ui.show(tostring(select_error), config.ui.notification_duration_seconds)
            return
        end

        if preview_visible then
            ExecuteInGameThread(function()
                schematic_preview.destroy_all()
                preview_visible = false
            end)
        end

        load_selected(false)
        ui.update_library(current_view(), config, preview_visible)
    end
)

RegisterKeyBind(
    config.keys.toggle_preview,
    function()
        ExecuteInGameThread(function()
            if preview_visible then
                schematic_preview.destroy_all()
                preview_visible = false
                ui.show_preview_state(
                    false,
                    current_view(),
                    config
                )
                return
            end

            if not loaded_document then
                logger.log(
                    "No schematic loaded. Press F10 first."
                )
                ui.show(
                    "No schematic loaded - press F10",
                    config.ui.notification_duration_seconds
                )
                return
            end

            local success, error_message =
                schematic_preview.spawn(
                    loaded_document,
                    config
                )

            if not success then
                logger.log(
                    "Preview creation failed: "
                    .. tostring(error_message)
                )
                ui.show(
                    "Preview failed: "
                    .. tostring(error_message),
                    config.ui.notification_duration_seconds
                )
                return
            end

            preview_visible = true
            ui.show_preview_state(
                true,
                current_view(),
                config
            )
        end)
    end
)

RegisterKeyBind(
    config.keys.delete_selected,
    function()
        if preview_visible then
            ExecuteInGameThread(function()
                schematic_preview.destroy_all()
                preview_visible = false
            end)
        end

        local success, message =
            library.delete_selected(config)

        logger.log(tostring(message))
        ui.show_delete_message(message, config)

        if success then
            loaded_document = nil
            library_opened = false

            logger.log(
                "The native helper will refresh the manifest "
                .. "automatically. Press F10 shortly."
            )
        end
    end
)

logger.clear()

logger.log(
    "Loaded successfully - Phase 10 native ImGui bridge"
)

logger.log(
    "F10 open/next library | "
    .. "F6 show/hide preview | "
    .. "F8 delete selected"
)

logger.log(
    "Library source: Schematics/"
    .. config.library.manifest_filename
)

logger.log(
    "Dedicated log file: "
    .. logger.get_path()
)

local startup_ok, startup_error =
    pcall(function()
        refresh_library(false)
        library_opened = false
    end)

if not startup_ok then
    logger.log(
        "Startup library load raised an error: "
        .. tostring(startup_error)
    )
end


local command_path =
    storage and nil

local function get_command_path()
    local storage_module = require("storage")
    return storage_module.get_schematics_directory()
        .. "imgui-command.json"
end

local function read_and_remove_command()
    local path = get_command_path()
    local file = io.open(path, "rb")
    if not file then
        return nil
    end

    local content = file:read("*a")
    file:close()
    os.remove(path)

    local ok, command = pcall(function()
        return require("json").decode(content)
    end)

    if not ok or type(command) ~= "table" then
        logger.log("Invalid ImGui command: " .. tostring(command))
        return nil
    end

    return command
end

local function apply_imgui_command(command)
    if command.action == "refresh" then
        refresh_library(false)
        return
    end

    if command.file then
        local _, select_error = library.select_filename(command.file)
        if select_error then
            logger.log(select_error)
            return
        end
        load_selected(false)
    end

    if command.action == "select" then
        return
    end

    if command.action == "preview" then
        ExecuteInGameThread(function()
            if preview_visible then
                schematic_preview.destroy_all()
                preview_visible = false
            end

            if not loaded_document then
                logger.log("ImGui preview requested without loaded document")
                return
            end

            local success, error_message = schematic_preview.spawn(loaded_document, config)
            if not success then
                logger.log("ImGui preview failed: " .. tostring(error_message))
                return
            end

            preview_visible = true
        end)
        return
    end

    if command.action == "hide_preview" then
        ExecuteInGameThread(function()
            schematic_preview.destroy_all()
            preview_visible = false
        end)
        return
    end

    if command.action == "delete" then
        if preview_visible then
            ExecuteInGameThread(function()
                schematic_preview.destroy_all()
                preview_visible = false
            end)
        end

        local success, message = library.delete_selected(config)
        logger.log("ImGui delete: " .. tostring(message))
        if success then
            loaded_document = nil
        end
    end
end

LoopAsync(250, function()
    local command = read_and_remove_command()
    if command then
        local ok, error_message = pcall(function()
            apply_imgui_command(command)
        end)
        if not ok then
            logger.log("ImGui command error: " .. tostring(error_message))
        end
    end
    return false
end)

logger.log("Native ImGui command bridge active")
