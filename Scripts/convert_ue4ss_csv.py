from __future__ import annotations

import argparse
import csv
import json
import math
import re
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

VECTOR_RE = re.compile(
    r"\(\s*X=(?P<x>-?\d+(?:\.\d+)?)\s*,\s*Y=(?P<y>-?\d+(?:\.\d+)?)\s*,\s*Z=(?P<z>-?\d+(?:\.\d+)?)\s*\)"
)
ROTATION_RE = re.compile(
    r"\(\s*Pitch=(?P<pitch>-?\d+(?:\.\d+)?)\s*,\s*Yaw=(?P<yaw>-?\d+(?:\.\d+)?)\s*,\s*Roll=(?P<roll>-?\d+(?:\.\d+)?)\s*\)"
)
CLASS_RE = re.compile(r"'(?P<class_path>/Game/.+?\.(?P<class_name>[^./']+))'")

def parse_vector(value: str) -> dict[str, float]:
    match = VECTOR_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(f"Vecteur Unreal invalide : {value!r}")
    return {key: float(match.group(key)) for key in ("x", "y", "z")}

def parse_rotation(value: str) -> dict[str, float]:
    match = ROTATION_RE.fullmatch(value.strip())
    if not match:
        raise ValueError(f"Rotation Unreal invalide : {value!r}")
    return {key: float(match.group(key)) for key in ("pitch", "yaw", "roll")}

def parse_actor(value: str) -> tuple[str, str]:
    match = CLASS_RE.search(value)
    if not match:
        raise ValueError(f"Classe Unreal invalide : {value!r}")
    return match.group("class_name"), match.group("class_path")

def normalize_angle(angle: float) -> float:
    normalized = (angle + 180.0) % 360.0 - 180.0
    return 0.0 if abs(normalized) < 1e-9 else normalized

def rotate_xy(x: float, y: float, degrees: float) -> tuple[float, float]:
    radians = math.radians(degrees)
    cos_a = math.cos(radians)
    sin_a = math.sin(radians)
    return x * cos_a - y * sin_a, x * sin_a + y * cos_a

def convert_csv(
    source: Path,
    destination: Path,
    *,
    schematic_name: str,
    author: str,
    origin_mode: str,
    center: tuple[float, float, float] | None,
    radius: float | None,
) -> dict[str, Any]:
    pieces: list[dict[str, Any]] = []

    with source.open("r", encoding="utf-8-sig", newline="") as handle:
        reader = csv.DictReader(handle)
        for row in reader:
            actor_raw = row.get("Actor", "")
            if "/Game/Pal/Blueprint/MapObject/BuildObject/" not in actor_raw:
                continue

            class_name, class_path = parse_actor(actor_raw)
            location = parse_vector(row["Location"])
            rotation = parse_rotation(row["Rotation"])
            scale = parse_vector(row["Scale"])

            if center is not None and radius is not None:
                dx = location["x"] - center[0]
                dy = location["y"] - center[1]
                dz = location["z"] - center[2]
                if math.sqrt(dx * dx + dy * dy + dz * dz) > radius:
                    continue

            pieces.append({
                "class": class_name,
                "classPath": class_path,
                "worldLocation": location,
                "worldRotation": rotation,
                "scale": scale,
            })

    if not pieces:
        raise RuntimeError("Aucune construction Palworld trouvée dans le CSV.")

    if origin_mode == "lowest_then_min_xy":
        origin_piece = min(
            pieces,
            key=lambda p: (
                p["worldLocation"]["z"],
                p["worldLocation"]["x"],
                p["worldLocation"]["y"],
            ),
        )
        origin_location = dict(origin_piece["worldLocation"])
        origin_yaw = origin_piece["worldRotation"]["yaw"]
    elif origin_mode == "center":
        origin_location = {
            axis: sum(p["worldLocation"][axis] for p in pieces) / len(pieces)
            for axis in ("x", "y", "z")
        }
        origin_yaw = 0.0
    else:
        raise ValueError(f"Mode d'origine inconnu : {origin_mode}")

    converted = []
    for index, piece in enumerate(pieces, start=1):
        dx = piece["worldLocation"]["x"] - origin_location["x"]
        dy = piece["worldLocation"]["y"] - origin_location["y"]
        dz = piece["worldLocation"]["z"] - origin_location["z"]
        relative_x, relative_y = rotate_xy(dx, dy, -origin_yaw)

        converted.append({
            "pieceId": index,
            "class": piece["class"],
            "classPath": piece["classPath"],
            "relativeLocation": {
                "x": round(relative_x, 6),
                "y": round(relative_y, 6),
                "z": round(dz, 6),
            },
            "relativeRotation": {
                "pitch": round(piece["worldRotation"]["pitch"], 6),
                "yaw": round(normalize_angle(piece["worldRotation"]["yaw"] - origin_yaw), 6),
                "roll": round(piece["worldRotation"]["roll"], 6),
            },
            "scale": {
                axis: round(piece["scale"][axis], 6)
                for axis in ("x", "y", "z")
            },
        })

    counts = Counter(piece["class"] for piece in converted)
    xs = [p["relativeLocation"]["x"] for p in converted]
    ys = [p["relativeLocation"]["y"] for p in converted]
    zs = [p["relativeLocation"]["z"] for p in converted]

    document = {
        "format": "PalSchematica",
        "formatVersion": 1,
        "metadata": {
            "name": schematic_name,
            "author": author,
            "createdAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"),
            "source": source.name,
            "pieceCount": len(converted),
        },
        "origin": {
            "worldLocation": {key: round(value, 6) for key, value in origin_location.items()},
            "worldYaw": round(origin_yaw, 6),
            "strategy": origin_mode,
        },
        "bounds": {
            "min": {"x": min(xs), "y": min(ys), "z": min(zs)},
            "max": {"x": max(xs), "y": max(ys), "z": max(zs)},
        },
        "summary": {"classes": dict(sorted(counts.items()))},
        "pieces": converted,
    }

    destination.write_text(
        json.dumps(document, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )
    return document

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Convertit un dump UE4SS actor_data.csv en fichier .palschem."
    )
    parser.add_argument("input_csv", type=Path)
    parser.add_argument("output_palschem", type=Path)
    parser.add_argument("--name", default="Palworld schematic")
    parser.add_argument("--author", default="")
    parser.add_argument(
        "--origin",
        choices=["lowest_then_min_xy", "center"],
        default="lowest_then_min_xy",
    )
    parser.add_argument("--center-x", type=float)
    parser.add_argument("--center-y", type=float)
    parser.add_argument("--center-z", type=float)
    parser.add_argument(
        "--radius",
        type=float,
        help="Rayon 3D en unités Unreal autour du centre fourni.",
    )
    args = parser.parse_args()

    center_values = (args.center_x, args.center_y, args.center_z)
    center = None
    if any(value is not None for value in center_values):
        if not all(value is not None for value in center_values):
            parser.error("--center-x, --center-y et --center-z doivent être fournis ensemble.")
        if args.radius is None:
            parser.error("--radius est requis lorsqu'un centre est fourni.")
        center = center_values

    document = convert_csv(
        args.input_csv,
        args.output_palschem,
        schematic_name=args.name,
        author=args.author,
        origin_mode=args.origin,
        center=center,
        radius=args.radius,
    )
    print(
        f"{document['metadata']['pieceCount']} pièce(s) exportée(s) vers "
        f"{args.output_palschem}"
    )

if __name__ == "__main__":
    main()