# Current Color

What color is it now. A clock whose background color is derived from the time.

Live: https://zero3kw.github.io/CurrentColor/

The page is plain HTML, CSS and JavaScript in `docs/` (served by GitHub Pages);
there is no build step. To view it locally, serve the folder, for example:

```
python3 -m http.server 8000 -d docs
```

## Keys

The three modes are named after jo-ha-kyū (序破急), the slow opening,
development and rapid climax of traditional Japanese performing arts.

| Key        | Mode     | Action                                                    |
| ---------- | -------- | --------------------------------------------------------- |
| 1 / Q      | 序 Jo    | Hue wheel in 6 minutes, one degree per second (default)   |
| 2 / W      | 破 Ha    | Hue wheel in 1 minute, continuous                         |
| 3 / E      | 急 Kyū   | Random color every second, up to the edge of Display P3   |
| G          |          | Gradient / single color                                   |
| H          |          | Show or hide the hue wheel                                |

## Design

- Background in OKLCH with fixed lightness and chroma, so every hue looks
  equally bright. The browser paints OKLCH directly, which keeps more
  precision than 8-bit sRGB on wide-gamut displays (e.g. Safari on a P3
  display).
- Text in the same hue at a 3:1 WCAG contrast ratio.
- Sizes on a golden-ratio scale from the height of the colored area, which
  is letterboxed to 2.39:1.
- Typeface: [Shippori Mincho](https://github.com/fontdasu/ShipporiMincho)
  (SIL Open Font License 1.1, see `docs/fonts/ShipporiMincho-OFL.txt`).
