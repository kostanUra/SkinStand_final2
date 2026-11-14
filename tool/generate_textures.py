#!/usr/bin/env python3
"""Generate the skin textures and the tag manifest.

The files in ``assets/tags/`` are catalog *previews* (screenshots of a skin
store UI), so they can never be used as base-color textures: they are pictures
of a whole weapon, include UI chrome and are 1280x591 (not a square UV atlas).

This script generates one real, texture-like, square image per tag into
``assets/textures/`` and writes ``assets/tags/manifest.json`` describing both
the preview and the texture.

Requirements: numpy, Pillow.
Run:  python3 tool/generate_textures.py
"""

from __future__ import annotations

import json
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "assets")
TEXTURES = os.path.join(ASSETS, "textures")
TAGS = os.path.join(ASSETS, "tags")
OUT_MANIFEST = os.path.join(TAGS, "manifest.json")

SIZE = 1024
QUALITY = 86

Y, X = np.mgrid[0:SIZE, 0:SIZE].astype(np.float32) / SIZE

# id, display name, accent, preview file, generator
TAGS_SPEC = [
    ("carbon", "Carbon", "#3A3A3A", "carbon.jpg"),
    ("chameleon", "Chameleon", "#4FC3A1", "chameleon.jpg"),
    ("daybreak", "Daybreak", "#F5A623", "daybreak.jpg"),
    ("digital-burst", "Digital Burst", "#C05CFF", "digital burst.jpg"),
    ("dust-devil", "Dust Devil", "#C9A227", "dust devil.jpg"),
    ("fury", "Fury", "#E53935", "fury.jpg"),
    ("geometric", "Geometric", "#3F8CFF", "geometric.jpg"),
    ("haunt", "Haunt", "#9FD4D0", "haunt.jpg"),
    ("hunter", "Hunter", "#6B7A3A", "hunter.jpg"),
    ("lich", "Lich", "#2BB3A3", "lich.jpg"),
    ("monster", "Monster", "#5DBB3F", "monster.jpg"),
    ("nebula", "Nebula", "#8A6CFF", "nebula.jpg"),
    ("necromancer", "Necromancer", "#7B3FA0", "necromancer.jpg"),
    ("noxious", "Noxious", "#B6D62C", "noxious.jpg"),
    ("poison", "Poison", "#39C24A", "poison.jpg"),
    ("radiation", "Radiation", "#F2E205", "radiation.jpg"),
    ("samurai", "Samurai", "#D62828", "samurai.jpg"),
    ("scratch", "Scratch", "#9AA0A6", "scratch.jpg"),
    ("sport-v2", "Sport V2", "#2F6BFF", "sport v2.jpg"),
    ("stone-cold", "Stone Cold", "#8C8C8C", "stone cold.jpg"),
    ("thorn", "Thorn", "#8E1B2C", "thorn.jpg"),
    ("tiger", "Tiger", "#F08C1A", "tiger.jpg"),
    ("venom", "Venom", "#7BD32F", "venom.jpg"),
    ("winter-sport", "Winter Sport", "#8CC8FF", "winter sport.jpg"),
]


def norm(array: np.ndarray) -> np.ndarray:
    low = float(array.min())
    high = float(array.max())
    return (array - low) / (high - low + 1e-6)


def waves(freqs, seed: int) -> np.ndarray:
    """Sum of integer-frequency sinusoids -> smooth, tileable noise."""
    rng = np.random.default_rng(seed)
    out = np.zeros((SIZE, SIZE), np.float32)
    for fx, fy in freqs:
        out += rng.uniform(0.35, 1.0) * np.sin(
            2.0 * np.pi * (fx * X + fy * Y) + rng.uniform(0.0, 2.0 * np.pi)
        )
    return norm(out)


def palette(t: np.ndarray, stops) -> np.ndarray:
    positions = np.array([stop[0] for stop in stops], np.float32)
    colors = np.array([stop[1] for stop in stops], np.float32)
    out = np.zeros((SIZE, SIZE, 3), np.float32)
    for channel in range(3):
        out[..., channel] = np.interp(np.clip(t, 0.0, 1.0), positions, colors[:, channel])
    return out


def mix(base: np.ndarray, layer: np.ndarray, amount: np.ndarray | float) -> np.ndarray:
    return base * (1.0 - amount) + layer * amount


def to_image(rgb: np.ndarray) -> Image.Image:
    data = np.clip(rgb, 0.0, 1.0) * 255.0
    return Image.fromarray(data.astype(np.uint8), mode="RGB")


def radial(cx: float, cy: float, radius: float) -> np.ndarray:
    return np.exp(-(((X - cx) ** 2 + (Y - cy) ** 2) / (radius ** 2)))


# --------------------------------------------------------------------------
# individual designs
# --------------------------------------------------------------------------


def design_carbon() -> np.ndarray:
    weave_a = (np.sin(2 * np.pi * (26 * X + 26 * Y)) > 0.15).astype(np.float32)
    weave_b = (np.sin(2 * np.pi * (26 * X - 26 * Y)) > 0.15).astype(np.float32)
    fine = waves([(96, 0), (0, 96), (61, 37)], 7)
    base = 0.055 + 0.085 * weave_a + 0.05 * weave_b + 0.05 * fine
    return np.stack([base * 0.94, base, base * 1.1], -1)


def design_chameleon() -> np.ndarray:
    field = waves([(1, 1), (2, -1), (3, 2)], 21)
    t = 0.5 + 0.5 * np.sin(2 * np.pi * (1.4 * X + 0.8 * Y) + 2.2 * field)
    rgb = palette(
        t,
        [
            (0.0, (0.05, 0.18, 0.16)),
            (0.25, (0.13, 0.55, 0.47)),
            (0.5, (0.42, 0.85, 0.55)),
            (0.72, (0.15, 0.45, 0.62)),
            (1.0, (0.55, 0.25, 0.65)),
        ],
    )
    sheen = 0.25 * (0.5 + 0.5 * np.sin(2 * np.pi * (7 * X - 5 * Y)))
    return np.clip(rgb + sheen[..., None] * 0.35, 0, 1)


def design_daybreak() -> np.ndarray:
    t = np.clip(Y * 1.05 + 0.12 * waves([(2, 1), (4, -2)], 31) - 0.05, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.04, 0.05, 0.14)),
            (0.32, (0.22, 0.14, 0.36)),
            (0.48, (0.78, 0.28, 0.32)),
            (0.56, (1.0, 0.68, 0.32)),
            (0.66, (1.0, 0.9, 0.62)),
            (1.0, (0.18, 0.22, 0.42)),
        ],
    )
    glow = radial(0.5, 0.58, 0.22)
    return np.clip(rgb + glow[..., None] * np.array([0.55, 0.42, 0.18]), 0, 1)


def design_digital_burst() -> np.ndarray:
    rng = np.random.default_rng(51)
    cells = 32
    blocks = rng.random((cells, cells)).astype(np.float32)
    blocks = np.kron(blocks, np.ones((SIZE // cells, SIZE // cells), np.float32))
    blocks = np.clip(blocks * 0.9 + 0.05 * waves([(12, 5), (5, 12)], 52), 0, 1)
    rgb = palette(
        blocks,
        [
            (0.0, (0.06, 0.02, 0.14)),
            (0.35, (0.32, 0.08, 0.55)),
            (0.62, (0.72, 0.2, 0.85)),
            (0.85, (0.95, 0.35, 0.75)),
            (1.0, (0.35, 0.85, 1.0)),
        ],
    )
    scan = 0.5 + 0.5 * np.sin(2 * np.pi * 256 * Y)
    rgba = rgb * (0.85 + 0.15 * scan[..., None])
    lines = ((np.arange(SIZE) // 16) % 2 == 0).astype(np.float32)
    rgba = rgba * (0.9 + 0.1 * lines.reshape(1, -1, 1))
    return np.clip(rgba, 0, 1)


def design_dust_devil() -> np.ndarray:
    swirl = waves([(3, 1), (5, -2), (8, 3), (13, -5)], 61)
    bands = 0.5 + 0.5 * np.sin(2 * np.pi * (2 * X - 3 * Y) + 5.0 * swirl)
    t = np.clip(0.55 * swirl + 0.45 * bands, 0, 1)
    return palette(
        t,
        [
            (0.0, (0.09, 0.06, 0.04)),
            (0.3, (0.42, 0.26, 0.11)),
            (0.55, (0.76, 0.55, 0.24)),
            (0.78, (0.89, 0.77, 0.52)),
            (1.0, (0.98, 0.95, 0.86)),
        ],
    )


def design_fury() -> np.ndarray:
    field = waves([(2, 1), (3, -2), (5, 4), (8, -3), (13, 7)], 71)
    vein = (np.abs(field - 0.5) < 0.025).astype(np.float32)
    t = np.clip(field * 1.1, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.08, 0.01, 0.01)),
            (0.3, (0.42, 0.03, 0.02)),
            (0.55, (0.85, 0.14, 0.03)),
            (0.75, (1.0, 0.45, 0.05)),
            (1.0, (1.0, 0.9, 0.55)),
        ],
    )
    glow = Image.fromarray((vein * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(2))
    glow_arr = np.asarray(glow, np.float32) / 255.0
    return np.clip(rgb + glow_arr[..., None] * np.array([1.0, 0.55, 0.1]), 0, 1)


def design_geometric() -> np.ndarray:
    u = np.abs(((6 * X + 3 * Y) % 1.0) - 0.5)
    v = np.abs(((6 * X - 3 * Y) % 1.0) - 0.5)
    w = np.abs(((3 * Y) % 1.0) - 0.5)
    lines = ((np.minimum(np.minimum(u, v), w) < 0.02)).astype(np.float32)
    noise = waves([(4, 1), (7, -3)], 81)
    base = np.stack(
        [
            0.05 + 0.10 * noise,
            0.08 + 0.16 * noise,
            0.16 + 0.26 * noise,
        ],
        -1,
    )
    accent = np.array([0.18, 0.62, 1.0], np.float32)
    return np.clip(base + lines[..., None] * accent, 0, 1)


def design_haunt() -> np.ndarray:
    base = 0.42 + 0.3 * waves([(1, 2), (3, -1), (5, 3)], 91)
    wisps = 0.5 + 0.5 * np.sin(
        2 * np.pi * (5 * X + 1.5 * Y) + 3.0 * waves([(2, 2), (6, -4)], 92)
    )
    t = np.clip(0.6 * base + 0.4 * wisps, 0, 1)
    return palette(
        t,
        [
            (0.0, (0.06, 0.09, 0.1)),
            (0.35, (0.16, 0.3, 0.32)),
            (0.6, (0.44, 0.66, 0.66)),
            (0.82, (0.74, 0.88, 0.86)),
            (1.0, (0.95, 0.99, 0.97)),
        ],
    )


def design_hunter() -> np.ndarray:
    field = waves([(1, 1), (2, -2), (4, 3), (7, -5)], 101)
    levels = np.digitize(field, [0.36, 0.55, 0.74]).astype(np.float32) / 3.0
    rgb = palette(
        levels,
        [
            (0.0, (0.16, 0.17, 0.10)),
            (0.34, (0.29, 0.31, 0.16)),
            (0.67, (0.42, 0.42, 0.22)),
            (1.0, (0.55, 0.52, 0.3)),
        ],
    )
    grain = (waves([(60, 0), (0, 60)], 102) - 0.5) * 0.06
    return np.clip(rgb + grain[..., None], 0, 1)


def design_lich() -> np.ndarray:
    field = waves([(2, 1), (3, -1), (5, 2)], 111)
    veins = 0.5 + 0.5 * np.sin(2 * np.pi * (3 * X + 0.4 * field))
    veins *= 0.5 + 0.5 * np.sin(2 * np.pi * (4 * Y - 0.3 * field))
    vein_mask = Image.fromarray(((veins > 0.72) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(2)
    )
    glow = np.asarray(vein_mask, np.float32) / 255.0
    t = np.clip(0.35 * field + 0.4 * veins, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.02, 0.08, 0.07)),
            (0.4, (0.06, 0.26, 0.24)),
            (0.7, (0.12, 0.52, 0.45)),
            (1.0, (0.55, 0.95, 0.8)),
        ],
    )
    return np.clip(rgb + glow[..., None] * np.array([0.2, 0.9, 0.7]), 0, 1)


def design_monster() -> np.ndarray:
    scales = np.sin(2 * np.pi * 18 * X) * np.sin(2 * np.pi * 18 * Y)
    mask = (scales > 0.15).astype(np.float32)
    noise = waves([(2, 1), (5, -2), (9, 4)], 121)
    t = np.clip(0.5 * mask + 0.5 * noise, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.05, 0.14, 0.05)),
            (0.35, (0.14, 0.34, 0.09)),
            (0.62, (0.3, 0.6, 0.12)),
            (0.85, (0.62, 0.82, 0.2)),
            (1.0, (0.86, 0.95, 0.5)),
        ],
    )
    ridge = np.abs(scales) ** 6
    return np.clip(rgb * (0.85 + 0.25 * ridge[..., None]), 0, 1)


def design_nebula() -> np.ndarray:
    field = waves([(1, 1), (2, -1), (3, 2), (5, -3)], 131)
    second = waves([(1, -2), (4, 1), (6, 3)], 132)
    t = np.clip(0.6 * field + 0.4 * second, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.02, 0.01, 0.06)),
            (0.28, (0.16, 0.05, 0.35)),
            (0.5, (0.42, 0.12, 0.62)),
            (0.7, (0.18, 0.32, 0.72)),
            (0.88, (0.35, 0.72, 0.9)),
            (1.0, (0.92, 0.92, 1.0)),
        ],
    )
    rng = np.random.default_rng(133)
    stars = np.zeros((SIZE, SIZE, 3), np.float32)
    count = 1400
    ys = rng.integers(0, SIZE, count)
    xs = rng.integers(0, SIZE, count)
    brightness = rng.uniform(0.35, 1.0, count) ** 2
    stars[ys, xs] = brightness[:, None]
    glow = Image.fromarray((np.clip(stars[..., 0], 0, 1) * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(1.6)
    )
    glow_arr = np.asarray(glow, np.float32)[..., None] / 255.0
    return np.clip(rgb + stars * 0.9 + glow_arr, 0, 1)


def design_necromancer() -> np.ndarray:
    field = waves([(3, 1), (5, -2), (8, 3)], 141)
    cracks = np.minimum(
        np.abs(np.sin(2 * np.pi * (5 * X + 0.5 * field))),
        np.abs(np.sin(2 * np.pi * (6 * Y - 0.4 * field))),
    )
    crack_mask = (cracks < 0.02).astype(np.float32)
    base_t = np.clip(0.25 + 0.5 * field, 0, 1)
    rgb = palette(
        base_t,
        [
            (0.0, (0.03, 0.02, 0.05)),
            (0.5, (0.14, 0.06, 0.2)),
            (1.0, (0.32, 0.14, 0.4)),
        ],
    )
    glow = Image.fromarray((crack_mask * 255).astype(np.uint8)).filter(
        ImageFilter.GaussianBlur(3)
    )
    glow_arr = np.asarray(glow, np.float32)[..., None] / 255.0
    return np.clip(rgb + glow_arr * np.array([0.55, 0.2, 0.95]), 0, 1)


def design_noxious() -> np.ndarray:
    field = waves([(1, 2), (3, -2), (6, 3)], 151)
    levels = np.digitize(field, [0.3, 0.5, 0.72]).astype(np.float32) / 3.0
    rgb = palette(
        levels,
        [
            (0.0, (0.07, 0.1, 0.02)),
            (0.34, (0.28, 0.4, 0.05)),
            (0.67, (0.55, 0.72, 0.08)),
            (1.0, (0.82, 0.92, 0.25)),
        ],
    )
    spots = (waves([(9, 7), (7, -9)], 152) > 0.82).astype(np.float32)
    return np.clip(rgb * (1.0 - 0.35 * spots[..., None]), 0, 1)


def design_poison() -> np.ndarray:
    field = waves([(2, 1), (4, -3), (7, 2)], 161)
    drip = 0.5 + 0.5 * np.sin(2 * np.pi * (16 * X + 0.8 * field))
    t = np.clip(0.45 * field + 0.55 * drip, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.02, 0.08, 0.03)),
            (0.35, (0.06, 0.3, 0.1)),
            (0.62, (0.16, 0.62, 0.18)),
            (0.85, (0.45, 0.9, 0.3)),
            (1.0, (0.8, 1.0, 0.55)),
        ],
    )
    bubbles = Image.fromarray(
        ((waves([(11, 5), (5, -11)], 162) > 0.88) * 255).astype(np.uint8)
    ).filter(ImageFilter.GaussianBlur(4))
    bubble_arr = np.asarray(bubbles, np.float32)[..., None] / 255.0
    return np.clip(rgb + bubble_arr * np.array([0.3, 0.9, 0.2]), 0, 1)


def design_radiation() -> np.ndarray:
    stripes = (((8 * X + 8 * Y) % 1.0) < 0.5).astype(np.float32)
    noise = waves([(20, 0), (0, 20), (13, 7)], 171)
    yellow = np.array([0.95, 0.85, 0.05], np.float32)
    dark = np.array([0.06, 0.06, 0.05], np.float32)
    rgb = mix(dark[None, None, :], yellow[None, None, :], stripes[..., None])
    grain = (noise - 0.5) * 0.18
    worn = (waves([(3, 1), (7, -2)], 172) > 0.8).astype(np.float32)
    rgb = np.clip(rgb + grain[..., None] - 0.25 * worn[..., None], 0, 1)
    return rgb


def design_samurai() -> np.ndarray:
    warp = np.sin(2 * np.pi * (3 * Y)) * 0.35 + waves([(2, 1)], 181) * 0.2
    wave = np.sin(2 * np.pi * (4 * X + warp))
    bands = (wave > 0.62).astype(np.float32)
    edge = (np.abs(wave - 0.62) < 0.05).astype(np.float32)
    base = np.stack(
        [
            0.06 + 0.05 * waves([(2, 1), (5, -2)], 182),
            0.03 + 0.03 * waves([(3, -1), (7, 2)], 183),
            0.04 + 0.03 * waves([(2, 2), (6, -3)], 184),
        ],
        -1,
    )
    red = np.array([0.75, 0.06, 0.08], np.float32)
    white = np.array([0.95, 0.9, 0.86], np.float32)
    rgb = base + bands[..., None] * red + edge[..., None] * white * 0.55
    return np.clip(rgb, 0, 1)


def design_scratch() -> np.ndarray:
    brushed = waves([(0, 160), (3, 120), (11, 60)], 191)
    base = 0.34 + 0.22 * brushed
    rgb = np.stack([base * 0.98, base, base * 1.04], -1)
    rng = np.random.default_rng(192)
    scratches = Image.new("L", (SIZE, SIZE), 0)
    draw = ImageDraw.Draw(scratches)
    for _ in range(120):
        y = int(rng.integers(0, SIZE))
        x0 = int(rng.integers(0, SIZE))
        length = int(rng.integers(40, 420))
        draw.line((x0, y, x0 + length, y + int(rng.integers(-3, 4))), fill=int(rng.integers(80, 220)), width=1)
    arr = np.asarray(scratches, np.float32)[..., None] / 255.0
    return np.clip(rgb + arr * 0.5, 0, 1)


def design_sport_v2() -> np.ndarray:
    base = np.ones((SIZE, SIZE, 3), np.float32) * 0.94
    blue = np.array([0.1, 0.28, 0.85], np.float32)
    cyan = np.array([0.1, 0.7, 0.95], np.float32)
    a = (((5 * X + 2 * Y) % 1.0) < 0.34).astype(np.float32)
    b = (((5 * X + 2 * Y) % 1.0) > 0.42).astype(np.float32) * (
        ((3 * X - 4 * Y) % 1.0 < 0.25).astype(np.float32)
    )
    gap = ((((5 * X + 2 * Y) % 1.0) > 0.34) & (((5 * X + 2 * Y) % 1.0) < 0.37)).astype(np.float32)
    rgb = base + a[..., None] * blue + b[..., None] * cyan + gap[..., None] * 0.0
    rgb = rgb - gap[..., None] * 0.06
    return np.clip(rgb, 0, 1)


def design_stone_cold() -> np.ndarray:
    field = waves([(2, 1), (3, -1), (5, 2), (9, -4)], 201)
    fine = waves([(48, 0), (0, 48), (37, 19)], 202)
    t = np.clip(0.7 * field + 0.3 * fine, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.12, 0.13, 0.14)),
            (0.3, (0.3, 0.31, 0.32)),
            (0.55, (0.48, 0.49, 0.5)),
            (0.78, (0.66, 0.67, 0.68)),
            (1.0, (0.84, 0.85, 0.86)),
        ],
    )
    rng = np.random.default_rng(203)
    speck = rng.random((SIZE, SIZE)) < 0.004
    rgb[speck] = 0.08
    bright = (rng.random((SIZE, SIZE)) < 0.002)
    rgb[bright] = 0.95
    return rgb


def design_thorn() -> np.ndarray:
    field = waves([(3, 2), (6, -1)], 211)
    thorns = np.abs(np.sin(2 * np.pi * (9 * X + 0.5 * np.sin(2 * np.pi * 2 * Y) + 0.3 * field)))
    mask = (thorns < 0.06).astype(np.float32)
    tips = (thorns < 0.02).astype(np.float32)
    base = palette(
        np.clip(0.3 + 0.5 * field, 0, 1),
        [
            (0.0, (0.05, 0.02, 0.03)),
            (0.5, (0.2, 0.05, 0.08)),
            (1.0, (0.4, 0.1, 0.14)),
        ],
    )
    return np.clip(
        base - mask[..., None] * 0.12 + tips[..., None] * np.array([0.55, 0.2, 0.2]), 0, 1
    )


def design_tiger() -> np.ndarray:
    field = waves([(2, 1), (4, -2), (7, 3)], 221)
    warp = 0.18 * np.sin(2 * np.pi * 3 * Y) + 0.25 * field
    bands = np.abs(np.sin(2 * np.pi * (7 * X + warp * 3)))
    stripe = (bands < 0.3).astype(np.float32)
    base = palette(
        np.clip(0.55 + 0.45 * np.sin(2 * np.pi * (0.5 * Y + 0.2 * field)), 0, 1),
        [
            (0.0, (0.35, 0.14, 0.02)),
            (0.45, (0.78, 0.38, 0.05)),
            (0.75, (0.95, 0.62, 0.12)),
            (1.0, (0.99, 0.82, 0.4)),
        ],
    )
    fur = (waves([(90, 20), (20, 90)], 222) - 0.5) * 0.12
    rgb = base + fur[..., None]
    return np.clip(rgb * (1.0 - 0.92 * stripe[..., None]), 0, 1)


def design_venom() -> np.ndarray:
    field_a = waves([(2, 1), (5, -2), (8, 3)], 231)
    field_b = waves([(1, 3), (4, -5), (7, 2)], 232)
    t = np.clip(0.6 * field_a + 0.4 * field_b, 0, 1)
    rgb = palette(
        t,
        [
            (0.0, (0.03, 0.09, 0.02)),
            (0.3, (0.16, 0.42, 0.06)),
            (0.5, (0.4, 0.72, 0.12)),
            (0.68, (0.28, 0.2, 0.55)),
            (0.85, (0.5, 0.24, 0.72)),
            (1.0, (0.75, 0.45, 0.9)),
        ],
    )
    veins = (np.abs(field_b - 0.5) < 0.015).astype(np.float32)
    return np.clip(rgb + veins[..., None] * np.array([0.3, 0.9, 0.2]), 0, 1)


def design_winter_sport() -> np.ndarray:
    field = waves([(1, 1), (3, -2), (5, 3)], 241)
    levels = np.digitize(field, [0.34, 0.55, 0.76]).astype(np.float32) / 3.0
    rgb = palette(
        levels,
        [
            (0.0, (0.16, 0.32, 0.52)),
            (0.34, (0.35, 0.55, 0.75)),
            (0.67, (0.66, 0.79, 0.9)),
            (1.0, (0.93, 0.97, 1.0)),
        ],
    )
    sparkle = Image.fromarray(
        ((waves([(70, 30), (30, -70)], 242) > 0.93) * 255).astype(np.uint8)
    ).filter(ImageFilter.GaussianBlur(1.2))
    spark_arr = np.asarray(sparkle, np.float32)[..., None] / 255.0
    return np.clip(rgb + spark_arr * 0.5, 0, 1)


DESIGNS = {
    "carbon": design_carbon,
    "chameleon": design_chameleon,
    "daybreak": design_daybreak,
    "digital-burst": design_digital_burst,
    "dust-devil": design_dust_devil,
    "fury": design_fury,
    "geometric": design_geometric,
    "haunt": design_haunt,
    "hunter": design_hunter,
    "lich": design_lich,
    "monster": design_monster,
    "nebula": design_nebula,
    "necromancer": design_necromancer,
    "noxious": design_noxious,
    "poison": design_poison,
    "radiation": design_radiation,
    "samurai": design_samurai,
    "scratch": design_scratch,
    "sport-v2": design_sport_v2,
    "stone-cold": design_stone_cold,
    "thorn": design_thorn,
    "tiger": design_tiger,
    "venom": design_venom,
    "winter-sport": design_winter_sport,
}


def main() -> int:
    os.makedirs(TEXTURES, exist_ok=True)
    tags = []
    total = 0
    for tag_id, name, accent, preview in TAGS_SPEC:
        texture_name = f"{tag_id}.jpg"
        texture_path = os.path.join(TEXTURES, texture_name)
        image = to_image(DESIGNS[tag_id]())
        image.save(texture_path, quality=QUALITY, optimize=True, subsampling=1)
        size = os.path.getsize(texture_path)
        total += size
        preview_path = os.path.join(TAGS, preview)
        tags.append(
            {
                "id": tag_id,
                "name": name,
                "accent": accent,
                "texture": f"assets/textures/{texture_name}",
                "preview": f"assets/tags/{preview}",
                "previewAvailable": os.path.exists(preview_path),
            }
        )
        print(f"  {texture_name:<24} {size / 1024:7.1f} KiB")

    manifest = {"version": 1, "generatedBy": "tool/generate_textures.py", "tags": tags}
    with open(OUT_MANIFEST, "w", encoding="utf-8", newline="\n") as handle:
        json.dump(manifest, handle, ensure_ascii=False, indent=2)
        handle.write("\n")

    print(f"Wrote {len(tags)} textures, {total / 1024 / 1024:.1f} MiB total")
    print(f"Wrote {OUT_MANIFEST}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
