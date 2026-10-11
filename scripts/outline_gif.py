#!/usr/bin/env python3
"""Turn a folder of NEO wake-outline frames into an animated GIF (Pillow).

    python3 scripts/outline_gif.py FRAMEDIR [-o OUT.gif] [--fps 30] [--margin 40]
                                   [--max-mb 6] [--hold 0.4] [--speed 1] [--no-resample]

FRAMEDIR is a frame folder written by `NotchHub --neo-outline-frames` or
`--neo-outline-morph` (e.g. shots/neo-outline/current/wings/grey/episode): its
NNN.png files plus the frames.json beside them, which gives each frame's time
`t`, the render scale and the island's rect in pixels.

- Playback is REAL TIME at --fps (30): every output tick shows the frame that
  is current at that moment, so a 48-frame loop of a 3.6 s cycle plays at its
  true speed (each frame held as long as it lasts) rather than sped up. With
  --no-resample each frame is shown once for 1/fps instead.
- The island is cropped tight with --margin points (40) around it, from the
  top of the screen; without a frames.json the frames are used whole.
- One palette is built from frames across the whole sequence and applied to
  every frame without dithering, so colours never flicker between frames.
- If the GIF is over --max-mb (6 MB) it is scaled down until it fits.

Default output: the folder's name with .gif, beside it
(e.g. .../wings/grey/episode → .../wings/grey/episode.gif).
"""
from __future__ import annotations

import argparse
import io
import json
import sys
from pathlib import Path

from PIL import Image


def load(folder: Path) -> tuple[list[Path], list[float] | None, dict]:
    meta: dict = {}
    times: list[float] | None = None
    manifest = folder / "frames.json"
    if manifest.exists():
        meta = json.loads(manifest.read_text())
        entries = meta.get("frames", [])
        files = [folder / e["file"] for e in entries]
        times = [float(e.get("t", i)) for i, e in enumerate(entries)]
    else:
        files = sorted(folder.glob("*.png"))
    if not files:
        sys.exit(f"no frames in {folder}")
    return files, times, meta


def crop_box(size: tuple[int, int], meta: dict, margin_pt: float) -> tuple[int, int, int, int]:
    width, height = size
    island = meta.get("island_px")
    if not island:
        return (0, 0, width, height)
    scale = float(meta.get("scale", 2))
    m = margin_pt * scale
    x, y, w, h = island
    flare = 6 * scale  # the island's top flares reach this far beyond its rect
    left = max(0, int(x - flare - m))
    right = min(width, int(x + w + flare + m + 0.999))
    bottom = min(height, int(y + h + m + 0.999))
    return (left, 0, right, bottom)


def schedule(times: list[float] | None, count: int, meta: dict, fps: float, speed: float,
             resample: bool, hold: float) -> list[tuple[int, int]]:
    """(frame index, duration in ms) pairs at real time, GIF delays being whole centiseconds."""
    if not resample or times is None:
        ticks = [(i, 1.0 / fps) for i in range(count)]
    else:
        loops = bool(meta.get("loops"))
        if count > 1:
            step = (times[-1] - times[0]) / (count - 1)
        else:
            step = 1.0 / fps
        end = times[-1] + (step if loops else 1.0 / fps)
        ticks = []
        n = 0
        while True:
            at = times[0] + n * speed / fps
            if at >= end - 1e-9:
                break
            index = max(i for i, t in enumerate(times) if t <= at + 1e-9)
            ticks.append((index, 1.0 / fps))
            n += 1
    if hold > 0 and ticks:
        index, d = ticks[-1]
        ticks[-1] = (index, d + hold)
    # Whole centiseconds that add up to real time (30 fps alternates 30/30/40 ms).
    out: list[tuple[int, int]] = []
    clock = 0.0
    shown = 0
    for index, d in ticks:
        clock += d
        cs = round(clock * 100) - shown
        shown += cs
        out.append((index, max(2, cs) * 10))
    return out


def build(files: list[Path], box, plan, scale: float) -> bytes:
    used = sorted({i for i, _ in plan})
    frames: dict[int, Image.Image] = {}
    for i in used:
        image = Image.open(files[i]).convert("RGB").crop(box)
        if scale != 1:
            image = image.resize((max(1, round(image.width * scale)), max(1, round(image.height * scale))), Image.LANCZOS)
        frames[i] = image
    # One palette for the whole sequence, from up to 16 frames across it.
    picks = [used[round(k * (len(used) - 1) / 15)] for k in range(min(16, len(used)))] if len(used) > 1 else used
    first = frames[used[0]]
    montage = Image.new("RGB", (first.width, first.height * len(picks)))
    for row, i in enumerate(picks):
        montage.paste(frames[i], (0, row * first.height))
    palette = montage.quantize(colors=255, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE)
    indexed = {i: f.quantize(palette=palette, dither=Image.Dither.NONE) for i, f in frames.items()}
    sequence = [indexed[i] for i, _ in plan]
    durations = [d for _, d in plan]
    buffer = io.BytesIO()
    sequence[0].save(buffer, format="GIF", save_all=True, append_images=sequence[1:], duration=durations,
                     loop=0, disposal=1, optimize=False)
    return buffer.getvalue()


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("folder", type=Path)
    parser.add_argument("-o", "--out", type=Path)
    parser.add_argument("--fps", type=float, default=30)
    parser.add_argument("--margin", type=float, default=40, help="points around the island (default 40)")
    parser.add_argument("--max-mb", type=float, default=6)
    parser.add_argument("--hold", type=float, default=None,
                        help="seconds to hold the last frame (default 0 for a loop, 0.4 otherwise)")
    parser.add_argument("--speed", type=float, default=1, help="playback speed (0.25 = four times slower)")
    parser.add_argument("--no-resample", action="store_true", help="show each frame once for 1/fps")
    args = parser.parse_args()

    folder = args.folder.resolve()
    files, times, meta = load(folder)
    with Image.open(files[0]) as probe:
        size = probe.size
    box = crop_box(size, meta, args.margin)
    hold = args.hold if args.hold is not None else (0 if meta.get("loops") else 0.4)
    plan = schedule(times, len(files), meta, args.fps, args.speed, not args.no_resample, hold)
    out = args.out or folder.with_suffix(".gif")

    limit = args.max_mb * 1024 * 1024
    scale = 1.0
    while True:
        data = build(files, box, plan, scale)
        if len(data) <= limit or scale < 0.3:
            break
        scale *= 0.85
    out.write_bytes(data)
    seconds = sum(d for _, d in plan) / 1000
    print(f"{out}: {len(plan)} ticks from {len(set(i for i, _ in plan))} frames, {seconds:.2f} s at {args.fps:g} fps"
          f"{'' if args.speed == 1 else f' (speed {args.speed:g})'}, crop {box[2] - box[0]}×{box[3] - box[1]} px"
          f"{'' if scale == 1 else f' scaled {scale:.2f}'}, {len(data) / 1024 / 1024:.2f} MB")
    if len(data) > limit:
        print(f"warning: still over {args.max_mb} MB", file=sys.stderr)


if __name__ == "__main__":
    main()
