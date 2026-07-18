# PalSchematica – Phase 8E

This Lua version no longer uses:

- `index.txt`;
- `refresh-schematics-index.bat`;
- `io.popen`;
- LuaFileSystem.

It reads:

```text
Schematics/library.palschemlib
```

The file is generated automatically by the separate native C++ mod
`PalSchematicaFilesystem`.

## Controls

```text
F10  Open/refresh the library, then select the next schematic
F6   Show/hide selected preview
F8   Delete selected file with double confirmation
```

After deletion, the native helper detects the change within approximately two
seconds and regenerates the manifest.
