local scripts_directory =
    debug.getinfo(1, "S").source:sub(2):match("(.*[\\/])")

package.path =
    scripts_directory
    .. "?.lua;"
    .. package.path

local config = require("config")
local library = require("library")
local logger = require("logger")
local schematic_preview =
    require("schematic_preview")

local loaded_document = nil
local library_opened = false
local preview_visible = false

local function load_current_selection()
    local document, error_message =
        library.load_selected()

    if not document then
        loaded_document = nil

        logger.log(
            "Unable to load selected schematic: "
            .. tostring(error_message)
        )

        return false
    end

    loaded_document = document
    library.log_selected_details()

    logger.log(
        "Selected schematic ready. "
        .. "Press F6 to show or hide it."
    )

    return true
end

local function refresh_and_select_first()
    local success, error_message =
        library.refresh(config)

    if not success then
        logger.log(
            "Library refresh failed: "
            .. tostring(error_message)
        )
        return false
    end

    return load_current_selection()
end

RegisterKeyBind(
    config.keys.manage_library,
    function()
        if not library_opened then
            logger.log(
                "Library manager opened/refreshed"
            )

            library_opened = true
            refresh_and_select_first()
            return
        end

        local _, select_error =
            library.select_next()

        if select_error then
            logger.log(select_error)
            return
        end

        load_current_selection()
    end
)

RegisterKeyBind(
    config.keys.toggle_preview,
    function()
        ExecuteInGameThread(function()
            if preview_visible then
                logger.log(
                    "Preview hide requested"
                )

                schematic_preview.destroy_all()
                preview_visible = false
                return
            end

            if not loaded_document then
                logger.log(
                    "No schematic selected. "
                    .. "Press F10 first."
                )
                return
            end

            logger.log(
                "Selected schematic preview requested"
            )

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
                return
            end

            preview_visible = true
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

        if success then
            loaded_document = nil
            library_opened = false

            logger.log(
                "Press F10 to reopen the refreshed library."
            )
        end
    end
)

logger.clear()

logger.log(
    "Loaded successfully - Phase 8B compact library manager"
)

logger.log(
    "F10 library/select next | "
    .. "F6 show/hide preview | "
    .. "F8 delete selected (double confirmation)"
)

logger.log(
    "Official schematic directory: "
    .. "PalSchematica/Schematics"
)

logger.log(
    "Files placed beside enabled.txt are intentionally ignored."
)

logger.log(
    "Dedicated log file: "
    .. logger.get_path()
)

-- Fast startup: index parsing only, no cmd/io.popen.
local startup_ok, startup_error =
    library.refresh(config)

if startup_ok then
    load_current_selection()
    library_opened = true
else
    logger.log(
        "Startup library refresh failed: "
        .. tostring(startup_error)
    )
end
