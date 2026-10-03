# bike-assyst

an assistant for ebikers. Works with alt mode glasses like Nreal. 
- If possible, main screen is deemed or turned off, but it turns on if user presses buttons on the phone, touches fingerprnt sensor, etc.
- Screen on Nreal is clear by default, to let user see the road
- App imports route from Google maps and leads the user. Shows arrows left/right before turns. 
- If user turns head, shows small img from the camera in the right/left upper corner depending on the turn side. Phone's camera is used for the rear view

## Status

Flutter app (Android + iOS). What works so far:

- **Google Maps link import**: paste (or keep on the clipboard) a Google Maps directions or place link, including `maps.app.goo.gl` short links. The stops are read from the link and the bike route, with Google's own turn instructions, comes from the Google Routes API. A place link, or a link starting at "my location", is routed from where you are.
- **File import**: GPX (tracks or routes) and KML (`LineString`, `gx:Track`, which is what Google My Maps exports). A built-in demo route lets you try it without a file.
- **Turn detection**: GPX/KML tracks carry no instructions, so turns are derived from the route's shape (slight / normal / sharp left and right, U-turn, arrival).
- **Navigation**: GPS fixes are matched to the route to find the next turn, distance to it, off-route and arrival.
- **Glasses HUD**: a pure black screen (transparent on Nreal/XREAL) that shows a turn arrow on the side of the turn only when the turn is within 150 m. Screen stays awake; tap the phone to show ride controls.
- **Phone screen dimming**: the phone's own screen goes to minimum brightness for the ride. Tapping it or pressing a phone button (such as volume) lights it up and shows the ride controls for 4 seconds, then it dims again. It stays lit once you arrive, and normal brightness comes back when the ride ends.
- **Simulated ride**: rides the route without GPS, to try the HUD at a desk.

Not yet: opening links straight from Google Maps' Share button, waking the screen from the fingerprint sensor, head-turn detection and the rear camera picture-in-picture.

## Google Maps API key

Link import calls the [Routes API](https://developers.google.com/maps/documentation/routes) (the current version of Google's directions service; the older Directions API is legacy).

1. In Google Cloud Console, create a project with billing enabled and enable **Routes API**.
2. Create an API key and restrict it to the Routes API (and, ideally, to your app's package name / bundle id).
3. Copy `env.example.json` to `env.json` (git-ignored), put the key in it, and run with:

```sh
flutter run --dart-define-from-file=env.json
```

Without a key the app still works with files and the demo route; the Google Maps button explains what's missing.

## Development

```sh
flutter pub get
flutter analyze
flutter test
flutter run
```

Code layout: `lib/geo` (distance/bearing math), `lib/route` (route model, GPX/KML parser, turn detection), `lib/nav` (route matching, GPS and simulated positions), `lib/ui` (home screen, HUD, turn arrow, screen dimmer).
