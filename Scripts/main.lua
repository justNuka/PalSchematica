local scripts_directory =
    debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])")

package.path =
    scripts_directory
    .. "?.lua;"
    .. package.path

local config = require("config")
local inspector = require("inspector")
local library = require("library")
local logger = require("logger")
local schematic_preview = require("schematic_preview")

local watching = false
local loaded_document = nil

logger.clear()

inspector.watch_new_build_actors(
    config,
    function()
        return watching
    end
)

RegisterKeyBind(
    config.keys.refresh_library,
    function()
        logger.log("Library refresh requested")

        local success, error_message =
            library.refresh(config)

        if not success then
            logger.log(
                "Library refresh failed: "
                .. tostring(error_message)
            )
        end
    end
)

RegisterKeyBind(
    config.keys.previous_schematic,
    function()
        local _, error_message =
            library.select_previous()

        if error_message then
            logger.log(error_message)
        end
    end
)

RegisterKeyBind(
    config.keys.next_schematic,
    function()
        local _, error_message =
            library.select_next()

        if error_message then
            logger.log(error_message)
        end
    end
)

RegisterKeyBind(
    config.keys.load_selected,
    function()
        local document, error_message =
            library.load_selected()

        if not document then
            logger.log(
                "Unable to load selected schematic: "
                .. tostring(error_message)
            )
            return
        end

        loaded_document = document

        logger.log(
            "Selected schematic is ready. "
            .. "Press F6 to display its preview."
        )
    end
)

RegisterKeyBind(
    config.keys.destroy_preview,
    function()
        ExecuteInGameThread(function()
            logger.log(
                "Full schematic preview destruction requested"
            )

            schematic_preview.destroy_all()
        end)
    end
)

RegisterKeyBind(
    config.keys.spawn_preview,
    function()
        ExecuteInGameThread(function()
            logger.log(
                "Selected schematic preview requested"
            )

            if not loaded_document then
                logger.log(
                    "No selected schematic is loaded. "
                    .. "Use F1/F2/F3/F4 first."
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
            end
        end)
    end
)

RegisterKeyBind(
    config.keys.show_selected_details,
    function()
        local success, error_message =
            library.log_selected_details()

        if not success then
            logger.log(error_message)
        end
    end
)

RegisterKeyBind(
    config.keys.delete_selected,
    function()
        local success, message =
            library.delete_selected(config)

        if success then
            logger.log(
                message
                or "Selected schematic deleted"
            )
        else
            logger.log(
                tostring(message)
            )
        end
    end
)

RegisterKeyBind(
    config.keys.toggle_watch,
    function()
        watching = not watching

        logger.log(
            "Build actor watcher "
            .. (
                watching
                and "enabled"
                or "disabled"
            )
        )
    end
)

logger.log(
    "Loaded successfully - Phase 8 library manager"
)

logger.log(
    "F1 refresh/list | F2 previous | F3 next | "
    .. "F4 load | F5 destroy preview | "
    .. "F6 preview | F7 details | "
    .. "F8 delete (double confirmation) | "
    .. "F9 watcher"
)

logger.log(
    "Dedicated log file: "
    .. logger.get_path()
)

local startup_ok, startup_error =
    library.refresh(config)

if not startup_ok then
    logger.log(
        "Startup library refresh failed: "
        .. tostring(startup_error)
    )
end
