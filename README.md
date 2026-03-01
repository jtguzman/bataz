# Bataz

A 2D turn-based strategy board game built with Godot 4.

> **Development stack:** [Godot 4.6](https://godotengine.org/) · [Claude Code](https://claude.ai/claude-code) · [Godot MCP Server](https://github.com/Coding-Crashkurse/godot-mcp)

---

## Overview

Bataz is a card-driven tactical game played on a chessboard. Two players each control 8 pawns and use a shared deck of cards to move, attack, and defend. The last player with pawns on the board wins.

---

## How to Play

### Setup

- **Board:** Standard 8×8 chessboard.
- **Pawns:** Each player places 8 pawns on their starting rows.
- **Deck:** 30 cards shared between both players — 10 Movement, 10 Attack, 10 Defense.
- **Starting hand:** Each player draws 4 cards.

---

### Turn Structure

1. Play 1 card from your hand.
2. Resolve the card's effect.
3. Draw 1 card to return to 4 cards in hand.

Used cards go to a **discard pile**. When the draw pile is empty, the discard pile is shuffled and becomes the new draw pile.

---

### Card Types

#### Movement Card

- Roll **1d4**.
- Distribute the result as movement points among any of your pawns (any combination).
- Pawns move like a **chess king** — one square in any direction (orthogonal or diagonal).
- A single pawn can use multiple movement points in one turn.

#### Attack Card

- Can only be played when one of your pawns is **adjacent** (orthogonal or diagonal) to an enemy pawn.
- **Before rolling**, the attacking player must declare:
  - Which of their pawns is attacking.
  - Which enemy pawn is being attacked.
- The attack die is determined by the number of **friendly pawns adjacent** to the attacking pawn:

| Adjacent allies | Attack die |
|:-:|:-:|
| 0 | 1d4 |
| 1 | 1d6 |
| 2 | 1d8 |
| 3 | 1d10 |
| 4 | 1d12 |
| 5+ | 1d20 |

- The attack is successful if the attack roll **exceeds** the defense roll (or the defender plays no Defense card).
- A successful attack **removes** the defending pawn from the board.

#### Defense Card

- Played **reactively** by the defending player when their pawn is attacked.
- The defense die is determined by the number of **friendly pawns adjacent** to the defending pawn:

| Adjacent allies | Defense die |
|:-:|:-:|
| 0 | 1d4 |
| 1 | 1d6 |
| 2 | 1d8 |
| 3 | 1d10 |
| 4 | 1d12 |
| 5+ | 1d20 |

- **Defense succeeds** if the defense roll is **equal to or greater than** the attack roll — the defending pawn survives.
- When a Defense card is played:
  - At the end of the attacker's turn, **both** the attacker and the defender each draw 1 card.
  - Both players start the next turn with 4 cards in hand.

---

### Win Condition

A player loses when all of their pawns have been eliminated. The last player with pawns remaining wins.

---

## Project Structure

```
bataz/
├── addons/
│   └── godot_mcp/       # Godot MCP Server plugin (AI-assisted development)
├── icon.svg
└── project.godot
```

---

## Development

This project is developed using **Claude Code** with the **Godot MCP Server** plugin, which allows Claude to interact directly with the Godot editor — reading the scene tree, creating nodes, writing scripts, and more.

### Requirements

- Godot 4.6+
- [Claude Code](https://claude.ai/claude-code)
- [Godot MCP Server](https://github.com/Coding-Crashkurse/godot-mcp) (included as a plugin)

### Getting Started

1. Open the project in Godot 4.6+.
2. Enable the **Godot MCP** plugin under `Project > Project Settings > Plugins`.
3. Open Claude Code in the project directory.
4. Connect Claude Code to the Godot MCP server.
