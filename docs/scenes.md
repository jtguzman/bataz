# Scene Registry

> Maintained by Claude. Updated whenever a new scene is created or significantly restructured.

---

## res://scenes/main.tscn

- **Root:** `Main` (Node2D)
- **Script:** `res://scripts/game/main.gd`
- **Key children:**
  - `Board` — instance of `board.tscn`, position `(324, 48)`
  - `HUD` — instance of `hud.tscn` (CanvasLayer)
- **Responsibility:** Orchestrates HUD signals → autoload calls. Handles board taps, 180° screen flip Tween (0.4s), and `_awaiting_discard_confirm` guard for Discard & Pass flow.

---

## res://scenes/board/board.tscn

- **Root:** `Board` (Node2D)
- **Script:** `res://scripts/board/board.gd`
- **Responsibility:** Draws 8×8 checkerboard via `_draw()`. Manages pawn visual nodes (Dictionary `board_pos → Node2D`). Handles mouse/touch input. Highlights move/attack cells.
- **Signals emitted:** `board_cell_tapped(cell: Vector2i)`

---

## res://scenes/pieces/pawn.tscn

- **Root:** `Pawn` (Node2D)
- **Script:** `res://scripts/pieces/pawn.gd`
- **Responsibility:** Visual pawn — draws filled circle + optional selection ring via `_draw()`. Call `select()` / `deselect()` to toggle ring.

---

## res://scenes/cards/card.tscn

- **Root:** `Card` (Button)
- **Script:** `res://scripts/cards/card_ui.gd`
- **Min size:** 100×80px
- **Responsibility:** Single card widget. Call `setup(index, type, face_down)` after instantiate. Emits `card_selected(index)` on press.
- **Signals emitted:** `card_selected(index: int)`
- **Note:** Always instantiate via `_card_scene.instantiate()` with untyped variable — do NOT type as `Button` or `setup()` call will fail at runtime.

---

## res://scenes/ui/hud.tscn

- **Root:** `HUD` (CanvasLayer)
- **Script:** `res://scripts/ui/hud.gd`
- **Node tree:**
  ```
  HUD (CanvasLayer)
  ├── TopBar (HBoxContainer)        anchor: top-wide, h=48px
  │   ├── TurnLabel (Label)
  │   └── TopHand (HBoxContainer)   inactive player face-down cards
  ├── BottomBar (HBoxContainer)     anchor: bottom-wide, h=96px
  │   ├── BottomHand (HBoxContainer) active player cards
  │   ├── DoneBtn (Button)
  │   ├── DiscardPassBtn (Button)
  │   └── ConfirmBtn (Button)
  ├── DicePanel (PanelContainer)    anchor: center, visible=false
  │   └── DiceLabel (Label)
  ├── DefensePanel (PanelContainer) anchor: center, visible=false
  │   └── VBox (VBoxContainer)
  │       ├── Title (Label)
  │       ├── DefenseHand (HBoxContainer)
  │       └── PassBtn (Button)
  └── TurnOverlay (PanelContainer)  anchor: center, visible=false
      └── Label
  ```
- **Responsibility:** Subscribes to TurnManager/CardSystem/GameManager signals. Rebuilds card hands. Shows/hides panels contextually.
- **Signals emitted:** `card_played_by_ui`, `discard_pass_requested`, `defense_chosen`, `movement_done_requested`, `turn_end_confirmed`
