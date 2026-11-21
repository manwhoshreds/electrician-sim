# Agent handoff: Electrician Sim

For the next coding agent picking this project up. Read it all before changing code.
It covers how the project is built, how to verify changes, the traps, and the next task:
a data-driven service call system (spec at the end), mapped onto what already exists.

## Start here

1. The data-driven service-call refactor is active. The dead-receptacle vertical
   slice is complete, and failed GFCI, failed switch, failed fixture, weak-breaker
   and overload calls use shared strategies against real domain state. Last full
   run: **285 unit tests plus both headless smoke runs, all passed** (after the
   house was rebuilt to the owner's plan, below).
2. Engine: **Godot 4.7.2**, typed GDScript, Forward+. No addons. No autoloads.
   No git repository (the owner said not to worry about it).
3. **Don't open game windows without asking.** The last session briefly opened
   windowed screenshot runs on the owner's Wayland desktop; there's no Xvfb on this
   machine. Prefer headless checks.

## The house: built to the owner's floor plan

Every service house is the owner's one-story ranch plan: **40 x 30 ft**
(12.192 x 9.144 m) plus a 6 ft covered porch across the front. (An earlier pass
built it 40 x 50 ft, which pushed yard trees into kitchens; that's fixed, and the
trees are back.) Local metres: x across the front (kitchen side negative), +z
toward the street. `Town` holds the plan's size, front/back door and window
positions (`HOUSE_PLAN_*`, `PLAN_*`); `HouseInterior.WALLS` is the table of inside
walls and their doorways. Check positions against that table, not by eye.

- Kitchen/dining back left: an L of counters (corner cabinet, range, cabinet,
  fridge down the left wall; microwave, toaster, sink under the window, dishwasher,
  cabinet along the back), back door at the end of the counter.
- Family room front left: TV on the left wall, couch facing it, front door.
- Laundry back middle (water heater, washer, dryer), master bath under it
  (vanity, toilet, tub, linen cupboard; door into the master).
- Hall across the middle to the master (back right, walk-in closet below it),
  the hall bath, and bedroom 2 (front right, closet beside the hall bath).
- HVAC: air handler in the attic over the hall, return grille in the hall
  ceiling, thermostat on the hall wall, condenser on a pad out back with its
  disconnect on the wall. Placeholder models.

**How it's protected:**
- Boxes are placed with `_box_on(kind, wall, along, height, side, ...)` /
  `_switch_on`, which put them on a wall's *face* and cut the hole for them.
  Don't place wall boxes at a wall's centre line (they end up buried).
- `layout_violations()` fails any wall box that isn't on a wall face, sits in a
  doorway, or is outside the house, and any furniture outside the house. The
  20-job smoke run calls it for every house.
- `tests/unit/test_house_layout.gd` builds the real house and checks: every box,
  light and detector is in the room it's named for; appliances are in their
  rooms; the customer's toast spot is at the toaster; and physics rays walk
  through every doorway into every room, are blocked by the walls the plan has,
  and go out the back door only when it's open.
- To see the layout without opening a window, draw it from above, headless:
  project the house's `BoxShape3D` colliders and `BoxView` positions onto an
  `Image` and save a PNG. Tall colliders are walls; low ones are furniture and the
  wall above each doorway. This was used to check the rebuild against the plan.

The box order in `BuildingElectricalModel.residential()` is unchanged (saves and
callbacks index into it), so `_build_rooms()` creates boxes in that exact order.
The owner is collecting more floor plans; a second plan will need the layout
(walls, rooms, box spots) to become data rather than code in `HouseInterior`.

Unused duplicates: `GLB/`, `FBX/`, `Texture/` and `LICENSE.txt` at the project
root are a second copy of the appliance pack (the game uses
`assets/appliances/`). Ask the owner before deleting them.

## Water heater calls

- `WaterHeater` (`scripts/domain/water_heater.gd`): the heater's electrics and water. 240 V in on the upper thermostat, through the high-limit (ECO); the upper element heats first and only then hands power to the lower one. Meter points `l1 l2 u_a u_b lo_a lo_b tank`; `voltage()`, `ohms()`, `is_live()`. Faults `upper_element`, `lower_element`, `eco`. Draining (cold off, drain open) is needed before an element unscrews; power on before it's full again dry-fires the element.
- `WaterHeaterView` (`scripts/presentation/water_heater_view.gd`): the close-up in the laundry. Finds its click points by node name in `assets/water_heater/water_heater.glb`, so keep the names in `art/water_heater_covers.py` (`UpperCompartment`, `UpperThermostat_ScrewL1`, `UpperElement_ScrewA`, `DrainValve_Handle`...). It ticks the heater and reports its 18.75 A to the panel as `demo["5:water heater"]`.
- Jobs: `data/jobs/wh_upper.tres`, `wh_lower.tres`, `wh_eco.tres` (family `"heater"`); part `data/parts/Element.tres`. `JobTuning.heater_job_percent` (default 15) is rolled on the generator's own `RandomNumberGenerator`, seeded from the address and serial, so it never moves the global dice. The service golden pins it to 0.

## The home computer: TradesmanGear.com

- `ComputerScreen` (`scripts/presentation/computer_screen.gd`): sit at the desk at home (`HomeHouse.computer`, `seat_view()`) and the view moves in to the monitor: a browser on TradesmanGear.com (Shop All, categories, Deals, search, item pages, cart) and a Mail app. Product pictures are spinning 3D models (`ShopModels`, `Preview3D`).
- Catalog: one `ShopItem` per file in `data/shop/` (truck gear, tools, power tools, safety, workwear). `effect`: `truck_space`, `bag_slots`, `vehicle`, `headlamp`, `light_bar`, `insulated_gloves`, `work_boots`, or `""` (no gameplay effect yet: the five hand/power tools and the boots).
- `Upgrades` (gameplay): owned + on the way. `ServiceCall.buy_online()` pays and orders; `_take_deliveries()` runs from `_process` once it's past 8 AM next day, **only between jobs and out of the truck**; `_apply_upgrades()` sets bag slots, truck space (also `SupplyCounter.truck_space`), headlamp, gloves, light bar and the van. The van's price is still `JobTuning.van_price`. Saved as `upgrades` and `mail`; an old save with the van gets `work_van` marked owned.
- Inbox (`ServiceCall.inbox()`): order and delivery emails, then customer reviews from `Aftercare.reviews`.
- Tests: `tests/unit/test_computer.gd`. The service golden's shop section now buys the van online (re-recorded 2026-11-16; only that section changed).

## Verifying changes

```
tests/run.sh             # unit tests + "main scene loads" + "play 20 jobs" smoke run
tests/run.sh <filter>    # only unit tests whose file or test name contains <filter>
```

- Runner: `tests/run_tests.gd`, an in-house runner (no GUT). It runs every `test_*`
  method in `tests/unit/test_*.gd` on a fresh instance. Tests extend
  `res://tests/test_case.gd` (`eq`, `near`, `is_true`, `is_false`, `check`,
  `add_node`, `before_each` / `after_each`; tests may `await`).
- `run.sh` fails on any engine `ERROR` / `SCRIPT ERROR` line, including
  "ObjectDB instances leaked at exit". Treat that output as a real failure.
- **Golden captures** (`tests/golden/*.json`) are behaviour recorded from reference
  code: `aftercare_simulate`, `box_scenarios` (415 wiring scenarios plus repair
  flows), `service_scenarios` (60 seeded jobs through the real ServiceCall, plus the
  supply counter).
  - Recapture only to accept a **deliberate** behaviour change, using
    `tests/tools/capture_*_golden.gd`. Before recapturing, diff the old and new files
    and confirm only the intended entries changed.
  - Each golden has an **adapter section** in `tests/support/*_scenarios.gd`. A
    refactor updates the adapter, not the observations.
- **Mutation checks** are the established practice for new tests: copy the project to
  the scratchpad, break a line, and confirm a test fails.

## Traps (each of these has bitten before)

- **The owner's real save file.** `SaveGame.enabled = false` must be set in any
  test or headless run that loads `main.tscn`; `run.sh` passes `-- --no-save` to the
  main-scene smoke run. The real save lives at
  `~/.local/share/godot/app_userdata/Electrician Sim/save.json`.
- **The owner tunes `.tres` files** (`data/aftercare_tuning.tres` currently has
  `days_played = 7` and `good_work_callback_percent = 19`). Goldens and tests must pin
  default tuning by creating `AftercareTuning.new()` / `JobTuning.new()`, never by
  loading the game's `.tres`. Every slider's full range must work: a 7-day setting
  once crashed a 3-entry array.
- **Global RNG order is load-bearing.** The goldens and the seeded playthrough depend
  on the exact sequence of `randf` / `pick_random` calls. Anything new that is built
  at startup must not roll the global dice; the supply clerk uses
  `Customer.look_seed` for exactly this reason. If a change alters the dice order on
  purpose, recapture and explain why.
- **Engine quirk:** a `-s` script, or a helper it *preloads*, whose code names game
  classes or has inner classes extending them, is reported as "leaked at exit". Load
  such helpers at runtime with `load()` (see `tests/smoke/poke.gd`,
  `test_box_golden.gd`). This is not a game leak.
- **RefCounted cycles leak.** 3-way partners point at each other, so
  `ElectricalDevice.partner` is a `WeakRef`. Watch for new cycles.
- JSON makes every number a float. `load_save` functions cast with `int()`.
- `set_anchors_preset(FULL_RECT)` on a freshly created Control leaves it 0 × 0. Use
  `set_anchors_and_offsets_preset`.

## Architecture (as it is now)

```
scripts/domain/        pure electrical model; no scene tree
  electrical_panel.gd  ElectricalPanel: split-phase potentials, Circuit list, faults,
                       thermal trips, measurements, check_repair(), overload_trips
  circuit.gd           Circuit: CircuitSpec + Breaker + wire_landed + heater
  breaker.gd           Breaker: rating, handle, Fault enum (NONE/OPEN/WEAK/HOT)
  electrical_device.gd ElectricalDevice: one box (receptacle, GFCI, range,
                       switch/dimmer/3-way, fixture/fan, jbox, smoke). Wires on
                       terminals, buses, links (feed / partner / junction), faults,
                       repair_state(), commands (land, loosen, install...)
  overload_trip.gd     what was running when a breaker tripped from overload
scripts/data/          typed Resources; content lives in data/*.tres
  circuit_spec.gd, device_spec.gd, part_spec.gd (data/parts/*.tres),
  job_type.gd (data/jobs/*.tres), job_tuning.gd (data/job_tuning.tres),
  aftercare_tuning.gd (data/aftercare_tuning.tres)
scripts/gameplay/      rules of the business; no presentation
  job_generator.gd     picks definitions; completes device strategies after house construction
  active_job.gd        persistent service-call identity/status plus runtime job state
  service_call_*       factory, strategy registry, JSON repository and generation port
  *_strategy.gd        reusable dead-receptacle, device-fault and breaker-trip generation
  service_objective.gd, circuit_objective.gd  outcomes checked against real domain state
  inventory.gd, wallet.gd, credit_account.gd, business_stats.gd
  billing.gd           job sheet (pay, bonuses, penalties, stars)
  work_log.gd          what you did at a panel or box (tested dead, shocks...)
  supply_counter.gd    supply house conversation: buy, return, credit
  save_game.gd         user://save.json: versioned, .tmp swap, damaged files to .bad
  pause_summary.gd     snapshot the pause screen displays
scripts/presentation/  box_view.gd (BoxView), supply_house.gd, pause_screen.gd, ui_icon.gd
scripts/ (not yet moved, mostly presentation)
  service_call.gd      ServiceCall: Node coordinator plus all customer dialogue
  aftercare.gd         Aftercare: the days after a job (callbacks, inspections,
                       fires, reviews, habits); remembers each house's panel and
                       device snapshots
  house_interior.gd    HouseInterior: builds a house's rooms AND creates its
                       ElectricalDevices and BoxViews when a job starts
  panel_view.gd, hud.gd, town.gd, van.gd, player.gd, customer.gd, meter_base.gd,
  power_company.gd, appliance.gd, main.gd ...
```

`Appliance` is now live in `HouseInterior`: appliances can be slid out/back with E
and operated with F. Their operation depends on real circuit/outlet power and reports
real current to `ElectricalPanel`. The Godot Asset Library package was found in
`~/.cache/godot/tmp_asset_kitchen-appliance.zip`; its licensed GLB models and required
attribution were imported into `assets/appliances/`. The house now uses its fridge,
stove, microwave, washer and dryer. Imported models are offset fully in front of the
wall; the 600 mm stove is scaled to an exact 762 mm/30-inch opening. A regression test pins
both corrections.

All service houses use the owner's 40 x 30 ft ranch plan (see "The house" above). The former basement circuit is now a real
20 A laundry circuit; the washer and 240 V dryer produce real panel loads. A simple
purpose-built central HVAC system is present until dedicated art is sourced: attic
air handler with a hall return, outdoor condenser, hall thermostat and exterior disconnect. The
thermostat and disconnect are interactive, and indoor/outdoor equipment loads their
separate 120 V furnace and 240 V A/C circuits. The Asset Library pack contains no
HVAC art, so replace these serviceable placeholder meshes when an HVAC pack arrives.

**Conventions:**
- Typed GDScript, small classes, and explicit dependencies (set fields before
  `add_child`).
- Each owner has `to_save()` / `load_save(d)`; `SaveGame.capture` / `apply` compose them.
- `##` doc comments written in plain, concrete language about the game world. Match
  that voice.
- Content and tunables live in `.tres` files with inspector sliders; chances are
  percentages.

## Owner preferences

- Casual and direct. Doesn't like alarm words ("risk"); be calm and plain about what
  could go wrong and what protects against it.
- Wants every gameplay number tweakable as one inspector value.
- Decides scope; ask when a choice is genuinely theirs. Recent decisions:
  - Saves happen **between jobs only**, and the game auto-continues on launch.
  - The pause screen shows unbuilt features as greyed **"Coming soon"** placeholders.
  - Supply-house credit is gated on *current* five-star reviews; the number is
    tunable (default 50).
- Backlog the owner asked for: a **"run a new circuit" upsell** when a customer
  overloads a circuit. The panel is full (all 16 slots used), so it needs a tandem
  breaker or a subpanel.
- **Residential systems pass:** the first implementation now exists: central HVAC,
  laundry, washer, dryer, dedicated circuits, controls, and real loads. The HVAC
  equipment still uses programmer-art placeholders, needs visual/layout QA, and does
  not yet have HVAC-specific service-call definitions. Do not regress it to decorative
  props; faults and calls must continue to operate on honest domain state.

## Service call system (done 2026-11-15)

How a call comes to be, in order:

1. **`ServiceCallGenerator`** (`scripts/gameplay/service_call_generator.gd`) picks a home, in random order, from the **`PropertyRegistry`**.
2. It reads that home's **`BuildingElectricalModel`**: panel, devices, water heater, install requests.
3. It keeps the definitions that apply there: property type, `eligibility` and `prerequisites`.
   - These are rule names from **`ServiceCallSpecs`**, such as `has_working:Receptacle`, `has_attic` or `min_five_stars:10`.
   - The definition's strategy must also agree (`is_eligible`).
4. It picks one of those by `weight`.
5. The strategy makes the call:
   - It picks the target with the generator's dice, makes the fault real through domain commands, and checks the symptom.
   - If the symptom isn't there, it undoes everything.
   - It writes a complaint that describes symptoms only.
6. **`ServiceCallFactory`** builds the call (`ActiveJob`) as GENERATED. The repository saves it, and the generator marks it AVAILABLE.
7. **`ServiceCallScheduler`** puts it on the board.
   - It sets a window from `urgency`: emergency (any hour), standard (business hours, weekdays) or appointment (booked).
   - It expires calls nobody takes in time.
   - `ServiceCall.start_job` takes the next call from the board, moving the game clock on to the call's window if needed.

Other parts of the system:

- **Lifecycle:** `ActiveJob.TRANSITIONS`. The statuses are GENERATED, AVAILABLE, ACCEPTED, SCHEDULED, IN_PROGRESS, COMPLETED, CANCELLED and EXPIRED. New enum values go on the end, because saves store the number.
- **Dice:** `call_seed` (saved) plus the repository serial. Same game, same calls, before and after a load.
- **Persistence:** in the save file, under `service.properties` (every touched house's installation) and `service.service_calls` (records). `ServiceCallScheduler.rebuild()` turns records back into live calls pointing at the same equipment.
- **Strategies** (`ServiceCallStrategyRegistry`):
  - `dead_receptacles`: weighted `causes` of loose, scorched or bad_splice.
  - `device_fault`.
  - `breaker_trip` and `breaker_fault`: weak, overload, open, hot.
  - `water_heater`.
  - `install_device`.
  - `on_arrival`: older device calls whose fault is still placed when the house is built (`ServiceCall._place_device_fault`). That covers smoke, range, light_loose, light_nut, dimmer, fan, three_way, jbox and scorched. Migrating one is a data change once a strategy covers it.
- **Objectives:** `ServiceObjective` (device powered and ok), `CircuitObjective`, `WaterHeaterObjective` and `InstallObjective`. All of them judge the real state, so any valid repair counts.
- **New receptacle install:**
  - The model: `BuildingElectricalModel.INSTALL_SPOTS`, `request_install`, `rough_in(id, source)`. `ElectricalDevice.source` and `add_cable_out()` mean a new outlet's power comes off another outlet's spare screws.
  - The house: `HouseInterior.INSTALL_PLACES` is where each spot is on this plan; `cut_in()` needs the `OldWork` part in hand.
- **Adding a call:** a `.tres` in `data/jobs/` with a `weight`, `eligibility`, and an existing `generation_strategy`.

Limits as built:
- One house type (residential).
- The two install spots are fixed per plan.
- Cut-in feeds from the nearest working receptacle in the room.
- A cut-in made during a job has no hole in the drywall until the next visit.
- Callbacks still come from Aftercare and skip the board.

## Recent history (for context)

1. Characterization tests and harness.
2. Typed breakers and circuits.
3. Device electrics pulled out of BoxView.
4. ServiceCall split into the gameplay classes.
5. Save and load.
6. Overload advice: customers learn "one thing at a time".
7. Walk-in supply house with the clerk Ray, and the credit account.
8. Pause screen redesign from the owner's mockup.
9. (Codex) Service-call strategies, building electrical model, appliances, HVAC,
   a first pass at the new house layout.
10. House rebuilt to the owner's 40 x 30 ft plan; layout checks and tests added.

There are more notes in Claude's memory, but this file is self-contained.
