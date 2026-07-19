return {
    mod_name = "PalSchematica",
    format_version = 1,

    library = {
        maximum_file_size_bytes = 25 * 1024 * 1024,
        deletion_confirmation_seconds = 8,

        manifest_filename = "library.palschemlib",
        manifest_format = "PalSchematicaLibrary",
        manifest_format_version = 1,
    },

    ui = {
        library_duration_seconds = 9.0,
        notification_duration_seconds = 4.0,
    },

    full_preview = {
        anchor_distance = 1200.0,
        height_offset = -100.0,
        scale = 1.0,
        maximum_spawned_meshes = 150,
    },

    keys = {
        manage_library = Key.F10,
        toggle_preview = Key.F6,
        delete_selected = Key.F8,
    },

    build_name_markers = {
        "BP_BuildObject_",
    },
}
