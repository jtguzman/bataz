# Progress & Roadmap

> Maintained by Claude. Updated at the end of every development session.
> `[x]` done · `[~]` in progress · `[ ]` pending

---

## Milestone 0 — Project Setup
- [x] Godot 4.6.1 project created
- [x] Godot MCP Pro plugin installed and connected
- [x] CLAUDE.md written
- [x] README.md written (full game rules)
- [x] Local docs structure created (`docs/`)

---

## Milestone 1 — Board
- [x] Create `scenes/board/board.tscn` (8×8 grid)
- [x] Visual board rendering (checkerboard colors #F0D9B5 / #B58863)
- [x] Pawn placement on starting rows (P1 rows 6-7, P2 rows 0-1)
- [x] Pawn selection and highlight of valid moves
- [x] Pawn visual (filled circle, selection ring)

---

## Milestone 2 — Turn System
- [x] TurnManager autoload (phase tracking, current_player)
- [x] Turn phases: PLAY_CARD → RESOLVE → DRAW → END
- [x] Screen flip 180° between turns (Main handles via Tween)
- [x] Discard & Pass flow with confirm preview

---

## Milestone 3 — Card System
- [x] Deck: 30 cards (10 Movement, 10 Attack, 10 Defense)
- [x] Shuffle and draw logic
- [x] Hand: 4 cards per player
- [x] Discard pile with reshuffle before draw when pile insufficient
- [x] Card UI: colored buttons (MOV=green, ATK=red, DEF=blue)

---

## Milestone 4 — Movement
- [x] Movement card: roll 1d4, distribute points among pawns
- [x] Pawn moves king-style (8 directions, 1 square)
- [x] Multi-step movement within one card play
- [x] Board boundary and occupied-cell validation

---

## Milestone 5 — Combat
- [x] Attack card: adjacency check, declare attacker + target
- [x] Attack die scaling by adjacent allies (1d4 → 1d20)
- [x] Defense card: reactive response during opponent's attack
- [x] Defense die scaling by adjacent allies
- [x] Success condition: defense roll ≥ attack roll
- [x] Pawn removal on failed defense
- [x] Post-combat card draw (attacker always; defender if card played)

---

## Milestone 6 — UI
- [x] Hand display (4 cards, touch-friendly 100×80px min)
- [x] Active player indicator (TurnLabel)
- [x] Dice roll result display (DicePanel, fades after 1.5s)
- [x] Attack/defense declaration UI (DefensePanel)
- [x] Win screen (TurnLabel shows "Player X Wins!")
- [x] Turn overlay ("Player X's Turn" during flip)
- [x] Turn history sidebar (card played, dice result, outcome per turn)
- [x] Dice roll overlay on board (die type + result, fades after 1.5s)
- [x] Draw/discard pile panel left of board (live card counts, last discard color)

---

## Milestone 7 — Polish & Platform
- [ ] Mobile touch input — touch events handled in board.gd (InputEventScreenTouch), needs real device test
- [ ] Screen scaling on portrait — untested
- [ ] Sound effects (dice roll, pawn remove, card play)
- [ ] Android export preset configured
- [ ] iOS export preset configured
- [ ] Tested on real mobile device

---

## Known Issues / Next Steps
- P2 face-down cards in TopBar appear compressed — cosmetic, no gameplay impact
- No sound effects yet (Milestone 7)
- Mobile not tested on real device yet
