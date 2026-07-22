# ITGMania Archipelago Module

A Lua module for **ITGMania** that functions as a client integration for the **Archipelago Multiworld Randomizer**.
It automatically synchronizes song unlocks, sends checks upon song clears/score thresholds, manages progression
modifiers, and provides interactive UI overlays directly inside the **Simply Love** theme.

---

## 🌟 Key Features

*   **Persistent WebSocket Connection**: A background client connection that runs continuously in ITGMania. It
      handles handshakes, syncs item unlocks, and automatically submits completed location checks.
*   **Dynamic Playlist & Live Song Wheel Updates**:
    *   Unlocked song charts are written to a local playlist file: `%APPDATA%/Themes/Simply Love/Other/Playlists/Archipelago - <SeedName>.txt`.
    *   The module forces the StepMania C++ engine to reload the playlist from disk when new songs arrive. If you are on the song selection screen
        (`ScreenSelectMusic`) and sorting by **Preferred**, the music wheel refreshes automatically so new unlocks appear instantly.
*   **In-Game Status Overlay (`F10`)**:
    *   Pressing **`F10`** on the music wheel opens a full-screen, scrollable dashboard.
    *   Displays: Room and Seed metadata, Win Goal progress, current modifier limits (if enabled), and a list of unlocked song charts.
    *   Selecting any song displays a detailed pane showing the current **Clear Condition** (active score type target, minimum percentage, fail
        allowance) and the individual status (`[x]` or `[ ]`) of all its checks.
*   **Interactive Score Evaluation Overlay**:
    *   Earn "Score Booster" items from the multiworld, which grant a `+0.25%` score increase.
    *   If you have unused boosters, a custom interactive panel auto-pops on the song evaluation screen.
    *   Allows you to distribute boosters to your **Money**, **EX**, or **High EX** performance.
    *   Displays a live preview of what check thresholds will unlock (e.g. *Clear Check 1*, *85% Score Check*) before you commit and send checks.
*   **Offline Seed Caching**:
    *   Caches DataPackage definitions (player names, item IDs, location definitions) to `%APPDATA%/Themes/Simply Love/Modules/Archipelago/SAVE_AP_<SeedName>/`.
    *   Does this for all connected players to show what players are unlocking songs for you, and what items you're unlocking for them.
*   **Real-Time Toast Notifications**:
    *   Dynamic status messages slide into view in the screen footer when:
        *   Connecting or disconnecting from the server.
        *   Receiving items/charts from another player (e.g., `RECEIVED: Song Name (from PlayerName)`).
        *   Sending checks to another player (e.g., `CHECK SENT: Song Name (to PlayerName)`).

---

## ⚙️ Installation & Setup

### 1. Client Installation
1. Copy `archipelago.lua` and the `Archipelago` folder into your ITGMania theme directory under:
   `ITGMania/Themes/Simply Love/Modules/`
2. Open `archipelago.lua` in a text editor and configure your connection credentials at the top of the file:
   ```lua
   AP.HOST = "ws://localhost:38281"  -- Replace with your Archipelago server address
   AP.SLOT = "ITGManiaPlayer"        -- Replace with your slot/player name
   AP.PASSWORD = ""                  -- Replace with your room password if set
   ```
   *Note: While optimized for standard **Simply Love**, UI elements might require styling adjustments on theme forks (like Zmod, ArrowCloud, or DigitalDance).*
   *Extra Note: This is incompatible with DeadSync until it can support themes and Modules. Assuming DeadSync does not implement this module's functionality directly.*

### 2. Multiworld Generation & Seed Setup (TODO)

A separate module (or portion of this one) will be dedicated to parsing your entire songlist and generating a `songpool.csv` file to give to the server.
This is not yet done.

---

## 🕹️ Controls Reference

### Status Overlay (`F10`)
*Accessible from the Song Selection wheel (`ScreenSelectMusic`).*
*   **`F10` or `ESC`**: Open/Close the overlay.
*   **`MenuUp` / `MenuDown`** (or Arrow Up/Down): Scroll through the list of unlocked songs to inspect details.
*   **`Start` / `Select`**: Close the overlay.

### Screen Evaluation Overlay
*Triggers automatically on `ScreenEvaluation` when unused Score Boosters are available.*
*   **`MenuUp` / `MenuDown`** (or Arrow Up/Down): Select which score system row to boost (Money, EX, High EX).
*   **`MenuLeft` / `MenuRight`** (or Arrow Left/Right): Decrease/increase the count of boosters to allocate.
*   **`Start`**: Confirm allocations and submit.
*   **`Back` / `Escape` / `Select`**: Exit without applying new boosters and send baseline checks.

---

## TODOs

* Support more complex items besides a score booster (combo shield? worst judgement upgrader?)
* Support traps sent from the server
* Enforce modifier restrictions (if enabled), meaning that until you unlock BPMs, Mini, or BG settings, they will be unchangeable
* Separate leg of the module for generating a song pool to pass to the server for world generation
* Allow the user to specify their AP credentials in game
* Fix the item application, as it's a little buggy with repeated charts
* Properly calculate HEX, that's not actually finished yet
* Decide if items should just be granted to the player as unlockable items, or if it should be shop based
  * e.g. players will send coins, and those coins unlock items or charts SRPG sytle
* Shortcut to regen the playlist in case of desync issues
