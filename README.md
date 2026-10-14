# Walkou

A native iOS app (SwiftUI, iOS 17+) for walking and running toward a step goal.

1. **Pick a goal.** Choose walk or run and a number of steps, for example 6,000.
2. **Get routes.** Walkou suggests three routes on the map whose length matches the goal:
   - **Loop:** finish where you started.
   - **One way:** end somewhere new.
   - **Free walk / free run:** no route. Halfway through your steps you get a reminder to turn back, plus a "Guide me back" button with directions to your start.
3. **Follow the path.** You get a live map, turn-by-turn voice directions, off-route alerts with a dashed detour back to the route, and live steps, distance, time and pace. Everything keeps working with the screen locked.
4. **Hit the goal: "YOU ROCK!"** A celebration screen appears with *"Go the extra mile, you can do it!"*. You can keep going or finish.

**💎 Gem Trail.** Every route comes with gems to collect:
- 🔷 **Common** (1 pt) every ~350 m.
- 💜 **Rare** (5 pts), one or two per route.
- 🟡 **Legendary** (10 pts) at the finish.
- 💚 **Bonus** gems (3 pts) a short detour off the route, showing the extra steps.

Walk within ~25 m of a gem to collect it (not counted above 25 km/h). Free walks spawn gems ahead of you, and at halfway a gold gem appears at your start. Points add up to levels (Walker → Explorer → Pathfinder → Trailblazer → Legend), and the collection shelf shows everything you've found. Gem artwork lives in `Assets.xcassets/Gems`, and sounds in `Resources/Sounds`.

Workouts are saved on the device (SwiftData) and appear under **Activity**. They can also be saved to Apple Health (see below).

## Running it

You need a Mac with **Xcode 16 or newer**.

1. Open `Walkou.xcodeproj`.
2. Select the **Walkou** target → **Signing & Capabilities** → choose your **Team**. A free Apple ID works: add it in *Xcode → Settings → Accounts*.
3. If Xcode reports the bundle ID is taken, change `com.walkou.app` to something unique, such as `com.yourname.walkou`.
4. Plug in your iPhone, select it as the run destination and press **Run**.
   - On the phone, the first time: *Settings → General → VPN & Device Management* → trust your developer certificate.
   - You may also need to turn on *Settings → Privacy & Security → Developer Mode*.

### Simulator vs. real iPhone

The simulator has no step counter. On it, steps are estimated from GPS distance, and you can fake movement with *Features → Location → City Walk / City Run*.
For the real experience (step counting, GPS, background tracking, voice in your pocket), use an iPhone.

## Apple Developer account

| | Free Apple ID | Apple Developer Program |
|---|---|---|
| Price | $0 | **$99 per year** (local pricing varies) |
| Run on your own iPhone | ✅ (the app expires after 7 days; just run it again from Xcode) | ✅ (1 year) |
| Background location, voice, notifications | ✅ | ✅ |
| Apple Health (HealthKit) | ❌ | ✅ |
| TestFlight / App Store | ❌ | ✅ |

The project builds with a **free Apple ID** out of the box, because HealthKit is left out of the default entitlements. Without it, the *Save to Apple Health* toggle in Settings shows an error, and workouts are still saved in the app.

**To turn on Apple Health once you have a paid account:** in the Walkou target's build settings, set
`CODE_SIGN_ENTITLEMENTS` to `Walkou/Resources/WalkouHealthKit.entitlements`. You can also add the *HealthKit* capability in *Signing & Capabilities*. Then turn on *Settings → Save to Apple Health* in the app.

## How routes are made

Apple MapKit only gives A→B walking directions. So `RoutePlanner` builds routes from waypoints:

- **Steps to distance** uses a fixed average stride: 0.75 m when walking, 1.0 m when running. So 6,000 walking steps ≈ 4.5 km.
- **Loop:** a triangle (start → A → B → start) in three different directions. It is sized using a typical 1.3× street detour factor, measured with MapKit, then rescaled once if it's more than 7% off target.
- **One way:** a single destination in three different directions, measured and rescaled the same way.
- Each route card shows how close the route is to the goal ("On target", "+6% steps"). The 🔀 button suggests three new routes.

During a workout, `RouteTracker` matches GPS fixes to the route. It only searches a window around your current progress, so loops and out-and-back streets don't confuse it. You count as off route after 3 fixes more than 40 m from it, and as back on route within 25 m.

## Project layout

```
Walkou/
  App/            App entry, tabs, shared AppModel and settings keys
  DesignSystem/   Colors, fonts and reusable components (from the moodboard)
  Models/         Activity/mode/plan, units and formatting, SwiftData WorkoutRecord, PlannedRoute
  Services/       Location, pedometer, MapKit route planner, HealthKit, voice, notifications
  Workout/        WorkoutSession (live workout engine), RouteTracker, geo math
  Features/       Onboarding, Home, Plan (goal + route picker), Workout (live, celebration, summary),
                  History, Settings
  Resources/      Info.plist, entitlements, asset catalog
WalkouTests/      Unit tests for route tracking, geo math and formatting
scripts/          generate_project.rb: regenerates Walkou.xcodeproj
```

### Adding files

`Walkou.xcodeproj` is generated. After adding or removing Swift files, you can either add them in Xcode as usual, or regenerate the project:

```sh
gem install xcodeproj
ruby scripts/generate_project.rb
```

## Not in v1 (ideas for later)

- Personal stride length (from height or Apple Health) instead of the fixed average.
- Route preferences: parks, quiet streets, flat routes.
- Apple Watch app, accounts, sync, challenges and leaderboards from the moodboard.
