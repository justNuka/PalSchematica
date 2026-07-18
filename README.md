# PalSchematica

Early Palworld 1.0 prototype for capturing and previewing reusable building schematics.

## Current milestone

This build is a read-only discovery probe. It does not place, destroy, or alter any
building and does not write to the Palworld save.

## Install for development

1. Install the Palworld-compatible UE4SS development build.
2. Copy the complete `PalSchematica` folder into the UE4SS `Mods` directory.
3. Enable the UE4SS GUI console and Lua hot reload while developing.
4. Start a backed-up test world.

Expected Steam layout:

```text
Palworld/Pal/Binaries/Win64/ue4ss/Mods/PalSchematica/
```

Some Workshop installations redirect UE4SS mods to a different `Mods` directory.
The invariant is that `PalSchematica/enabled.txt` and
`PalSchematica/Scripts/main.lua` must remain together under UE4SS's active mod root.

## Controls

- `F8`: scan the conservative candidate class list and print matches.
- `F9`: enable or disable logging of newly created build-like actors.
- `Ctrl+R`: hot reload Lua when UE4SS hot reload is enabled.

## First test protocol

1. Load an empty or disposable test world.
2. Confirm the `loaded` message appears in the UE4SS console/log.
3. Press `F8` and retain every `[PalSchematica]` line.
4. Build one wooden foundation, one wall, one roof, and one workbench.
5. Retain the `new build-like actor` lines and their reported classes.
6. Add the exact short class names to `Scripts/config.lua` for the next scan.

The output of this test determines the concrete actor hierarchy used by Palworld 1.0.
Capture and transform serialization should only be implemented after those names are
confirmed from the running game.

## Safety

Use a separate backed-up save during development. Palworld 1.0 changed underlying
systems, so old assumptions and pre-1.0 class names must not be trusted.
