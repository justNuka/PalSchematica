return {
    mod_name = "PalSchematica",
    format_version = 1,

    library = {
        maximum_file_size_bytes = 25 * 1024 * 1024,
        deletion_confirmation_seconds = 8,
    },

    full_preview = {
        anchor_distance = 1200.0,
        height_offset = -100.0,
        scale = 1.0,
        maximum_spawned_meshes = 150,
    },

    keys = {
        refresh_library = Key.F1,
        previous_schematic = Key.F2,
        next_schematic = Key.F3,
        load_selected = Key.F4,
        destroy_preview = Key.F5,
        spawn_preview = Key.F6,
        show_selected_details = Key.F7,
        delete_selected = Key.F8,
        toggle_watch = Key.F9,
    },

    build_name_markers = {
        "BP_BuildObject_",
    },
}
