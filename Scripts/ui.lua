local ui = {}

local logger = require("logger")

local state = {
    widget = nil,
    tree = nil,
    canvas = nil,
    border = nil,
    text = nil,
    opened = false,
}

local function valid(object)
    if object == nil then return false end
    local ok, result = pcall(function() return object:IsValid() end)
    return not ok or result == true
end

local function find(path)
    local ok, object = pcall(function() return StaticFindObject(path) end)
    if ok and valid(object) then return object end
    return nil
end

local function construct(class_object, outer)
    if not class_object then return nil end
    local ok, object = pcall(function()
        return StaticConstructObject(class_object, outer)
    end)
    if ok and valid(object) then return object end
    return nil
end

local function resolve_controller()
    for _, name in ipairs({"BP_PalPlayerController_C", "PalPlayerController", "PlayerController"}) do
        local ok, controller = pcall(function() return FindFirstOf(name) end)
        if ok and valid(controller) then return controller end
    end
    return nil
end

local function make_margin(left, top, right, bottom)
    if type(FMargin) == "function" then
        local ok, margin = pcall(function() return FMargin(left, top, right, bottom) end)
        if ok then return margin end
    end
    return { Left = left, Top = top, Right = right, Bottom = bottom }
end

local function make_color(r, g, b, a)
    if type(FLinearColor) == "function" then
        local ok, color = pcall(function() return FLinearColor(r, g, b, a) end)
        if ok then return color end
    end
    return { R = r, G = g, B = b, A = a }
end

local function set_text(text_widget, value)
    if not valid(text_widget) then return false end
    local attempts = {
        function() text_widget:SetText(FText(value)) end,
        function() text_widget.Text = FText(value) end,
        function() text_widget:SetText(value) end,
    }
    for _, attempt in ipairs(attempts) do
        if pcall(attempt) then return true end
    end
    return false
end

local function set_visible(widget, visible)
    if not valid(widget) then return end
    local visibility = visible and 0 or 2 -- Visible / Collapsed
    pcall(function() widget:SetVisibility(visibility) end)
end

local function destroy_widget()
    if valid(state.widget) then
        pcall(function() state.widget:RemoveFromParent() end)
    end
    state.widget = nil
    state.tree = nil
    state.canvas = nil
    state.border = nil
    state.text = nil
    state.opened = false
end

local function create_widget()
    if valid(state.widget) then return true end

    local controller = resolve_controller()
    if not controller then
        logger.log("UMG menu creation failed: PlayerController not found")
        return false
    end

    local c_user_widget = find("/Script/UMG.UserWidget")
    local c_widget_tree = find("/Script/UMG.WidgetTree")
    local c_canvas = find("/Script/UMG.CanvasPanel")
    local c_border = find("/Script/UMG.Border")
    local c_text = find("/Script/UMG.TextBlock")
    local widget_library = find("/Script/UMG.Default__WidgetBlueprintLibrary")

    if not (c_user_widget and c_widget_tree and c_canvas and c_text) then
        logger.log("UMG menu creation failed: one or more UMG classes are unavailable")
        return false
    end

    local widget = nil
    if widget_library then
        pcall(function()
            widget = widget_library:Create(controller, c_user_widget, controller)
        end)
    end
    if not valid(widget) then
        widget = construct(c_user_widget, controller)
    end
    if not valid(widget) then
        logger.log("UMG menu creation failed: UserWidget could not be created")
        return false
    end

    local tree = construct(c_widget_tree, widget)
    local canvas = construct(c_canvas, tree)
    local text = construct(c_text, tree)
    if not (valid(tree) and valid(canvas) and valid(text)) then
        logger.log("UMG menu creation failed: widget tree objects could not be created")
        pcall(function() widget:RemoveFromParent() end)
        return false
    end

    pcall(function() widget.WidgetTree = tree end)
    pcall(function() tree.RootWidget = canvas end)

    local content_parent = canvas
    local border = nil
    if c_border then
        border = construct(c_border, tree)
        if valid(border) then
            local border_slot = nil
            pcall(function() border_slot = canvas:AddChild(border) end)
            if valid(border_slot) then
                pcall(function() border_slot:SetPosition({X = 36.0, Y = 100.0}) end)
                pcall(function() border_slot:SetSize({X = 590.0, Y = 410.0}) end)
                pcall(function() border_slot:SetAnchors({Minimum={X=0.0,Y=0.0}, Maximum={X=0.0,Y=0.0}}) end)
            end
            pcall(function() border:SetBrushColor(make_color(0.015, 0.025, 0.04, 0.94)) end)
            pcall(function() border:SetPadding(make_margin(22, 18, 22, 18)) end)
            pcall(function() border:SetContent(text) end)
            content_parent = border
        end
    end

    if content_parent == canvas then
        local text_slot = nil
        pcall(function() text_slot = canvas:AddChild(text) end)
        if valid(text_slot) then
            pcall(function() text_slot:SetPosition({X = 48.0, Y = 112.0}) end)
            pcall(function() text_slot:SetSize({X = 550.0, Y = 380.0}) end)
        end
    end

    pcall(function() text:SetColorAndOpacity(make_color(0.88, 0.96, 1.0, 1.0)) end)
    pcall(function() text:SetAutoWrapText(true) end)
    pcall(function() text:SetJustification(0) end)
    pcall(function() text:SetMinDesiredWidth(520.0) end)

    local added = pcall(function() widget:AddToViewport(10000) end)
    if not added then
        logger.log("UMG menu creation failed: AddToViewport failed")
        return false
    end

    state.widget = widget
    state.tree = tree
    state.canvas = canvas
    state.border = border
    state.text = text
    state.opened = true
    set_visible(widget, true)
    logger.log("Native UMG library panel created and added to viewport")
    return true
end

local function format_library(view, preview_visible)
    if not view or not view.selected then
        return table.concat({
            "PALSCHEMATICA",
            "",
            "No compatible schematic found.",
            "",
            "F10  Refresh / close",
        }, "\n")
    end

    local selected = view.selected
    local lines = {
        "PALSCHEMATICA  •  LIBRARY OPEN",
        "────────────────────────────────────────",
        string.format("Selected  %d / %d", view.selected_index or 1, view.count or 1),
        "",
        tostring(selected.name or selected.file or "Unnamed schematic"),
        tostring(selected.file or ""),
        "",
        string.format("Status      %s", tostring(selected.status or "UNKNOWN")),
        string.format("Pieces      %s", tostring(selected.piece_count or selected.pieces or "?")),
        string.format("Author      %s", tostring(selected.author or "Unknown")),
        string.format("Preview     %s", preview_visible and "VISIBLE" or "HIDDEN"),
        "",
        "F10  Next schematic / close with Shift+F10",
        "F6   Show or hide preview",
        "F8   Delete (press twice)",
    }
    return table.concat(lines, "\n")
end

function ui.open_library(view, config, preview_visible)
    ExecuteInGameThread(function()
        if not create_widget() then return end
        state.opened = true
        set_visible(state.widget, true)
        set_text(state.text, format_library(view, preview_visible))
    end)
end

function ui.update_library(view, config, preview_visible)
    ExecuteInGameThread(function()
        if not valid(state.widget) then
            if not create_widget() then return end
        end
        state.opened = true
        set_visible(state.widget, true)
        set_text(state.text, format_library(view, preview_visible))
    end)
end

function ui.close_library()
    ExecuteInGameThread(function()
        if valid(state.widget) then set_visible(state.widget, false) end
        state.opened = false
        logger.log("Native UMG library panel closed")
    end)
end

function ui.toggle_library(view, config, preview_visible)
    if state.opened then
        ui.close_library()
        return false
    end
    ui.open_library(view, config, preview_visible)
    return true
end

function ui.is_open()
    return state.opened
end

function ui.show(message, duration)
    -- Reuse the permanent panel instead of Shipping-disabled PrintString.
    ExecuteInGameThread(function()
        if not valid(state.widget) then
            if not create_widget() then return end
        end
        state.opened = true
        set_visible(state.widget, true)
        set_text(state.text, "PALSCHEMATICA\n\n" .. tostring(message))
    end)
end

function ui.show_library(view, config, preview_visible)
    ui.update_library(view, config, preview_visible)
end

function ui.show_preview_state(visible, view, config)
    ui.update_library(view, config, visible)
end

function ui.show_delete_message(message, config)
    ui.show(tostring(message), 8)
end

function ui.destroy()
    ExecuteInGameThread(destroy_widget)
end

return ui
