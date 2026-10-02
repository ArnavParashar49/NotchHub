#!/usr/bin/env python3
"""Pixel pet art tool.

Art lives in art/pet/*.pet as text grids — one character per pixel, keys from
art/pet/palette.txt, '.' transparent:

    @frame sit
    ................
    ..k........k....
    ...

Extras (see art/pet/SPEC.md, "Looks and hats"):
    art/pet/looks.txt        colour looks: "@look NAME", then "KEY #RRGGBB" lines
                             overriding palette keys for the fox's pixels
    art/pet/hats.pet         hat frames named hat_<name>, drawn centred on the
                             pixel BOUNDARY x=8 with their row 15 as the row that
                             sits on the head
    art/pet/anchors/*.txt    where each pet frame wears a hat: "frame X Y" (X a
                             pixel boundary 0-16, Y the frame row the hat's row 15
                             lands on) or "frame none"

    art/pet/wear.pet         accessories (glasses, a scarf, ...): frames named
                             acc_<name> drawn exactly where the fox wears them on
                             `sit` (front view), and acc_<name>_side drawn where
                             it wears them on `run_1` (side view, facing left)
    art/pet/wear.txt         how each pet frame wears accessories, where it is
                             not simply "front view at the hat anchor":
                             "frame VIEW [X Y] [-face] [-neck] [-ears]"

Commands:
    validate [FILE.pet ...]  check frames (size, palette, duplicates)
    extras [--strict]        check looks, hats and anchors (--strict: every pet
                             frame must be anchored)
    sheet OUT.png [--scale N] [--cols N] [--look NAME] [--hat NAME|test]
          [--wear NAME] [--anchor X,Y] [--frames a,b,...] [FILE.pet ...]
                             render a labelled contact sheet on black (default 8x,
                             8 columns); --look recolours the fox, --hat puts a
                             hat on every anchored frame ("test": a placeholder;
                             --anchor puts it at X,Y on every frame instead);
                             --wear puts an accessory on every frame that wears it
    generate                 write Sources/NotchHubCore/PetArt.generated.swift
"""
import glob, os, re, struct, sys, zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ART = os.path.join(ROOT, "art", "pet")
OUT_SWIFT = os.path.join(ROOT, "Sources", "NotchHubCore", "PetArt.generated.swift")
WIDTH = HEIGHT = 16
HAT_PREFIX = "hat_"
HAT_HEADROOM = 8
WEAR_PREFIX = "acc_"
SIDE_SUFFIX = "_side"
# Accessory art is drawn where these frames wear it: (x boundary, y row) of
# their hat anchor. A frame's own wear anchor moves the art by the difference.
WEAR_REF = {"front": (7, 3), "side": (6, 3)}
WEAR_VIEWS = ("front", "side", "peek", "none")
# What part of the fox an accessory is worn on; a frame can hide a slot.
WEAR_SLOTS = ("face", "neck", "ears")
WEAR_SLOT_OF = {"glasses": "face", "sunglasses": "face", "scarf": "neck", "bowtie": "neck", "headphones": "ears"}

# A placeholder hat for authoring anchors before the real hats exist: a red
# brim (cols 6-9) under a yellow crown (cols 7-8), centred on the boundary x=8.
TEST_HAT = ["................"] * 13 + [".......YY.......", ".......YY.......", "......rrrr......"]


def load_palette():
    palette = {}
    with open(os.path.join(ART, "palette.txt")) as fh:
        for line in fh:
            m = re.match(r"^\s*(\S)\s+#([0-9A-Fa-f]{6})\b", line)
            if m:
                palette[m.group(1)] = m.group(2).upper()
    if "." in palette:
        raise SystemExit("palette: '.' is reserved for transparency")
    return palette


def load_frames(files=None):
    files = files or sorted(glob.glob(os.path.join(ART, "*.pet")))
    frames = []
    for path in files:
        name, rows, line_no = None, [], 0
        with open(path) as fh:
            for raw in fh:
                line_no += 1
                line = raw.rstrip("\n").rstrip()
                if not line or line.lstrip().startswith("#"):
                    continue
                if line.startswith("@frame"):
                    if name is not None:
                        frames.append((path, name, rows))
                    name, rows = line.split(None, 1)[1].strip(), []
                    continue
                if name is None:
                    raise SystemExit(f"{path}:{line_no}: pixels before any @frame")
                rows.append(line.strip())
        if name is not None:
            frames.append((path, name, rows))
    return frames


def validate(frames, palette):
    errors, seen = [], {}
    for path, name, rows in frames:
        where = f"{os.path.basename(path)}:{name}"
        if not re.fullmatch(r"[a-z0-9_]+", name):
            errors.append(f"{where}: name must be lowercase letters, digits, underscores")
        if name in seen:
            errors.append(f"{where}: duplicate of {seen[name]}")
        seen[name] = where
        if len(rows) != HEIGHT:
            errors.append(f"{where}: {len(rows)} rows, expected {HEIGHT}")
        for i, row in enumerate(rows):
            if len(row) != WIDTH:
                errors.append(f"{where}: row {i} has {len(row)} pixels, expected {WIDTH}")
            bad = sorted({c for c in row if c != "." and c not in palette})
            if bad:
                errors.append(f"{where}: row {i} uses unknown keys {bad}")
    return errors


# --- Extras: looks, hats, anchors --------------------------------------------

def load_looks(palette):
    """Look name -> {key: RRGGBB}. Returns (looks, errors)."""
    path = os.path.join(ART, "looks.txt")
    looks, errors, current = {}, [], None
    if not os.path.exists(path):
        return looks, errors
    with open(path) as fh:
        for line_no, raw in enumerate(fh, 1):
            line = raw.strip()
            if not line or line.startswith("#"):
                continue
            if line.startswith("@look"):
                parts = line.split()
                if len(parts) != 2 or not re.fullmatch(r"[a-z]+", parts[1]):
                    errors.append(f"looks.txt:{line_no}: expected '@look name' (lowercase letters)")
                    current = None
                    continue
                current = parts[1]
                if current in looks:
                    errors.append(f"looks.txt:{line_no}: duplicate look {current}")
                looks[current] = {}
                continue
            m = re.match(r"^(\S)\s+#([0-9A-Fa-f]{6})\b", line)
            if not m or current is None:
                errors.append(f"looks.txt:{line_no}: expected 'KEY #RRGGBB' inside a @look")
                continue
            if m.group(1) not in palette:
                errors.append(f"looks.txt:{line_no}: unknown palette key {m.group(1)!r}")
                continue
            looks[current][m.group(1)] = m.group(2).upper()
    return looks, errors


def load_anchors():
    """Frame name -> (x, y) or None. Returns (anchors, errors)."""
    anchors, errors, where = {}, [], {}
    for path in sorted(glob.glob(os.path.join(ART, "anchors", "*.txt"))):
        base = os.path.basename(path)
        with open(path) as fh:
            for line_no, raw in enumerate(fh, 1):
                line = raw.split("#", 1)[0].strip()
                if not line:
                    continue
                parts = line.split()
                loc = f"anchors/{base}:{line_no}"
                if len(parts) == 2 and parts[1] == "none":
                    value = None
                elif len(parts) == 3 and re.fullmatch(r"-?\d+", parts[1]) and re.fullmatch(r"-?\d+", parts[2]):
                    x, y = int(parts[1]), int(parts[2])
                    if not (0 <= x <= WIDTH and -HAT_HEADROOM <= y < HEIGHT):
                        errors.append(f"{loc}: anchor ({x},{y}) out of range (x 0-16, y -8..15)")
                        continue
                    value = (x, y)
                else:
                    errors.append(f"{loc}: expected 'frame X Y' or 'frame none'")
                    continue
                if parts[0] in anchors:
                    errors.append(f"{loc}: {parts[0]} already anchored in {where[parts[0]]}")
                anchors[parts[0]] = value
                where[parts[0]] = loc
    return anchors, errors


def load_wear():
    """Frame name -> (view, x, y, hidden slots) with x/y None for "the hat anchor". Returns (wear, errors)."""
    path = os.path.join(ART, "wear.txt")
    wear, errors = {}, []
    if not os.path.exists(path):
        return wear, errors
    with open(path) as fh:
        for line_no, raw in enumerate(fh, 1):
            line = raw.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            loc = f"wear.txt:{line_no}"
            if len(parts) < 2 or parts[1] not in WEAR_VIEWS:
                errors.append(f"{loc}: expected 'frame VIEW [X Y] [-slot ...]' with VIEW one of {', '.join(WEAR_VIEWS)}")
                continue
            rest, x, y = parts[2:], None, None
            if len(rest) >= 2 and re.fullmatch(r"-?\d+", rest[0]) and re.fullmatch(r"-?\d+", rest[1]):
                x, y, rest = int(rest[0]), int(rest[1]), rest[2:]
                if not (0 <= x <= WIDTH and -HAT_HEADROOM <= y < HEIGHT):
                    errors.append(f"{loc}: anchor ({x},{y}) out of range (x 0-16, y -8..15)")
                    continue
            hidden = set()
            for flag in rest:
                if flag.startswith("-") and flag[1:] in WEAR_SLOTS:
                    hidden.add(flag[1:])
                else:
                    errors.append(f"{loc}: unknown flag {flag!r} (expected -face, -neck or -ears)")
            if parts[0] in wear:
                errors.append(f"{loc}: {parts[0]} listed twice")
            wear[parts[0]] = (parts[1], x, y, hidden)
    return wear, errors


def resolve_wear(pet_names, anchors, wear):
    """Every pet frame -> (view, x, y, hidden slots) or None (wears nothing). Returns (resolved, errors).

    A frame not in wear.txt wears accessories in front view at its hat anchor;
    one without a hat anchor must be listed.
    """
    resolved, errors = {}, []
    for name in sorted(wear):
        if name not in pet_names:
            errors.append(f"wear.txt: unknown frame {name}")
    for name in pet_names:
        view, x, y, hidden = wear.get(name, ("front", None, None, set()))
        if view == "none":
            resolved[name] = None
            continue
        if x is None:
            anchor = anchors.get(name)
            if anchor is None:
                errors.append(f"wear: {name} has no hat anchor, so wear.txt must place it (or say 'none')")
                continue
            x, y = anchor
        resolved[name] = (view, x, y, hidden)
    return resolved, errors


def wear_pixels(frames_by_name, accessory, placement, mirrored_frame=False):
    """The pixels (x, y, key) of `accessory` on a frame with wear `placement`, clipped to the frame."""
    if placement is None:
        return []
    view, ax, ay, hidden = placement
    if WEAR_SLOT_OF.get(accessory) in hidden:
        return []
    art_name = WEAR_PREFIX + accessory + ("" if view == "front" else SIDE_SUFFIX)
    rows = frames_by_name.get(art_name)
    if rows is None:
        return []
    pixels = []
    for y, row in enumerate(rows[:HEIGHT]):
        for x, key in enumerate(row[:WIDTH]):
            if key == ".":
                continue
            if view == "peek":
                # The side art mirrored: the fox faces right, its anchor mirrored with it.
                px, py = (WIDTH - 1 - x) + ax - (WIDTH - WEAR_REF["side"][0]), y + ay - WEAR_REF["side"][1]
            else:
                rx, ry = WEAR_REF[view]
                px, py = x + ax - rx, y + ay - ry
            if 0 <= px < WIDTH and 0 <= py < HEIGHT:
                pixels.append((px, py, key))
    return pixels


def check_extras(frames, palette, strict=False):
    errors, warnings = [], []
    looks, look_errors = load_looks(palette)
    errors += look_errors
    anchors, anchor_errors = load_anchors()
    errors += anchor_errors
    names = {name for _, name, _ in frames}
    pet = sorted(n for n in names if not n.startswith(HAT_PREFIX) and not n.startswith(WEAR_PREFIX))
    hats = sorted(n[len(HAT_PREFIX):] for n in names if n.startswith(HAT_PREFIX))
    for name in sorted(anchors):
        if name not in names:
            errors.append(f"anchors: unknown frame {name}")
        elif name.startswith(HAT_PREFIX) or name.startswith(WEAR_PREFIX):
            errors.append(f"anchors: {name} is a hat or an accessory, not a pet frame")
    missing = [n for n in pet if n not in anchors]
    if missing:
        (errors if strict else warnings).append(f"anchors: {len(missing)} pet frames not anchored: {', '.join(missing)}")
    for _, name, rows in frames:
        if name.startswith(HAT_PREFIX) and len(rows) == HEIGHT:
            for x in range(WIDTH):
                pass
    return looks, anchors, hats, errors, warnings


def check_wear(frames, anchors):
    """Accessories and how every pet frame wears them. Returns (resolved, accessories, errors)."""
    names = {name for _, name, _ in frames}
    pet = sorted(n for n in names if not n.startswith(HAT_PREFIX) and not n.startswith(WEAR_PREFIX))
    wear, errors = load_wear()
    resolved, resolve_errors = resolve_wear(pet, anchors, wear)
    errors += resolve_errors
    art = sorted(n[len(WEAR_PREFIX):] for n in names if n.startswith(WEAR_PREFIX))
    accessories = [n for n in art if not n.endswith(SIDE_SUFFIX)]
    for name in accessories:
        if name not in WEAR_SLOT_OF:
            errors.append(f"wear.pet: {WEAR_PREFIX}{name} has no slot (add it to WEAR_SLOT_OF)")
        if name + SIDE_SUFFIX not in art:
            errors.append(f"wear.pet: {WEAR_PREFIX}{name} needs a side view, {WEAR_PREFIX}{name}{SIDE_SUFFIX}")
    for name in art:
        if name.endswith(SIDE_SUFFIX) and name[:-len(SIDE_SUFFIX)] not in accessories:
            errors.append(f"wear.pet: {WEAR_PREFIX}{name} has no front view")
    return resolved, accessories, errors


def hat_rows(frames, hat):
    if hat == "test":
        return TEST_HAT
    for _, name, rows in frames:
        if name == HAT_PREFIX + hat:
            return rows
    all_frames = load_frames()
    for _, name, rows in all_frames:
        if name == HAT_PREFIX + hat:
            return rows
    raise SystemExit(f"no hat named {hat!r} (expected a frame {HAT_PREFIX}{hat})")


# --- PNG ------------------------------------------------------------------

def write_png(path, width, height, pixels):
    """pixels: list of rows, each a list of (r, g, b) tuples."""
    raw = b"".join(b"\x00" + bytes(c for px in row for c in px) for row in pixels)
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    with open(path, "wb") as fh:
        fh.write(png)


FONT = {
    "a": "010101111101101", "b": "110101110101110", "c": "011100100100011", "d": "110101101101110",
    "e": "111100110100111", "f": "111100110100100", "g": "011100101101011", "h": "101101111101101",
    "i": "111010010010111", "j": "001001001101010", "k": "101101110101101", "l": "100100100100111",
    "m": "101111111101101", "n": "110101101101101", "o": "010101101101010", "p": "110101110100100",
    "q": "010101101011001", "r": "110101110101101", "s": "011100010001110", "t": "111010010010010",
    "u": "101101101101111", "v": "101101101101010", "w": "101101111111101", "x": "101101010101101",
    "y": "101101010010010", "z": "111001010100111", "0": "111101101101111", "1": "010110010010111",
    "2": "110001010100111", "3": "110001010001110", "4": "101101111001001", "5": "111100110001110",
    "6": "011100110101010", "7": "111001010010010", "8": "010101010101010", "9": "010101011001110",
    "_": "000000000000111", "-": "000000111000000",
}


def sheet(out, frames, palette, scale=8, cols=8, look=None, hat=None, anchors=None, hat_art=None, wear=None, wear_placements=None):
    tile = WIDTH * scale
    head = HAT_HEADROOM * scale if hat else 0
    all_rows = {name: rows for _, name, rows in load_frames()} if wear else {}
    label_h = 14
    gap = 6
    rows_n = (len(frames) + cols - 1) // cols
    W = cols * (tile + gap) + gap
    H = rows_n * (head + tile + label_h + gap) + gap
    bg = (18, 18, 20)
    img = [[bg for _ in range(W)] for _ in range(H)]
    fox = dict(palette)
    if look:
        fox.update(look)
    base_colors = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in palette.items()}
    fox_colors = {k: tuple(int(v[i:i + 2], 16) for i in (0, 2, 4)) for k, v in fox.items()}

    def plot(cx, cy, x, y, color):
        for dy in range(scale):
            for dx in range(scale):
                py, px = cy + y * scale + dy, cx + x * scale + dx
                if 0 <= py < H and 0 <= px < W:
                    img[py][px] = color

    for index, (path, name, rows) in enumerate(frames):
        cx = gap + (index % cols) * (tile + gap)
        cy = gap + (index // cols) * (head + tile + label_h + gap) + head
        for y in range(-HAT_HEADROOM if hat else 0, HEIGHT):
            for x in range(WIDTH):
                plot(cx, cy, x, y, (0, 0, 0))  # the island's black
        colors = base_colors if name.startswith(HAT_PREFIX) or name.startswith(WEAR_PREFIX) else fox_colors
        for y, row in enumerate(rows[:HEIGHT]):
            for x, key in enumerate(row[:WIDTH]):
                if key != "." and key in colors:
                    plot(cx, cy, x, y, colors[key])
        if wear and not name.startswith(HAT_PREFIX) and not name.startswith(WEAR_PREFIX):
            for px, py, key in wear_pixels(all_rows, wear, (wear_placements or {}).get(name)):
                if key in base_colors:
                    plot(cx, cy, px, py, base_colors[key])
        anchor = (anchors or {}).get(name) if hat else None
        if anchor and hat_art and not name.startswith(HAT_PREFIX) and not name.startswith(WEAR_PREFIX):
            ax, ay = anchor
            for hy, row in enumerate(hat_art[:HEIGHT]):
                for hx, key in enumerate(row[:WIDTH]):
                    if key != "." and key in base_colors:
                        px, py = ax - 8 + hx, ay - 15 + hy
                        if 0 <= px < WIDTH and -HAT_HEADROOM <= py < HEIGHT:
                            plot(cx, cy, px, py, base_colors[key])
        # label (3x5 font at 2x)
        lx, ly = cx, cy + tile + 3
        label = name if not hat or anchor or name.startswith(HAT_PREFIX) else name + "-"
        for ch in label[:21]:
            glyph = FONT.get(ch)
            if glyph:
                for gy in range(5):
                    for gx in range(3):
                        if glyph[gy * 3 + gx] == "1":
                            for s in range(2):
                                for t in range(2):
                                    py, px = ly + gy * 2 + s, lx + gx * 2 + t
                                    if py < H and px < W:
                                        img[py][px] = (200, 200, 205)
            lx += 8
    write_png(out, W, H, img)
    for index, (path, name, _) in enumerate(frames):
        mark = ""
        if hat and not name.startswith(HAT_PREFIX):
            a = (anchors or {}).get(name, "missing")
            mark = f" anchor={a}"
        print(f"[{index // cols},{index % cols}] {os.path.basename(path)}:{name}{mark}")


def generate(frames, palette, looks, anchors, wear_placements):
    lines = [
        "// Generated by scripts/pet_art.py from art/pet — do not edit by hand.",
        "// Edit the .pet files, then run: python3 scripts/pet_art.py generate",
        "",
        "public enum PetArt {",
        "    /// Palette key → 0xRRGGBB.",
        "    public static let palette: [Character: UInt32] = [",
    ]
    for key, value in sorted(palette.items()):
        lines.append(f'        "{key}": 0x{value},')
    lines += ["    ]", "", "    /// Frame name → rows (16×16, '.' transparent). Hats are the frames named hat_*.",
              "    public static let frames: [String: [String]] = ["]
    for _, name, rows in frames:
        lines.append(f'        "{name}": [')
        for row in rows:
            lines.append(f'            "{row}",')
        lines.append("        ],")
    lines += ["    ]", "", "    /// Look name → the palette keys it recolours.", "    public static let looks: [String: [Character: UInt32]] = ["]
    if not looks:
        lines[-1] = "    public static let looks: [String: [Character: UInt32]] = [:]"
    else:
        for name in sorted(looks):
            lines.append(f'        "{name}": [')
            for key, value in sorted(looks[name].items()):
                lines.append(f'            "{key}": 0x{value},')
            lines.append("        ],")
        lines.append("    ]")
    lines += ["", "    /// Frame name → where it wears a hat: [x boundary, y row]. Frames not listed wear none."]
    anchored = {k: v for k, v in anchors.items() if v is not None}
    if not anchored:
        lines.append("    public static let hatAnchors: [String: [Int]] = [:]")
    else:
        lines.append("    public static let hatAnchors: [String: [Int]] = [")
        for name in sorted(anchored):
            x, y = anchored[name]
            lines.append(f'        "{name}": [{x}, {y}],')
        lines.append("    ]")
    lines += ["", "    /// Frame name → how it wears accessories (the frames named acc_*): [view, x boundary, y row, hidden slots].",
              "    /// View 0: front (the art as drawn on `sit`), 1: side (as drawn on `run_1`), 2: peek (the side art mirrored).",
              "    /// Hidden slots: bit 0 face, bit 1 neck, bit 2 ears. Frames not listed wear none."]
    worn = {k: v for k, v in (wear_placements or {}).items() if v is not None}
    if not worn:
        lines.append("    public static let wearAnchors: [String: [Int]] = [:]")
    else:
        lines.append("    public static let wearAnchors: [String: [Int]] = [")
        for name in sorted(worn):
            view, x, y, hidden = worn[name]
            mask = sum(1 << WEAR_SLOTS.index(slot) for slot in hidden)
            lines.append(f'        "{name}": [{WEAR_VIEWS.index(view)}, {x}, {y}, {mask}],')
        lines.append("    ]")
    lines += ["}", ""]
    tmp = OUT_SWIFT + ".tmp"
    with open(tmp, "w") as fh:
        fh.write("\n".join(lines))
    os.replace(tmp, OUT_SWIFT)
    print(f"wrote {len(frames)} frames, {len(looks)} looks, {len(anchored)} hat anchors, {len(worn)} wear anchors to {os.path.relpath(OUT_SWIFT, ROOT)}")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(__doc__)
    palette = load_palette()
    command = sys.argv[1]
    if command == "validate":
        frames = load_frames(sys.argv[2:] or None)
        errors = validate(frames, palette)
        for e in errors:
            print("error:", e)
        print(f"{len(frames)} frames, {len(errors)} errors")
        sys.exit(1 if errors else 0)
    if command == "extras":
        frames = load_frames()
        errors = validate(frames, palette)
        looks, anchors, hats, extra_errors, warnings = check_extras(frames, palette, strict="--strict" in sys.argv)
        errors += extra_errors
        wear_placements, accessories, wear_errors = check_wear(frames, anchors)
        errors += wear_errors
        for w in warnings:
            print("warning:", w)
        for e in errors:
            print("error:", e)
        anchored = sum(1 for v in anchors.values() if v is not None)
        wearing = sum(1 for v in wear_placements.values() if v is not None)
        print(f"{len(looks)} looks ({', '.join(sorted(looks)) or '-'}), {len(hats)} hats ({', '.join(hats) or '-'}), "
              f"{len(anchors)} frames in anchors ({anchored} wear hats), "
              f"{len(accessories)} accessories ({', '.join(accessories) or '-'}; {wearing} frames wear them), {len(errors)} errors")
        sys.exit(1 if errors else 0)
    if command == "sheet":
        args, scale, cols, look_name, hat, only, fixed, wear = sys.argv[3:], 8, 8, None, None, None, None, None
        while args and args[0] in ("--scale", "--cols", "--look", "--hat", "--frames", "--anchor", "--wear"):
            flag, value, args = args[0], args[1], args[2:]
            if flag == "--scale":
                scale = int(value)
            elif flag == "--cols":
                cols = int(value)
            elif flag == "--look":
                look_name = value
            elif flag == "--hat":
                hat = value
            elif flag == "--wear":
                wear = value
            elif flag == "--anchor":
                fixed = tuple(int(v) for v in value.split(","))
            else:
                only = value.split(",")
        frames = load_frames(args or None)
        errors = validate(frames, palette)
        if only:
            by_name = {name: (path, name, rows) for path, name, rows in load_frames()}
            by_name.update({name: (path, name, rows) for path, name, rows in frames})
            missing = [n for n in only if n not in by_name]
            if missing:
                raise SystemExit(f"unknown frames: {', '.join(missing)}")
            frames = [by_name[n] for n in only]
        look = None
        if look_name and look_name != "fox":
            looks, look_errors = load_looks(palette)
            errors += look_errors
            if look_name not in looks:
                raise SystemExit(f"no look named {look_name!r} in art/pet/looks.txt")
            look = looks[look_name]
        anchors, hat_art = None, None
        if hat:
            anchors, anchor_errors = load_anchors()
            errors += anchor_errors
            if fixed:
                anchors = {name: fixed for _, name, _ in frames}
            hat_art = hat_rows(frames, hat)
        wear_placements = None
        if wear:
            hat_anchors, anchor_errors = load_anchors()
            wear_placements, _, wear_errors = check_wear(load_frames(), hat_anchors)
            errors += anchor_errors + wear_errors
        for e in errors:
            print("error:", e)
        sheet(sys.argv[2], frames, palette, scale=scale, cols=cols, look=look, hat=hat, anchors=anchors, hat_art=hat_art,
              wear=wear, wear_placements=wear_placements)
        sys.exit(1 if errors else 0)
    if command == "generate":
        frames = load_frames()
        errors = validate(frames, palette)
        looks, anchors, hats, extra_errors, warnings = check_extras(frames, palette)
        errors += extra_errors
        wear_placements, _, wear_errors = check_wear(frames, anchors)
        errors += wear_errors
        for w in warnings:
            print("warning:", w)
        if errors:
            for e in errors:
                print("error:", e)
            sys.exit(1)
        generate(frames, palette, looks, anchors, wear_placements)
        return
    raise SystemExit(__doc__)


if __name__ == "__main__":
    main()
