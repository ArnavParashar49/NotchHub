#!/usr/bin/env node
// Dumps golden frames from the thinking-orbs JS engine, for the Swift port's
// tests (Tests/NotchHubOrbsTests). Pure functions only: no canvas, no DOM.
//
//   node scripts/orb_goldens.mjs [path/to/thinking-orbs/dist/engine.es.js]
//
// Without a path it uses ./node_modules/thinking-orbs/dist/engine.es.js, from
// the current folder (e.g. after `npm install --no-save thinking-orbs@0.3.2`).
//
// Writes Tests/NotchHubOrbsTests/Goldens/thinking-orbs.json. Re-run only when
// the upstream engine changes; the Swift test compares every dot and line of
// every frame here to the port's output within 1e-3.
import { readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const enginePath = resolve(
  process.argv[2] ?? "node_modules/thinking-orbs/dist/engine.es.js"
);
const pkg = JSON.parse(readFileSync(resolve(dirname(enginePath), "..", "package.json"), "utf8"));
const { MODE_FRAMES, STATE_TO_MODE, resolvePreset } = await import(pathToFileURL(enginePath).href);

const STATES = Object.keys(STATE_TO_MODE);
// (size preset, t) pairs: t is the engine's own time (already × speed). The
// times straddle the morph cycle's hold and morph phases and a rubik move.
const SAMPLES = [
  [64, 0],
  [64, 1.37],
  [64, 4.21],
  [32, 2.5],
  [20, 0.77],
];
const round = (v) => Number(v.toFixed(5));

const frames = [];
for (const state of STATES) {
  for (const [size, t] of SAMPLES) {
    const { mode, speed, opts } = resolvePreset(state, size);
    const frame = MODE_FRAMES[mode](size, t, opts);
    frames.push({
      state,
      size,
      t,
      mode,
      speed,
      opts,
      dots: frame.dots.map((d) => [d.x, d.y, d.z, d.r, d.white, d.a ?? 1].map(round)),
      lines: frame.lines.map((l) => [l.x1, l.y1, l.x2, l.y2, l.white, l.a ?? 1, l.w].map(round)),
    });
  }
}

const out = resolve(here, "..", "Tests", "NotchHubOrbsTests", "Goldens", "thinking-orbs.json");
mkdirSync(dirname(out), { recursive: true });
writeFileSync(out, JSON.stringify({ library: pkg.name, version: pkg.version, frames }));
console.log(`${frames.length} frames from ${pkg.name}@${pkg.version} → ${out}`);
