# Third-party notices

NotchHub itself is MIT-licensed (see `LICENSE`). It includes the following
third-party code, which is compiled into the app.

## thinking-orbs

`Sources/NotchHubOrbs/OrbEngine.swift` is a hand port of the geometry engine in
**thinking-orbs 0.3.2** by Jakub Antalik (npm `thinking-orbs`,
https://github.com/Jakubantalik/Libraries.dev, `packages/thinking-orbs`), the
dotted thought-orb indicators NEO draws; `Sources/NotchHubOrbs/OrbView.swift`
is its canvas painter. The nine animations, their presets and tuning are
reproduced so NotchHub's orb is the same orb NEO shows. The golden frames under
`Tests/NotchHubOrbsTests/Goldens` were dumped from the library's own JS engine
(`scripts/orb_goldens.mjs`).

```
MIT License

Copyright (c) 2026 Jakub Antalik

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```
