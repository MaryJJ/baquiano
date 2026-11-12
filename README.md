# Baquiano

An addon for World of Warcraft: Forever (client 1.60.x, Interface 16001).

Baquiano records the paths you walk and uses them to guide you: set a
destination on the map and it finds the shortest route along the paths it
already knows, draws it, and leads you point by point with an arrow.

A *baquiano* is a local guide who knows the trails by heart.

## Installation

1. Download `Baquiano-<version>.zip` from the
   [releases](https://github.com/MaryJJ/baquiano/releases) page (not the
   green "Code > Download ZIP" button: that one does not have the folder
   the game expects).
2. Close the game, and unzip it into:

   ```
   World of Warcraft/_forever_/Interface/AddOns/
   ```

   so that there is a folder `AddOns/Baquiano` with `Baquiano.toc` inside.
3. Start the game. In the character screen, *AddOns* should list Baquiano
   ticked. Type `/baq` in the chat to see the commands, or open
   Options > AddOns > Baquiano.

To update, delete the old `Baquiano` folder and unzip the new one: your
recorded paths are kept (they are saved in `WTF/.../SavedVariables`, not in
the addon's folder).

Baquiano comes with paths already recorded in several zones: they are added
on your first login (the chat says how many), and `/baq import undo` takes
them out if you would rather start empty. From then on it learns the paths
you walk. Another player can share theirs with `/baq export`, and you add
them with `/baq import` (see [Sharing paths](#sharing-paths)).

Carbonite, TomTom and Leatrix Maps are not needed; when Carbonite or TomTom
are installed, Baquiano works with them.

For development a symlink is more convenient: changes in the repo show up with
`/reload`, with nothing to copy.

```bash
mkdir -p "/Applications/World of Warcraft/_forever_/Interface/AddOns"
ln -s "$(pwd)/Baquiano" "/Applications/World of Warcraft/_forever_/Interface/AddOns/Baquiano"
```

## Usage

- Walk. Recording is on from the start.
- Open the map (`M`) and hold **Shift**: your recorded paths are drawn, blue
  outdoors and violet indoors (caves, buildings). Walks that passed through the
  same place are drawn as one line, thicker the more often you walked it.
  What you have just walked is drawn as green breadcrumbs that fade out
  behind you over about 400 yards (`/baq trail` hides them).
- `/baq paths`, or a key of your choice (*Key Bindings > AddOns > Baquiano*),
  shows or hides the recorded paths on the map and the minimap. In capital
  cities they stay hidden, since so many cross there (`/baq cities` to show
  them, or hold Shift on the map).
- **Alt + left click** on the map sets a destination. The route is drawn as a
  row of gold arrows moving towards the destination (white over a flight,
  faint orange where there is no recorded path), and
  the guide arrow appears (it can be dragged). The destination can be in
  another zone: open that zone's map and Alt + click there.
- To unmark the destination: **Alt + left click** on the destination itself,
  **right click** on the guide arrow, `/baq stop`,
  or a key of your choice (*Key Bindings > AddOns > Baquiano > Clear the route*).
- The route looks the same on the minimap and on Carbonite's map; on the
  minimap, when the destination is out of view, its gold disc waits on the
  edge, pointing where it lies.
- With the Carbonite addon (a version with its Map Provider API), the route and
  the recorded paths (when shown; fainter, and only those of your zone and the
  zones within about 800 yards) are drawn on Carbonite's map too, and
  **Alt + left click** on Carbonite's map sets a destination.
- Routes go round the other faction's towns (those with a flight master
  for only one side) and capital cities when there is a way; when there is
  none, or the destination is in one, the chat warns. `/baq avoid` turns
  this off. Towns without a flight master are not known (the game's files
  do not say whose they are).
- Waypoints set by other addons (through TomTom, or Carbonite's stand-in for
  it: SkillUp Forever, quest helpers...) or the game's own map pin become the
  destination too, and when that waypoint is removed the route goes with it
  (unless you set another destination meanwhile). `/baq follow` turns this
  off.
- The guide arrow turns smoothly from green, when you are heading the right
  way, through yellow, to red when you are going the opposite way. Below it:
  what is left to the destination along the route, and roughly how long it
  takes at your current speed ("take the flight to ..." at a flight master).

### Boats and zeppelins

Baquiano knows the docks of every boat and zeppelin (taken from Leatrix
Maps, which also has the routes Forever added; see
`tools/make_transports.py`), and routes use those of your faction and the
neutral ones, counting the trip and about two and a half minutes of waiting
at the dock; with them, routes can cross to another continent. A trip is
guessed to take two minutes until you ride it: then its real time is noted
(the chat says so). A boat or zeppelin missing from the tables is learned by
riding it ("learned a boat or zeppelin trip"). At the dock the arrow says "take the boat or zeppelin to ...",
hides during the trip and goes on after it.

- `/baq boats` turns them on or off in routes; `/baq boats list` lists the
  trips; `/baq boats forget 3` forgets what was measured of trip 3
  (`/baq boats forget`, of all of them).
- No paths recorded near the dock: the route goes to it in a straight line
  (drawn as a gap), and from the dock where it lands straight on to the
  destination if it is on that continent.
- The Deeprun Tram between Stormwind and Ironforge is used too: the route
  takes you to its entrance and goes on from the other one (about two
  minutes counted, with the wait). Inside, the game gives no position, so
  the arrow waits until you come out.
- The boat that goes round Southshore, Auberdine and Menethil only sails
  one way, so routes take it that way.
- Rides are noticed because you move faster than you walk while standing
  still; nothing is recorded as a path meanwhile.

### Sharing paths

- `/baq export` shows the paths of your zone as a text (`/baq export all`,
  of every zone). Copy it with Ctrl+C and send it however you like
  (Discord, a message, a text file). It carries the crossings between
  zones and the boat and zeppelin times too; not your flights, trail or
  distance walked.
- `/baq import` opens a box: paste the text with Ctrl+V, check what it
  holds and click Import. Its points are added to yours: those within a
  few yards of one of your points are joined to it, the rest are added.
  Nothing of yours is deleted. `/baq import Juan` gives the import a name.
- `/baq import list` lists the imports; `/baq import undo` takes the last
  one out again (not if those zones were edited since in edit mode).
- A text cut short or changed on the way is refused, and nothing is added.

### Flights

Routes can include flights when that is faster than walking (or riding: it
compares by time, at your current speed).

- Open a flight master's map once: Baquiano learns which flights your
  character knows (the chat says how many). It learns again each time, so new
  flight masters are added as you discover them. Each character has its own.
- The route takes you to the flight master and stops there: "take the flight
  to ...". The flight is drawn as a thin white line. During the flight the
  arrow hides, and after landing the route goes on.
- `/baq flights` turns flights in routes on or off.

Most settings are also in the game's *Options > AddOns > Baquiano* page
(`/baq options` opens it).

| Command | What it does |
|---|---|
| `/baq` | Lists the commands |
| `/baq options` | Opens Baquiano's page in the game's options |
| `/baq record` | Turns recording on or off |
| `/baq go X Y` | Sets a destination by coordinates (0 to 100) |
| `/baq go Orgrimmar` | Sets a destination in a town with a flight master, by name (English or your game's language; small typos are fine) |
| `/baq route` | Lists the active route step by step (walks, flights) |
| `/baq stop` | Clears the active route |
| `/baq arrow` | Shows or hides the arrow |
| `/baq arrow reset` | Puts the arrow back in its starting position |
| `/baq minimap` | Shows or hides the route on the minimap |
| `/baq carbonite` | Shows or hides the route on Carbonite's map |
| `/baq flights` | Uses known flights in routes, or not |
| `/baq paths` | Shows or hides the recorded paths on the map and minimap |
| `/baq trail` | Shows or hides the trail of what you just walked (green breadcrumbs) |
| `/baq cities` | Shows or hides the recorded paths in capital cities |
| `/baq walked` | Shows or hides the yards walked: this session and in total (per character) |
| `/baq walked reset` | Starts the session count again (also right click on it) |
| `/baq boats` | Uses boats and zeppelins in routes, or not (`list`, `forget N`) |
| `/baq avoid` | Keeps routes away from the other faction's towns, or not |
| `/baq follow` | Follows waypoints set by other addons or on the map, or not |
| `/baq walked units yd` | Unit for the distance walked: `yd`, `m`, `km` or `mi` |
| `/baq export` | Your zone's paths as a text to share (`all`, every zone) |
| `/baq import` | Adds paths shared by another player (`list`, `undo`, or a name) |
| `/baq info` | Points and links recorded in your zone |
| `/baq wipe` | Deletes your zone's recorded paths (asks first) |

## Limitations

- It only knows the paths you have walked. Where there are none, it guides in
  a straight line. Gaps of up to 250 yards between recorded paths are crossed
  in a straight line too, but only when going around by known paths is more
  than four times longer. Those straight stretches are drawn with faint
  orange arrows: the game may have hills or cliffs there.
- Routes cross from one zone to another only where you have walked across the
  border at least once (that is how it learns the crossing; the chat says
  "learned a crossing between zones"). Hearthstones and portals do not
  count. Routes cross between continents only by boat or zeppelin. Flights do
  count (see above): a zone you have never walked can be reached by flying
  there, with a straight line from the flight master.
- The game gives position without height, so bridges, caves and floors overlap.
  Points recorded indoors (caves, buildings) are kept apart from points
  outside: they connect only where you walked in or out. Paths recorded before
  this was added count as outdoors.
- Nothing is recorded while flying, on a taxi, or on a boat or zeppelin (noticed
  because you move faster than you walk). Walking as a ghost is recorded.
- Paths are saved on your computer and are not shared with other players.

## Credits

- Flights and towns come from the game's own tables, as published by
  [wago.tools](https://wago.tools).
- The docks of boats and zeppelins, including the routes Forever added,
  come from [Leatrix Maps](https://www.curseforge.com/wow/addons/leatrix-maps)
  by Leatrix. Thank you!

## Files

| File | Contents |
|---|---|
| `Core.lua` | Settings, player position, map size |
| `FlightData.lua` | Flight masters and flights (generated, do not edit) |
| `Flights.lua` | Which flights the character knows |
| `TransportData.lua` | Docks of boats and zeppelins (generated from Leatrix Maps) |
| `Share.lua` | Export and import of paths as text, and the paths that come with the addon |
| `StarterData.lua` | Paths that come with the addon (generated) |
| `Transports.lua` | Boats and zeppelins: trips usable and times measured |
| `Graph.lua` | Path network per zone and how it is saved |
| `PathView.lua` | Recorded paths bundled and simplified for drawing |
| `Bindings.xml` | Keys to show or hide the recorded paths and to clear the route |
| `Recorder.lua` | Recording while you walk |
| `Pathfinder.lua` | Shortest-route search (A*) |
| `Nav.lua` | Active route and point-by-point progress |
| `Editor.lua` | Edit mode: drawing and deleting paths on the map (developer tool, hidden) |
| `MinimapOverlay.lua` | Route on the minimap |
| `CarboniteOverlay.lua` | Route on Carbonite's map, through its Map Provider API |
| `MapOverlay.lua` | Drawing on the map and click to set a destination |
| `Arrow.lua` | Guide arrow |
| `Odometer.lua` | Yards walked, this session and in total |
| `Options.lua` | Page in the game's Options > AddOns |
| `Waypoints.lua` | Waypoints from other addons (TomTom, Carbonite) and the map pin |
| `Commands.lua` | `/baq` commands |

`tools/make_arrow.py` regenerates the guide arrow image (`Baquiano/arrow.tga`),
and `tools/make_textures.py` the small ones: the route's arrows
(`chevron_gold.tga`, `chevron_white.tga`), the destination (`dest.tga`), the
trail's breadcrumbs (`trail.tga`) and the edit-mode dot (`dot.tga`).

`tools/make_flights.py` regenerates `Baquiano/FlightData.lua` (flights, and the
towns of each faction) from the game's
own tables, as published by [wago.tools](https://wago.tools) for the Forever
client. Run it again when the game updates.

`tools/make_starter.py` regenerates `Baquiano/StarterData.lua`, the paths
that come with the addon, from your own `SavedVariables/Baquiano.lua` (close
the game first so it is up to date). Each player gets them added once per
version of that file; points they already have are joined, not repeated.

`tools/package.py` builds `dist/Baquiano-<version>.zip` to share, with the
`Baquiano` folder at its root and only the files the game loads; the version
comes from `## Version:` in `Baquiano.toc`, so change it there first (and
run `make_starter.py` before, to ship your latest paths). Then
publish the zip as a GitHub release (Releases > Draft a new release, a tag
such as `v0.1.0`, and the zip attached).

`tools/make_transports.py` regenerates `Baquiano/TransportData.lua` (the
docks of boats and zeppelins) from the installed Leatrix Maps
(`Leatrix_Maps_Icons.lua`; its path can be given as an argument). Run it
again when Leatrix Maps adds routes.
