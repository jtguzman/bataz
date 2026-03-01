# Attack Card UX — Design

**Date:** 2026-03-01
**Status:** Approved

## Feature

When a player selects an Attack card, they can tap their own pawn directly to confirm the card and select the attacker in one step. The card is not played until the enemy pawn is tapped. A Cancel button is available at any point before the enemy pawn is tapped and returns the card to the hand (full undo).

## UX Flow

1. Tap Attack card → card highlighted; **Cancel** button appears; "Play Card" does NOT appear. Phase stays `PLAY_CARD`. Card not played yet.
2. Tap own pawn (with valid attack targets) → pawn selected as attacker, enemy targets highlighted. Cancel still visible. Still `PLAY_CARD` phase. Card still not played.
3. Tap enemy pawn (target) → card played + attack declared in one step. Phase moves to `RESOLVE_DEFENSE`.
4. Tap **Cancel** (steps 1 or 2) → full reset: card deselected, attacker deselected, back to normal `PLAY_CARD` state. Card returned to hand (was never played).
5. Tap empty cell or own pawn without targets while attacker is selected → deselect attacker, keep card pending (player can pick a different pawn).

**Movement cards:** unchanged — "Play Card" button appears as before.

## Code Changes

### `hud.gd`

- New signal: `attack_card_pending(player: int, card_index: int)` — emitted when an Attack card is tapped (instead of showing "Play Card").
- In `_on_hand_card_tapped(idx)`:
  - If card type is `ATTACK`: set `_pending_card_index = idx`, emit `attack_card_pending`, show `_cancel_discard_btn` (text = "Cancel"), hide `play_card_btn`.
  - If card type is anything else (Movement): existing behavior unchanged.
- `_on_cancel_discard_btn_pressed()` already emits cancel for discard mode. We need to distinguish: if `_pending_card_index >= 0` and we're in PLAY_CARD phase (not discard mode) → emit new signal `attack_card_cancelled` (or reuse existing cancel path).
  - Actually: add a new `_cancel_attack_btn: Button` separate from `_cancel_discard_btn` to avoid conflating the two flows.
- New `_cancel_attack_btn: Button` (programmatic, same style as other buttons):
  - Shown when Attack card is pending (steps 1 and 2).
  - Pressed → emit `attack_card_cancelled`.
  - Hidden on reset.
- `_set_all_action_buttons_hidden()`: also hide `_cancel_attack_btn`.
- When `attack_card_pending` is emitted, main.gd owns the attacker selection state. HUD only handles card visual + cancel button visibility.

### `main.gd`

- New signal connection: `hud.attack_card_pending.connect(_on_attack_card_pending)`
- New signal connection: `hud.attack_card_cancelled.connect(_on_attack_card_cancelled)` (or reuse existing pattern)
- New vars:
  - `_pending_attack_card_index: int = -1`
  - `_pending_attacker_pos: Vector2i = Vector2i(-1, -1)`
- `_on_attack_card_pending(player: int, card_index: int)`:
  - Store `_pending_attack_card_index = card_index`
  - Clear `_pending_attacker_pos`
- `_on_attack_card_cancelled()`:
  - Reset `_pending_attack_card_index = -1` and `_pending_attacker_pos = Vector2i(-1, -1)`
  - `board.clear_highlights()`
- In `_on_board_cell_tapped`, under `PLAYING / PLAY_CARD`, add new branch when `_pending_attack_card_index >= 0`:
  ```
  if _pending_attacker_pos == Vector2i(-1, -1):
      # No attacker selected yet
      if cell has own pawn AND get_valid_attack_targets(cell) not empty:
          _pending_attacker_pos = cell
          board.set_selected(cell)
          board.highlight_attack_targets(get_valid_attack_targets(cell))
  else:
      # Attacker already selected
      if cell in get_valid_attack_targets(_pending_attacker_pos):
          # Play card + declare attack
          _execute_pending_attack(cell)
      elif cell has own pawn AND get_valid_attack_targets(cell) not empty:
          # Switch attacker
          _pending_attacker_pos = cell
          board.set_selected(cell)
          board.highlight_attack_targets(get_valid_attack_targets(cell))
      else:
          # Tap on empty / invalid cell — deselect attacker, keep card pending
          _pending_attacker_pos = Vector2i(-1, -1)
          board.clear_highlights()
  ```
- New `_execute_pending_attack(enemy_cell: Vector2i)`:
  - `CardSystem.play_card(TurnManager.current_player, _pending_attack_card_index)`
  - `TurnManager.on_card_played(CardType.Type.ATTACK)` — phase → RESOLVE_ATTACK
  - `var adjacent := GameManager.get_adjacent_allies(_pending_attacker_pos, TurnManager.current_player)`
  - `TurnManager.on_attack_declared(_pending_attacker_pos, enemy_cell, adjacent)`
  - Reset `_pending_attack_card_index = -1` and `_pending_attacker_pos = Vector2i(-1, -1)`
  - Hide `_cancel_attack_btn` via hud call or signal
- `_on_phase_changed` must also reset pending attack state (safety guard for phase transitions).
- `_on_card_played_by_ui` stays for Movement cards (unchanged).

## What Does NOT Change

- Movement card flow: "Play Card" button → tap to confirm → roll 1d4 → RESOLVE_MOVEMENT
- Defense card: reactive only, unchanged
- `TurnManager.on_attack_declared` signature and logic: unchanged
- `CardSystem.play_card` called directly (not via `card_played_by_ui` signal) for the attack path — history entry is still populated because `CardSystem.card_played` signal fires from `play_card`
