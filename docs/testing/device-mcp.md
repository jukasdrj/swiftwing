# Device MCP test bench

Device MCP 0.10.0 mirrors an iPhone, iPad, or iOS 27 simulator and exposes it to an agent over MCP. SwiftWing's debug build adds a **Test bench** the agent can tap, plus the same launch arguments the UI tests already use.

The bench is compiled into Debug only. It is not part of the product UI. When Impeccable (or any visual review) judges the app, ignore the "Test bench" capsule and use it only to reach a screen.

## Connect

Device MCP is at `/Applications/Device MCP.app`. MCP is on (`mcpEnabled` in `com.proxyman.devicemcp`). Grok's user config launches the stdio bridge:

```toml
[mcp_servers.device-mcp]
command = "/Applications/Device MCP.app/Contents/MacOS/device-mcp"
```

The Device MCP app has to be running. A new Grok session picks up the server. Free includes tap, screenshots, and one mirrored device. `build_and_run` and `install_app` need Device MCP Pro. Without Pro, install from Xcode, then `launch_app`.

Simulator (no Pro required for control):

1. `start_simulator` with `simulator` = `iPhone 18 Pro Max` (or `model` = `iPhone 18 Pro Max` to create one).
2. `build_and_run` with `project_path` = this repo and `scheme` = `swiftwing`, or launch an installed build.
3. `list_elements`, then `tap` a ref or `tap_text`.
4. `take_screenshot` for layout and color. The accessibility tree is the source for controls.

`launch_app` can pass arguments. Bundle id is `com.ooheynerds.swiftwing`.

| Goal | `arguments` |
|---|---|
| Skip onboarding and the camera primer | `["UI_TESTING"]` |
| Empty library | `["UI_TESTING", "CLEAR_DATA"]` |
| Seeded library | `["UI_TESTING", "SEED_LIBRARY"]` |
| Onboarding | `["FORCE_ONBOARDING"]` |
| Camera coach | `["UI_TESTING", "FORCE_CAMERA_GUIDANCE"]` |
| Scan one shelf | `["UI_TESTING", "INJECT_TEST_IMAGE", "SHELF_FIXTURE=science-paperbacks"]` |

`SHELF_FIXTURE` is one argument, `SHELF_FIXTURE=<id>`. Without it, `INJECT_TEST_IMAGE` still loads `test_book_stack.jpg` from the bundle, `TEST_IMAGE_PATH`, or the repo root.

## On-screen hooks

The capsule identifier is `test_bench_open`. `tap_text` "Test bench" works when the tree is missing (simulator OCR). Inside the sheet:

| Identifier | What it does |
|---|---|
| `test_bench_show_onboarding` | Presents the real onboarding flow |
| `test_bench_show_guidance` | Camera tab, first-run coach |
| `test_bench_tab_library` / `_review` / `_camera` | Switches tabs |
| `test_bench_clear` | Deletes every book |
| `test_bench_seed` | Replaces the library with the sample set (Dune is `book_cell_9780441172719`) |
| `test_bench_shelf_<id>` | Downloads that shelf and sends the JPEG through the normal scan pipeline |
| `test_bench_done` | Closes the sheet |
| `test_bench_status` | Last action |

Shelf downloads land in the app cache (`ShelfFixtures/<id>.jpg`) and are reused. They are Wikimedia Commons files at a 1920 long edge, which matches the Talaria upload size. A scan still needs the network and a live Talaria job. The bench does not stub the API.

## Fifteen shelves

Source pages are `https://commons.wikimedia.org/wiki/File:<file name>`. The app requests `Special:FilePath` at `width=1920`.

| id | What it stresses |
|---|---|
| `science-paperbacks` | Close, readable, slightly leaned paperbacks. Start here. |
| `blyton-double` | Two tight rows of colorful spines |
| `shop-wall` | Tall shop wall, many shelves, mixed languages |
| `african-studies` | Shallow focus, only a few titles sharp |
| `norsk-set` | Nearly identical encyclopedia spines |
| `kazakh-set` | Uniform green Cyrillic set, perspective |
| `winnington-stack` | Spines stacked horizontally (tall-image rotation) |
| `mitre-stacks` | Dark worn leather, strong perspective |
| `walloon-home` | Uneven heights, plus covers facing out |
| `glass-cabinet` | Glass glare and a reflection |
| `comic-bays` | Thin comics and face-out displays |
| `manga-stacks` | Piles lying flat, not an upright row |
| `window-backlight` | Backlit, dark spines |
| `loc-aisle` | Long aisle, spines small in the frame |
| `account-ledgers` | Close, faded cloth, partial titles |

## Impeccable

Operate mode. Reach each surface, then screenshot at the phone size:

1. Onboarding (`test_bench_show_onboarding` or `FORCE_ONBOARDING`).
2. Empty library (`test_bench_clear`).
3. Seeded library grid (`test_bench_seed`), then search, sort, and the low-confidence filter.
4. Camera, including the first-run coach (`test_bench_show_guidance`) and the coach dismissed.
5. Review, after a shelf inject, once Talaria returns cards.

Judge the product screens. Leave the Test bench capsule out of the critique. `set_appearance` dark and light, and `set_accessibility` for a larger text size, are the variant checks. The app's own scheme is dark.

## Swift 6.4 and iOS 27.2

This Mac is Xcode 27.2 (Swift 6.4.2). Every target sets `SWIFT_VERSION = 6.4`. The deployment target stays **iOS 27.0** so the app still runs on the 27.0 floor while linking the 27.2 SDK.

The test targets enable Approachable Concurrency. The app target does not, and it does not set Main Actor as the default isolation. The app already isolates UI on the main actor and keeps `TalariaService`, `ImagePreprocessor`, and `OnDeviceScanner` as actors. Turning on Main Actor by default would fight that split. No iOS 27.2-only API was required for the scan path.
