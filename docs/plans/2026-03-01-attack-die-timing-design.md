# Attack Die Timing — Design

**Date:** 2026-03-01

## Goal

Roll the attack die AFTER the defender decides whether to play a Defense card, not before showing the DefensePanel.

## Current flow (broken)
1. Attacker + target selected → `on_attack_declared()` rolls die → `defense_requested(ap, dp, roll, label)` emitted
2. DefensePanel shows "Defend? (ATK=12)"
3. Defender decides → `on_defense_resolved()` resolves with already-known attack roll

## New flow
1. Attacker + target selected → `on_attack_declared()` stores die_sides, does NOT roll → `defense_requested(ap, dp, die_sides)` emitted
2. DefensePanel shows "Defend? (Attack: 1dN)"
3. Defender decides → `on_defense_resolved()` rolls attack die first, then defense die if applicable, resolves

## Changes

### `turn_manager.gd`
- Signal `defense_requested(attacker_pos, defender_pos, attack_roll, die_label)` → `defense_requested(attacker_pos, defender_pos, attacker_die_sides)`
- `on_attack_declared()`: remove `DiceRoller.roll()` call; store `die_sides` in `pending_attack`; emit `defense_requested(ap, dp, die_sides)`
- `on_defense_resolved()`: add `var attack_roll := DiceRoller.roll(pending_attack["die_sides"])` at the start; rest unchanged

### `hud.gd`
- `_on_defense_requested(_ap, _dp, die_sides)`: change title to `"Player %d - Defend? (Attack: 1d%d)" % [defender, die_sides]`
- Remove `_show_dice(die_label, attack_roll)` call (no roll yet to show)
