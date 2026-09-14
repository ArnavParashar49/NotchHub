# Pixel Pet — art spec

The pet is a tiny pixel-art fox that lives in the MacBook notch. It is drawn
at **1 point per art pixel** (16×16 pt, 32×32 device pixels on Retina) in the
notch bar, and at 2 points per art pixel in the expanded island. It sits on a
**pure black** background (the island). It is a premium macOS companion, not a
game mascot: calm, charming, restrained.

## Format

- Files: `art/pet/<group>.pet`. Each frame is `@frame <name>` followed by
  exactly **16 rows of exactly 16 characters**. `#` lines are comments.
- One character per pixel. `.` is transparent (shows the black island). Every
  other character must be a key from `art/pet/palette.txt`. Do not add keys.
- Frame names are **fixed by this spec** (the engine refers to them). Do not
  rename, skip, or add frames beyond the list for your file.
- Tools (run from the repo root):
  - `python3 scripts/pet_art.py validate art/pet/<group>.pet`
  - `python3 scripts/pet_art.py sheet <out.png> --scale 12 --cols 4 art/pet/base.pet art/pet/<group>.pet`
    (view the PNG to check your work — compare against the base frames)
  - `python3 scripts/pet_art.py sheet <out.png> --scale 2 --cols 8 art/pet/<group>.pet`
    (TRUE SIZE on Retina: the pose must still read at this size)

## The character (keep it identical across every frame)

Start every frame from `art/pet/base.pet` `sit` and change only what the pose
needs. Same head shape, ear shape, eye style (1×2 dark `e` pixels), cream
cheeks/muzzle/chest, dark nose, orange body, cream paws, curled tail with a
cream tip. Same size: the fox never grows or shrinks between frames.

- Head rows 0–8, ears rows 0–3, eyes rows 5–6 at cols 4 and 9, nose row 7
  cols 6–7, body rows 9–15, tail cols 11–15.
- `k` is the outline. On black it reads as the silhouette edge; still draw it,
  consistently, around the whole fox and around props.
- Shade with `O` on the lower/left body, highlight with `y` sparingly on the top
  of the head. `W` shades cream. No gradients, no dithering noise.
- The ground line is row 15: feet touch it in resting poses. A jump lifts the
  whole fox (2–3 rows) — do not stretch it.

## Pixel-art rules

- Crisp, deliberate pixels. No anti-aliasing pixels, no stray single pixels that
  do not serve the shape, no "noise".
- Props are small and iconic (2–7 px): headphones, a laptop, a clock, a package,
  a magnifier, a cable. They must not hide the face. Outline props with `k`.
- Motion between frames of one animation should be 1–2 px: head bob, paw
  move, tail flick. Keep every non-moving pixel identical between those frames
  so the animation does not shimmer.
- Effects (zzz, hearts, `!`, sparkles, confetti) use `z`, `r`, `Y`, `t`, `b` and
  stay inside the 16×16 canvas, usually in the top-right corner (rows 0–4,
  cols 11–15) where the head leaves room. Keep them to a few pixels.
- Readability at true size matters more than detail. Check the `--scale 2`
  sheet: if a prop or expression does not read, simplify it.

## Frames by file

Frame lists are exact. Descriptions are guidance.

### `idle.pet` — calm idle life
- `sit_tail_1`, `sit_tail_2` — tail wag: the tail flicks out/down by 1–2 px, then
  further; everything else identical to `sit`.
- `yawn_1`, `yawn_2` — eyes closed (1 px `k` lines), mouth opening (`p` tongue
  shows on `yawn_2`), head tilted up 1 px.
- `stretch_1`, `stretch_2` — front paws forward and low, rear up (a play-bow);
  `stretch_2` more extended. Eyes closed.
- `sleep_1`, `sleep_2` — curled up lying down, eyes closed, tail wrapped around
  the front; `sleep_2` body 1 px lower (breathing). Lower profile than sitting.
- `sleep_zzz` — `sleep_1` with a small `z` "z" in the top-right.
- `wake` — sitting, sleepy half-closed eyes (eye row 5 as `k`, row 6 as `e`).

### `react.pet` — noticing the user
- `alert` — standing a little taller (ears perked, body 1 px up), eyes open.
- `curious` — head tilted to the viewer's left (ears asymmetric by 1 px).
- `wave_1`, `wave_2` — one front paw raised beside the head; `wave_2` paw 1 px
  further out. Happy eyes.
- `jump_crouch` — squashed 1 row lower, legs bent.
- `jump_air` — whole fox 3 rows up, paws tucked, tail out.
- `happy` — `^ ^` eyes (upturned 3-px arcs in `k`), small `p` mouth.
- `heart` — `happy` with a tiny `r` heart (5–6 px) top-right.

### `music.pet` — vibing (the fox wears headphones in all of these)
- Headphones: a `g` band over the head between the ears, `G`/`d` ear cups on
  the sides of the head at rows 4–6. Same headphones in every music frame.
- `music_1` — head bob left 1 px, eyes closed happy.
- `music_2` — head centered, eyes closed.
- `music_3` — head bob right 1 px, eyes closed happy.
- `music_4` — head centered, eyes open, tail flick.
- `music_excited` — eyes wide, a `z`/`Y` sparkle top-right (new song).

### `meeting.pet` — in a call
- Headset: the same headphones as music plus a small `G` boom mic curving to
  the mouth.
- `meet_talk_1`, `meet_talk_2` — headset; mouth closed / open (`p`).
- `meet_listen` — headset, calm eyes, ears slightly back.
- `meet_muted` — headset; a tiny mic icon top-right with an `r` slash.
- `meet_camera_off` — headset; a tiny `G` camera icon top-right with an `r`
  slash.
- `meet_type_1`, `meet_type_2` — headset, sitting behind a tiny laptop (see
  coding) with paws on it; paws alternate.

### `coding.pet` — working alongside the user
- Laptop: a small `g`/`G` open laptop in front of the body (rows 10–15), screen
  facing the fox, a hint of `b` glow on the chest/face. Same laptop in every
  frame that has it.
- `code_type_1`, `code_type_2`, `code_type_3` — typing: paws on the keyboard,
  alternating 1 px; eyes on the screen (looking down 1 px).
- `code_think_1`, `code_think_2` — no laptop; one paw to the chin, eyes looking
  up; `…` as three `z` pixels top-right, the dots appearing one/two at a time.
- `code_search_1`, `code_search_2` — holding a tiny magnifier (`g` ring, `b`
  lens) at head height, moved 1–2 px between frames.
- `code_run` — sitting beside a tiny `d` terminal window with a `t` prompt
  cursor, looking at it.
- `code_alert` — looking straight at the viewer, ears up, a small `r` `!`
  top-right (approval needed).
- `code_done` — paws up, happy eyes, a small `t` check mark top-right.

### `status.pet` — timer, download, battery
- `timer_1`, `timer_2` — holding a tiny round clock (`g` rim, `z` face, `k`
  hands) in front of the chest; hand moves between frames.
- `timer_alert` — clock raised, eyes wide.
- `timer_done` — small jump with the clock, `Y` sparkle.
- `download_1`, `download_2` — carrying a tiny `n`/`N` package on the head,
  walking (paws alternate).
- `download_done` — package set down beside the fox, happy eyes, `Y` sparkle.
- `charge_1`, `charge_2` — sitting beside a tiny `g` plug and cable; a `Y` bolt
  above it that blinks (visible on `charge_1`, dim `G` on `charge_2`).
- `low_battery_1`, `low_battery_2` — worried eyes (eyebrows as `k` slants), a
  `b` sweat drop that slides down 1 px.
- `full_charge` — happy eyes, `Y` bolt top-right.

### `events.pet` — brief acknowledgements
- `notify` — surprised: eyes wide (2×2), ears up, `Y` `!` top-right.
- `headphones_on` — wearing the music headphones, eyes open, tail flick.
- `headphones_off` — holding the headphones below the chin, eyes open.
- `mic_on` — a tiny `G` microphone beside the fox, ears up.
- `camera_on` — holding a tiny `d` camera with a `b` lens.
- `record_point` — one paw pointing to the viewer's left, a small `r` dot at
  the end.
- `celebrate_1`, `celebrate_2`, `celebrate_3` — a joyful hop (0, 2, 1 rows up)
  with a few confetti pixels (`Y`, `t`, `r`, `b`) changing position.

### Mischief frames

The engine can draw any frame mirrored (a name ending in `~`) and moves the
sprite in whole points per frame, so these are drawn IN PLACE and in one
facing only.

`mischief_move.pet` — side view (profile), every frame facing LEFT (head left,
tail streaming right), body centred around cols 7–8 in every frame:
- `run_1`–`run_4` — a 4-frame dash cycle: extended, gathered (1 px higher),
  extended with legs swapped, gathered.
- `skid` — braking: weight back, front legs planted forward, `W` dust puff at
  the front paws.
- `sneak_1`, `sneak_2` — low tiptoe creep with a mischievous brow; front paw
  lifted, then hind paw.
- `wiggle_1`, `wiggle_2` — pre-pounce crouch, rump up; only rump and tail move
  1 px.
- `pounce` — the leap, stretched diagonally, off the ground.

`mischief_hide.pet` — hide-and-seek behind the notch. For the peeks the notch
covers columns 0–7 COMPLETELY: those columns stay `.`, only columns 8–15 are
ever seen, and no outline runs down col 8 (the fox continues behind the notch):
- `peek_1`, `peek_2` — the head leaning out past the edge, one eye looking out;
  `peek_2` glances up with an ear twitch.
- `peek_grin` — the same with a `^` squint and a `p` tongue.
- `tail_peek_1`, `tail_peek_2` — only the bushy tail pokes out, wagging.
- `pop` — front view, the whole fox: the "boo!" of popping out, paws up.

`mischief_face.pet` — cheeky expressions, copies of `sit` changed only where
the expression needs: `blep_1` (wink + tongue), `blep_2` (`> <` grin + longer
tongue), `snicker_1`/`snicker_2` (giggling behind a paw, bobbing 1 px),
`caught` (busted: wide eyes, paws together, `Y` `!`), `pant_1`/`pant_2`
(tongue out after zoomies, breathing 1 px).

### Looks and hats

Tools: `python3 scripts/pet_art.py extras` checks looks, hats and anchors;
`sheet OUT.png --look NAME` recolours the fox; `sheet OUT.png --hat NAME`
(or `--hat test`, a placeholder cap) puts a hat on every anchored frame, with
8 rows of headroom above each tile. `--frames a,b,c` limits a sheet to frames.

- **Looks** (`art/pet/looks.txt`): `@look name`, then `KEY #RRGGBB` lines that
  recolour the FOX's palette keys (fur `o` `O` `y`; the outline `k`, cream `w` `W`
  or eyes `e` only if the look needs it). Props and effects keep their colours,
  because they use other keys. The base palette is the look `fox`. Every look
  must read on pure black at true size: silhouette, cream chest and tail tip
  distinct from the fur, dark eyes, and the shade still reading as shade.
- **Hats** (`art/pet/hats.pet`, frames `hat_<name>`): drawn centred on the pixel
  BOUNDARY x = 8 (symmetric across columns 7|8), with the hat's bottom row on
  row 15 — the row that sits on the head — and everything else above it. At most
  10 px wide and 8 px tall. `k` outline, palette keys only; each must read at true
  size, on black and on the fox's head.
- **Anchors** (`art/pet/anchors/<file>.txt`, one per `.pet` file): `frame X Y`,
  where X is the pixel boundary the hat centres on (the middle of the head,
  between the ears) and Y is the frame row the hat's row 15 covers (normally
  the head's top outline between the ears, so the hat sits snugly without
  hiding the ear tips). Write `frame none` where no hat fits (the head is
  hidden, as in `tail_peek_1`). The engine mirrors anchors with the frame,
  moves the hat with the frame's offset, draws it over the fox, and never
  recolours it with a look.

- **Holiday hats** (`art/pet/holiday_hats.pet`, same convention): `hat_hearts`
  (Valentine's heart bopper), `hat_shamrock` (St. Patrick's green top hat),
  `hat_bunny` (Easter ears), `hat_turkey` (Thanksgiving feather fan),
  `hat_lunar` (Lunar New Year red-and-gold cap), `hat_marigold` (Diwali and Día
  de Muertos marigold crown).

### `touch.pet` — stroking the big pet in its panel
- `lean_left`, `lean_right` — from `happy`: the head and shoulders lean 1 px
  toward the viewer's left / right into a stroking hand (ears tilted with the
  head), eyes closed happy `^ ^`, `p` blush; the feet and the base of the tail
  stay put. Each is the other mirrored.

### `interaction.pet` — when the user clicks the pet
- `hi_wave` — waving (like `wave_2`) with happy eyes and `p` blush.
- `pet_1`, `pet_2` — eyes closed blissful, `p` blush; ears pressed back on
  `pet_2` as if being patted.
- `eat_1`, `eat_2` — head down over a tiny `n` bowl in front, `W` food; head
  dips 1 px between frames.
- `play_1`, `play_2` — batting a tiny `r` ball; ball moves 2 px between frames.
