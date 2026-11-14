#!/usr/bin/env python3
"""Regenerate assets/catalog.json from the GLB files in assets/.

The catalog is the single source of truth for:
  * which models the app offers,
  * which GLB asset belongs to each model,
  * which *entities* (glTF node names) must receive a runtime skin texture.

`bodyEntities` is computed by walking every node that has a mesh and dropping
nodes that are clearly not part of the weapon body (stickers, StatTrak counter,
lens/reticle, cartridges, bullets, muzzle/shell helpers).

Run:  python3 tool/generate_catalog.py
"""

from __future__ import annotations

import json
import os
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
OUT = os.path.join(ASSETS, "catalog.json")

# First component(s) of a node name that identify non-body parts.
NON_BODY_PREFIXES = (
    "sticker",
    "stattrack",
    "sticker1",
    "sightlense",
    "sightreticle",
    "cartridge",
    "bullet",
    "charm",
    "muzzle",
    "shell",
)

CATEGORY_ORDER = [
    "Автоматы",
    "Пистолеты",
    "ПП",
    "Снайперские",
    "Дробовики",
    "Пулемёты",
    "Ножи",
    "Гранаты",
    "Другое",
]

META: dict[str, tuple[str, str]] = {
    # id: (display name, category)
    "akimbouzi": ("Akimbouzi", "Пистолеты"),
    "akr": ("AKR", "Автоматы"),
    "akr12": ("AKR-12", "Автоматы"),
    "awm": ("AWM", "Снайперские"),
    "berettas": ("Dual Berettas", "Пистолеты"),
    "butterfly": ("Butterfly Knife", "Ножи"),
    "deagle": ("Desert Eagle", "Пистолеты"),
    "dualdaggers": ("Dual Daggers", "Ножи"),
    "fabm": ("FABM", "Автоматы"),
    "famas": ("FAMAS", "Автоматы"),
    "fang": ("Fang", "Ножи"),
    "flash": ("Flashbang", "Гранаты"),
    "flip": ("Flip Knife", "Ножи"),
    "fnfal": ("FN FAL", "Автоматы"),
    "fs": ("F/S", "Автоматы"),
    "g22": ("G22", "Пистолеты"),
    "he": ("HE Grenade", "Гранаты"),
    "jkommando": ("Jagdkommando", "Ножи"),
    "karambit": ("Karambit", "Ножи"),
    "kukri": ("Kukri", "Ножи"),
    "kunai": ("Kunai", "Ножи"),
    "m110": ("M110", "Снайперские"),
    "m16": ("M16", "Автоматы"),
    "m40": ("M40", "Снайперские"),
    "m4a1": ("M4A1", "Автоматы"),
    "m60": ("M60", "Пулемёты"),
    "m9": ("M9 Bayonet", "Ножи"),
    "mac10": ("MAC-10", "ПП"),
    "mallard": ("Mallard", "Пистолеты"),
    "mantis": ("Mantis", "Ножи"),
    "molotov": ("Molotov", "Гранаты"),
    "mp5": ("MP5", "ПП"),
    "mp7": ("MP7", "ПП"),
    "p350": ("P350", "Пистолеты"),
    "p90": ("P90", "ПП"),
    "scorpion": ("Scorpion", "Ножи"),
    "sm1014": ("SM1014", "Дробовики"),
    "smoke": ("Smoke Grenade", "Гранаты"),
    "spas": ("SPAS-12", "Дробовики"),
    "stiletto": ("Stiletto", "Ножи"),
    "sting": ("Sting", "Ножи"),
    "tanto": ("Tanto", "Ножи"),
    "tec9": ("TEC-9", "Пистолеты"),
    "ump45": ("UMP-45", "ПП"),
    "usp": ("USP", "Пистолеты"),
    "val": ("VAL", "Автоматы"),
}


def read_gltf_json(path: str) -> dict:
    with open(path, "rb") as handle:
        data = handle.read()
    if len(data) < 20:
        raise ValueError(f"{path}: too small")
    magic, version, length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"{path}: not a GLB file")
    if version != 2:
        raise ValueError(f"{path}: unsupported GLB version {version}")
    if length != len(data):
        raise ValueError(f"{path}: declared length {length} != file size {len(data)}")
    offset = 12
    while offset + 8 <= len(data):
        chunk_length, chunk_type = struct.unpack_from("<II", data, offset)
        start = offset + 8
        end = start + chunk_length
        if end > len(data):
            raise ValueError(f"{path}: truncated chunk")
        if chunk_type == 0x4E4F534A:  # JSON
            return json.loads(data[start:end].decode("utf-8"))
        offset = end
    raise ValueError(f"{path}: no JSON chunk")


def body_entities(gltf: dict) -> list[str]:
    nodes = gltf.get("nodes", [])
    entities: list[str] = []
    seen: set[str] = set()
    for node in nodes:
        if "mesh" not in node:
            continue
        name = node.get("name")
        if not isinstance(name, str) or not name:
            continue
        if name.lower().startswith(NON_BODY_PREFIXES):
            continue
        if name in seen:
            continue
        seen.add(name)
        entities.append(name)
    return entities


def main() -> int:
    glb_files = sorted(
        name for name in os.listdir(ASSETS) if name.endswith(".glb")
    )
    if not glb_files:
        print("No .glb files found", file=sys.stderr)
        return 1

    unknown = [name[:-4] for name in glb_files if name[:-4] not in META]
    if unknown:
        print(
            "Missing META entry for: " + ", ".join(sorted(unknown)),
            file=sys.stderr,
        )
        return 1

    models = []
    for file_name in glb_files:
        model_id = file_name[:-4]
        gltf = read_gltf_json(os.path.join(ASSETS, file_name))
        entities = body_entities(gltf)
        if not entities:
            print(f"No body entity found in {file_name}", file=sys.stderr)
            return 1
        display_name, category = META[model_id]
        models.append(
            {
                "id": model_id,
                "name": display_name,
                "category": category,
                "glb": f"assets/{file_name}",
                "bodyEntities": entities,
            }
        )

    models.sort(
        key=lambda model: (
            CATEGORY_ORDER.index(model["category"]),
            model["name"].lower(),
        )
    )

    payload = {
        "version": 1,
        "generatedBy": "tool/generate_catalog.py",
        "models": models,
    }
    with open(OUT, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(payload, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"Wrote {OUT}: {len(models)} models")
    for model in models:
        print(f"  {model['id']:<12} {len(model['bodyEntities'])} entities")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
