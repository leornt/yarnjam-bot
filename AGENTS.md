# Yarn Jam bot

Swift helper for the browser puzzle. It reads the screen, moves the pointer, and clicks one yarn. It does not play on its own.

This file is the project documentation. When behavior, controls, or vision rules change, update this file in the same change.

## Game

The board is the portrait game view in the browser. Find it on screen; do not assume it fills the display.

- The wooden tray at the top holds four couches. Only two are playable. The others stay locked (pale, with a plus) until the game opens them.
- Each playable couch has one color and three slots. A couch is finished when it holds three yarns of its color.
- Under the couches are five buffer pegs. A yarn whose color does not match an open couch can sit there. Buffer yarns are only for backtracking blockers. Filling all five loses the level, so the bot always reserves one empty peg.
- The dark field in the center is the puzzle. Each yarn is a colored rope with a round end and an arrow end.
- A yarn is free when nothing blocks the arrow's way to the edge of the dark field. Only free yarns are targets.

## Controls

The process starts and waits. Nothing is captured until `1` is pressed.

| Key | Action |
| --- | --- |
| `1` | Capture the screen, analyze it, move the pointer to the first safe yarn, and click it. |

One press is one click. Press `1` again after the board settles. `2` and `3` are not bound.

Order of targets:

1. Choose one active couch: the playable, incomplete couch with the most filled slots; use the leftmost on a tie.
2. Offer only free yarns matching that couch until it reaches 3/3.
3. If no matching yarn is free, follow the blocking chains in front of that couch's yarns. A free blocker whose color fits the other open couch is clicked first, because it goes to that couch and uses no buffer peg.
4. If the chains have no such blocker, any free yarn that fits the other open couch comes next. Parking a wrong color is the last resort.
5. Only then are free blockers with no couch color offered for the buffer.

The bot does not click an unrelated free yarn into the buffer, and it clicks no buffer target when four of five pegs are occupied. Extra free yarns stay visible as green arrows in the debug image. Blocked yarns are not targets. Only the first target is clicked.

## What this version does not do

- No drags, and no keystrokes sent to the game.
- No timer, no loop, no unattended play. Each click waits for another press of `1`.
- `1` is observed, not swallowed. The focused app still receives it.

## Run

From this directory:

```sh
swift run YarnJamBot
```

Check a still image (no hotkeys, no pointer move):

```sh
swift run YarnJamBot --image path/to/screen.jpg
```

Each `1` (and `--image`) writes `debug/last-analysis.png`: field, couches, rim box (pink), slots (green filled, red empty), pegs, arrows, and numbered target dots. Colors are reported as hex values read from the screen. `--image` does not move the pointer or click.

Each `1` also saves `debug/last-capture.png` (or one file per display) with exactly what was captured, before anything is drawn on it. Reproduce a bad move with `--image debug/last-capture.png`; the overlay image is not a clean input. Set `YARNJAM_DEBUG=1` to list every yarn with its color, hue, state, arrow, and blockers.

## Permissions

Live mode needs two macOS permissions for the app that launches the binary (Terminal or Cursor) and, if prompted, for the `YarnJamBot` binary itself:

- Screen Recording, so captures are not empty.
- Accessibility, so the global key tap, pointer move, and click are allowed.

The process prints both checks at startup. If a capture or the key tap fails, grant the permission and start it again. `swift run` rebuilds into `.build/debug/YarnJamBot`; after a clean rebuild, macOS may ask again.

## Layout of the code

- `Sources/YarnJamBot/main.swift` — startup, keys, session.
- `Sources/YarnJamBot/Input.swift` — global key tap and pointer move.
- `Sources/YarnJamBot/Capture.swift` — display screenshots, or one image file.
- `Sources/YarnJamBot/Bitmap.swift` — pixels, color, drawing buffer.
- `Sources/YarnJamBot/Analyzer.swift` — find the board, couches, pegs, yarns.
- `Sources/YarnJamBot/Overlay.swift` — `debug/last-analysis.png`.
- `Sources/YarnJamBot/Models.swift` — board types.

Yarn components are independent after the field has been segmented. Their skeletons, arrowheads, and forward corridors are analyzed concurrently on the system's global dispatch pool, so this CPU-heavy stage can use multiple cores. Results are sorted back into screen order before target selection.

## How a yarn is read

Thresholds follow the board size (peg radius and field size), so a window and a full-screen capture use the same rules. If the pegs are smaller than a 16 px radius, the capture is enlarged with smooth interpolation until they reach it, and the board is found again. On a small board a rope is about 7 px wide, and its arrowhead is only a pixel or two wider.

1. The tray is a beige region on the dark navy field. It does not have to span the display. Five round white pegs sit in a row just under it.
2. Couch bays are the gaps between the dark wooden posts. If the posts are unclear, the tray is split into four equal bays.
3. No yarn or couch color is fixed in code. Each couch color is read from its rim on screen. The rim is the largest one-hue region in the bay that is at least half the bay wide and a third of it tall. Full-height columns (the tray's wooden bars) are cleared first, so an orange or yellow couch is still found. A dusty rim such as pink (saturation about 0.25) counts too. A white rim has no usable hue: it is the bright, nearly gray region (saturation under 0.10, value over 0.80). White is used only when the bay has no colored rim and no green plus, so a locked cream couch stays locked. The handle on top and the plus do not count.
4. The rim box comes from the rim's sides and bottom; its height is 0.947 of its width, because the handle can merge into the top. Three slots sit at fixed fractions of that box: top-left, top-right, bottom-center. A slot is filled when more than 20% of a small circle there matches the couch hue (a ball of that color). An empty slot shows a pale peg. Measured share: about 0.5 when filled, 0.0 when empty.
5. A buffer peg is occupied when its center is saturated instead of white.
6. Field pixels far from the navy background are rope. A rope is one connected region of similar hue. Low-saturation ropes (white, gray) stay separate from saturated ones. One-pixel holes and notches in a rope are closed, because pale ropes (salmon) have texture pixels below the saturation cut.
7. The centerline comes from Zhang-Suen thinning. Its two ends are the ends of the longest path, so a short spur is not an end.
8. Yarns only move forward, toward the arrow, so the arrow end must be right. Each end is measured by walking a straight line out through it and recording the rope's cross width at each step. The line runs along the board's horizontal or vertical axis, since every rope leg on the board is straight. The centerline can end in one barb of the arrowhead, so three distances back along the centerline are tried, and the axis with the longest straight run wins. The flare is the widest cross width near the end, divided by the rope's median width. The arrow end has a flare of at least 1.3, and at least 0.15 more than the other end. A pale head is only slightly wider, so a flare of 1.15 is enough when that end is at least 0.30 wider than the other. A flare above 2.0 is a U-fold, not an arrowhead. If neither end qualifies, the yarn is unresolved and never a target. The direction is the walk axis, pointing out through the tip.
9. Freedom is a corridor from the tip, along the arrow direction, to the field edge. It is 0.7 of the rope radius on each side of the line. Other rope component IDs in that corridor are recorded as blockers for buffer backtracking. The rope's own pixels do not block it.
10. A yarn matches a couch when its hue, or a clear second hue, is within 16 degrees of that couch, and its saturation is within 0.15 of the couch rim's. Pale shades share a hue with deep ones (lavender and royal blue, mint and green). Measured same-color pairs differ by at most 0.05 in saturation; look-alikes differ by 0.24 or more. White has no stable hue, so a white yarn matches a white couch when both saturations are under 0.12 and the colors are within distance 48. Other free yarns are buffer targets.
11. These pieces are not yarns:
    - A small piece that is short in both directions (the mute button, the level pill). A short rope is kept when its long side is more than 1.15 peg radii and at least 1.6 times its short side. Longer yarns are kept even when a fold makes the bounding box nearly square.
    - A piece in a top corner.
    - A piece that touches the field border, such as buttons cut off by the bottom of the screen.
    - A piece more than 1.7 times as thick as the median yarn (the scroll bar). Such a piece is removed from every blocker list, so it never blocks a yarn.

Hues are averaged circularly. Red and pink sit on both sides of 0/360 degrees, and a plain average of 355 and 5 would give 180.

The pointer goes to the middle of the centerline, which lies on the rope, and the click lands there.

## Known vision limits

- Where one rope crosses another, the lower rope can break into two regions. Treat a bad split as a vision bug and tighten the matcher, do not paper over it with a click.
- Two ropes of the same color that touch become one region.
- Freedom is the straight arrow corridor to the field edge, not a slide along the winding body.
- A few yarns have no clear arrowhead at either end (for example, where the head touches another rope). They stay unresolved and are never targets. The debug image shows no arrow stub for them.
- Couch paint and board yarn of the "same" color can sit more than 16 degrees apart. Those yarns are offered as buffer targets until the match window is widened with a level where that happens.
- Locked couches are ignored even if a later level opens a third. Revisit this when a screenshot shows three playable couches.

## Coordinates

Screenshots are top-left, y down. Pointer positions use global display points: top-left of the main display, y down (`CGDisplayBounds`). Analysis may scale a capture down, or enlarge a small board. Printed positions are analysis pixels. They are converted back before the pointer moves.
