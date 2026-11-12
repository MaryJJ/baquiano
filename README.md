# Baquiano

An addon for World of Warcraft: Forever (client 1.60.x, Interface 16001).

Baquiano records the paths you walk and uses them to guide you: set a
destination on the map and it finds the shortest route along the paths it
already knows, draws it, and leads you point by point with an arrow.

A *baquiano* is a local guide who knows the trails by heart.

## Installation

Copy the `Baquiano` folder into:

```
World of Warcraft/_forever_/Interface/AddOns/
```

For development a symlink is more convenient: changes in the repo show up with
`/reload`, with nothing to copy.

```bash
mkdir -p "/Applications/World of Warcraft/_forever_/Interface/AddOns"
ln -s "$(pwd)/Baquiano" "/Applications/World of Warcraft/_forever_/Interface/AddOns/Baquiano"
```

## Usage

- Walk. Recording is on from the start.
- Open the map (`M`): recorded paths are drawn in blue.
- **Alt + left click** on the map sets a destination. The route is drawn in
  gold and the arrow appears (it can be dragged).
- The arrow turns green when you are heading the right way, yellow when you
  drift, and red when you are going the opposite way.

| Command | What it does |
|---|---|
| `/baq` | Lists the commands |
| `/baq record` | Turns recording on or off |
| `/baq go X Y` | Sets a destination by coordinates (0 to 100) |
| `/baq stop` | Clears the active route |
| `/baq arrow` | Shows or hides the arrow |
| `/baq arrow reset` | Puts the arrow back in its starting position |
| `/baq paths` | Shows or hides the recorded paths on the map |
| `/baq info` | Points and links recorded in your zone |
| `/baq wipe` | Deletes your zone's recorded paths (asks first) |

## Limitations

- It only knows the paths you have walked. Where there are none, it guides in
  a straight line.
- Routes stay within one zone; it does not cross from one zone to another.
- The game gives position without height, so bridges, caves and floors overlap.
- Nothing is recorded while flying, on a taxi, or dead.
- Paths are saved on your computer and are not shared with other players.

## Files

| File | Contents |
|---|---|
| `Core.lua` | Settings, player position, map size |
| `Graph.lua` | Path network per zone and how it is saved |
| `Recorder.lua` | Recording while you walk |
| `Pathfinder.lua` | Shortest-route search (A*) |
| `Nav.lua` | Active route and point-by-point progress |
| `MapOverlay.lua` | Drawing on the map and click to set a destination |
| `Arrow.lua` | Guide arrow |
| `Commands.lua` | `/baq` commands |

`tools/make_arrow.py` regenerates the arrow image (`Baquiano/arrow.tga`).
