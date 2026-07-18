# PalSchematica Phase 8E — Native filesystem helper

## Important

This package contains the helper's **source code**, not a prebuilt DLL.

A UE4SS C++ mod must be built against a compatible UE4SS source/template
version. Building against an unrelated version can cause loading failures or
crashes.

## What the helper does

`PalSchematicaFilesystem`:

1. locates the Palworld installation root from the running executable;
2. scans:

```text
Mods/NativeMods/UE4SS/Mods/PalSchematica/Schematics
```

3. detects every `.palschem`;
4. obtains its size and modification timestamp;
5. writes atomically:

```text
Schematics/library.palschemlib
```

6. checks every two seconds and rewrites the manifest only when the list or
metadata changes.

The helper does not parse schematics and does not manipulate Unreal objects.

## Build prerequisites

- Visual Studio 2022 with Desktop development with C++;
- CMake;
- Git;
- a RE-UE4SS checkout or the official UE4SS C++ template matching the UE4SS
  build used by Palworld.

## Manual build layout

```text
MyMods/
├── CMakeLists.txt
├── RE-UE4SS/
└── PalSchematicaFilesystem/
    ├── CMakeLists.txt
    └── dllmain.cpp
```

Use `CMakeLists.txt.example` as the top-level CMake file, renaming it to
`CMakeLists.txt`.

Then:

```powershell
cmake -S . -B Output
cmake --build Output --config Release
```

The resulting DLL is generally placed under a path similar to:

```text
Output/Binaries/Release/PalSchematicaFilesystem/
```

## Installation

Create:

```text
D:\Steam\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\
PalSchematicaFilesystem\dlls
```

Copy the built DLL there and rename it:

```text
main.dll
```

Enable the helper either through the UE4SS mod configuration or by adding an
`enabled.txt` file in:

```text
PalSchematicaFilesystem
```

The Lua mod remains in its existing `PalSchematica` directory.

## Expected result

At launch, UE4SS should log:

```text
[PalSchematicaFilesystem] Helper loaded
[PalSchematicaFilesystem] Schematics directory: ...
[PalSchematicaFilesystem] Manifest refreshed: 2 schematic(s)
```

The following file should then exist:

```text
PalSchematica/Schematics/library.palschemlib
```

The Phase 8E Lua mod reads that manifest automatically.

## Current controls

```text
F10  Open/refresh library; further presses select the next schematic
F6   Show/hide selected schematic preview
F8   Delete selected schematic with double confirmation
```
