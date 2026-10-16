# Yarn Jam bot

Works for [YarnJam](https://www.reddit.com/r/YarnJam/)

A macOS Swift tool that reads the Yarn Jam board in the browser and clicks the next yarn. It does not play by itself.

## Run

From this directory:

```sh
swift run YarnJamBot
```

The process waits. With the game visible, press `1`. That captures the screen, reads the board, moves the pointer to the first safe yarn, and clicks it. Press `1` again after the board settles. One press is one click.

macOS must allow Screen Recording and Accessibility for the app that launches the bot (Terminal or Cursor). If a capture or the keys fail, grant those and start it again.

To check a saved screenshot, without keys or pointer movement:

```sh
swift run YarnJamBot --image path/to/screen.jpg
```

Each `1`, and each `--image` run, writes `debug/last-analysis.png`. `--image` does not move the pointer or click.

## How it works

The game is a portrait view somewhere on the screen. A capture is searched for the wooden tray, the couches, the five buffer pegs, and the dark puzzle field.

No color is fixed in the code. Each couch's color is read from its rim on screen, and yarns are matched to that, so new levels with new colors work the same way. Each playable couch has a color and three slots. Two couches are open. The other two stay locked. A yarn is a colored rope with a round end and an arrow end. Yarns only move forward, toward the arrow. The arrow end is the end where the rope widens into a head. A yarn is free when the straight path from the arrow tip to the edge of the field is clear.

Each press chooses one active couch (the most-filled one, then the leftmost on a tie) and keeps targeting its color until the couch reaches 3/3. If no matching yarn is free, it traces that yarn's blockers. A blocker that fits the other couch goes there first, then any free yarn for the other couch. Only after that does it park a blocker with no couch color in the buffer. It never fills the fifth buffer peg, because that loses the level.

The expensive per-yarn work—skeletonization, arrow detection, and forward-corridor checks—runs concurrently across the CPU cores. Results are put back into stable screen order before target selection. `1` clicks the middle of the first safe yarn.
