# Selective Discard — Design

**Date:** 2026-03-01
**Status:** Approved

## Feature

When a player presses "Discard & Pass", instead of discarding all 4 cards automatically, they can select which cards to discard (1–4) and draw that same number.

## UX Flow

1. Player presses "Discard & Pass" → HUD enters **discard mode**
2. Active hand cards become toggle-selectable: tap = mark/unmark for discard (highlighted vs dimmed)
3. "Confirm Discard (N)" button appears dynamically when ≥1 card is selected
4. "Cancel" button always visible in discard mode
5. **Cancel** → exit discard mode, return to normal PLAY_CARD state, no changes
6. **Confirm** → `CardSystem.selective_discard(player, indices)` discards N chosen cards, draws N → `TurnManager.on_discard_and_pass()` → phase END → flip

## Code Changes

### `res://scripts/cards/card_system.gd`

Add `selective_discard(player: int, indices: Array[int]) -> void`:
- Sort indices descending to avoid index shifting during removal
- Discard selected cards, draw same count
- Emit `hand_changed`

### `res://scripts/ui/hud.gd`

- Add `_discard_mode: bool = false`
- Add `_selected_discard: Array[int] = []`
- Add `_cancel_discard_btn: Button` (programmatic node, like `play_card_btn`)
- `_on_discard_pass_btn_pressed()` → activates discard mode instead of emitting signal
- `_on_hand_card_tapped(idx)` → in discard mode: toggle idx in `_selected_discard`, update card visuals and confirm button text
- `_on_confirm_btn_pressed()` → in discard mode: calls `CardSystem.selective_discard`, then emits `discard_pass_requested` for main.gd to handle turn end
- `_on_cancel_discard_btn_pressed()` → exits discard mode, restores normal PLAY_CARD buttons
- `_set_all_action_buttons_hidden()` → also hides `_cancel_discard_btn`

### `res://scripts/game/main.gd`

- `_on_discard_pass_requested` → remove `hud.show_discard_preview()` call; `show_discard_preview` step is no longer needed since confirm is part of discard mode
- Remove `_awaiting_discard_confirm` flag and related `_on_turn_end_confirmed` handler (confirm button repurposed for discard mode)

### `res://scripts/game/turn_manager.gd`

No changes — `on_discard_and_pass()` and phase END flow remain identical.

## What Does NOT Change

- `discard_and_refill` remains in CardSystem (may be used elsewhere)
- Board flip animation and turn transition logic unchanged
- History panel entry for discard/pass unchanged
