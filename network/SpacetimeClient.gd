# res://network/SpacetimeClient.gd
# GDScript WebSocket client for SpacetimeDB (v1.json.spacetimedb protocol).
# Drop-in replacement for SpacetimeClient.ts — same signals, same public API.
# Attach to res://scenes/network/spacetime_client.tscn
extends Node

# ── Configuration ─────────────────────────────────────────────────────────────
const _MAINCLOUD_WS   := "wss://maincloud.spacetimedb.com"
const _LOCAL_WS       := "ws://localhost:3000"
const _MAINCLOUD_HTTP := "https://maincloud.spacetimedb.com"
const _LOCAL_HTTP     := "http://localhost:3000"
const _MODULE         := "bataz"
const _TOKEN_PATH     := "user://network_token.txt"
const _USE_LOCAL      := false  # flip to true for local SpacetimeDB testing

# ── Signals ───────────────────────────────────────────────────────────────────
signal connected
signal disconnected
signal game_created(game_id: int, join_code: String)
signal game_joined(game_id: int)
signal join_failed(reason: String)
signal placement_phase_started(player: int)
signal game_state_updated(state_dict: Dictionary)
signal board_sync(pawns_array: Array)
signal pawn_moved(from_col: int, from_row: int, to_col: int, to_row: int)
signal pawn_removed(col: int, row: int, team: int)
signal hand_updated(player: int, hand_array: Array)
signal attack_declared(data_dict: Dictionary)
signal movement_rolled(points: int)
signal game_over(winner: int)
signal event_logged(text: String)

# ── State ─────────────────────────────────────────────────────────────────────
var _ws          := WebSocketPeer.new()
var _active      := false   # true after connect_to_server() called
var _was_open    := false   # tracks STATE_OPEN→STATE_CLOSED for disconnect signal
var _my_identity := ""
var _token       := ""
var _game_id     := -1
var _last_game   : Dictionary = {}
var _pawns       : Dictionary = {}   # pawn_id:int → row dict
var _hand_cache  : Dictionary = {}   # "gameId_player_slotIndex" → row dict

# ── Lifecycle ─────────────────────────────────────────────────────────────────
func _process(_delta: float) -> void:
	if not _active:
		return
	_ws.poll()
	match _ws.get_ready_state():
		WebSocketPeer.STATE_OPEN:
			_was_open = true
			while _ws.get_available_packet_count() > 0:
				var pkt := _ws.get_packet().get_string_from_utf8()
				var msg  = JSON.parse_string(pkt)
				if msg is Dictionary:
					_on_ws_message(msg)
		WebSocketPeer.STATE_CLOSED:
			if _was_open:
				_was_open = false
				_active   = false
				disconnected.emit()

# ── Public: connection ────────────────────────────────────────────────────────
func connect_to_server() -> void:
	_token = _load_token()
	_ws.supported_protocols = PackedStringArray(["v1.json.spacetimedb"])
	if _token != "":
		_ws.handshake_headers = PackedStringArray(["Authorization: Bearer " + _token])
	var base := _LOCAL_WS if _USE_LOCAL else _MAINCLOUD_WS
	var err  := _ws.connect_to_url("%s/v1/database/%s/subscribe" % [base, _MODULE])
	if err != OK:
		push_error("[SpacetimeClient] connect_to_url error %d" % err)
		disconnected.emit()
		return
	_active = true

# ── Public: lobby ─────────────────────────────────────────────────────────────
func create_game() -> void:                                _call_reducer("CreateGame", [])
func join_game(code: String) -> void:                      _call_reducer("JoinGame", [code])

# ── Public: placement ─────────────────────────────────────────────────────────
func place_pawn(gid: int, col: int, row: int) -> void:            _call_reducer("PlacePawn", [gid, col, row])
func remove_placement_pawn(gid: int, col: int, row: int) -> void: _call_reducer("RemovePlacementPawn", [gid, col, row])
func confirm_placement(gid: int) -> void:                         _call_reducer("ConfirmPlacement", [gid])

# ── Public: gameplay ──────────────────────────────────────────────────────────
func play_card(gid: int, slot: int) -> void:                       _call_reducer("PlayCard", [gid, slot])
func discard_and_pass(gid: int) -> void:                           _call_reducer("DiscardAndPass", [gid])
func move_pawn(gid: int, fc: int, fr: int, tc: int, tr: int) -> void: _call_reducer("MovePawn", [gid, fc, fr, tc, tr])
func done_moving(gid: int) -> void:                                _call_reducer("DoneMoving", [gid])
func declare_attack(gid: int, ac: int, ar: int, dc: int, dr: int) -> void: _call_reducer("DeclareAttack", [gid, ac, ar, dc, dr])
func play_defense(gid: int, slot: int) -> void:                    _call_reducer("PlayDefense", [gid, slot])
func pass_defense(gid: int) -> void:                               _call_reducer("PassDefense", [gid])
func end_turn(gid: int) -> void:                                   _call_reducer("EndTurn", [gid])

# ── Public: utility ───────────────────────────────────────────────────────────
func get_my_player_slot() -> int:
	if _my_identity.is_empty() or _last_game.is_empty():
		return 0
	if str(_last_game.get("player1", "")) == _my_identity:
		return 1
	if str(_last_game.get("player2", "")) == _my_identity:
		return 2
	return 0

func get_game_id() -> int:
	return _game_id

# ── WebSocket message dispatch ────────────────────────────────────────────────
func _on_ws_message(msg: Dictionary) -> void:
	if   msg.has("IdentityToken"):       _on_identity_token(msg["IdentityToken"])
	elif msg.has("InitialSubscription"):
		var db: Dictionary = msg["InitialSubscription"].get("database_update", {})
		_process_tables(db.get("tables", []))
	elif msg.has("TransactionUpdate"):
		var tu: Dictionary = msg["TransactionUpdate"]
		var st: Dictionary = tu.get("status", {})
		if st.has("Committed"):
			_process_tables(st["Committed"].get("tables", []))
		elif st.has("Failed"):
			var err_msg := str(st["Failed"].get("message", ""))
			var reducer := str((tu.get("reducerCall", {}) as Dictionary).get("reducerName", ""))
			push_warning("[SpacetimeClient] %s failed: %s" % [reducer, err_msg])
			if reducer in ["CreateGame", "JoinGame"]:
				join_failed.emit("%s failed: %s" % [reducer, err_msg])

func _on_identity_token(data: Dictionary) -> void:
	_my_identity = str(data.get("identity", ""))
	var tok := str(data.get("token", ""))
	if tok != "":
		_token = tok
		_save_token(tok)
	# Subscribe to all game tables
	_ws.send_text(JSON.stringify({
		"Subscribe": {
			"query_strings": [
				"SELECT * FROM game",
				"SELECT * FROM pawn",
				"SELECT * FROM card_hand",
				"SELECT * FROM pending_attack",
				"SELECT * FROM event_log",
			],
			"request_id": 1,
		}
	}))
	connected.emit()

func _process_tables(tables: Array) -> void:
	for t in tables:
		_apply_table(str(t.get("table_name", "")), t.get("deletes", []), t.get("inserts", []))

# ── Table change dispatch ─────────────────────────────────────────────────────
func _apply_table(table: String, dels: Array, ins: Array) -> void:
	match table:
		"game":           _apply_game(dels, ins)
		"pawn":           _apply_pawn(dels, ins)
		"card_hand":      _apply_card_hand(dels, ins)
		"pending_attack": _apply_pending_attack(ins)
		"event_log":
			for r in ins:
				if _mine(r):
					event_logged.emit(str(r.get("text", "")))

func _mine(row: Dictionary) -> bool:
	return int(row.get("gameId", -1)) == _game_id

# ── game ──────────────────────────────────────────────────────────────────────
func _apply_game(dels: Array, ins: Array) -> void:
	var old_by_id: Dictionary = {}
	for r in dels:
		old_by_id[int(r.get("gameId", -1))] = r
	for r in ins:
		var gid := int(r.get("gameId", -1))
		if old_by_id.has(gid):
			_on_game_update(old_by_id[gid], r)
		else:
			_on_game_insert(r)

func _on_game_insert(row: Dictionary) -> void:
	# Only care if I'm player1 of this new game
	if str(row.get("player1", "")) == _my_identity:
		_game_id   = int(row["gameId"])
		_last_game = row
		game_created.emit(_game_id, str(row.get("joinCode", "")))

func _on_game_update(old: Dictionary, new: Dictionary) -> void:
	var gid        := int(new.get("gameId",  -1))
	var prev_state := str(old.get("state",   ""))
	var next_state := str(new.get("state",   ""))
	var prev_phase := str(old.get("phase",   ""))
	var next_phase := str(new.get("phase",   ""))

	# WAITING → PLACEMENT_P1 means player2 just joined
	if prev_state == "WAITING" and next_state == "PLACEMENT_P1":
		if _game_id == -1 and str(new.get("player2", "")) == _my_identity:
			# I'm player2 — record game and signal lobby
			_game_id   = gid
			_last_game = new
			game_joined.emit(_game_id)
			placement_phase_started.emit(1)
			return
		elif _game_id == gid:
			# I'm player1 — opponent arrived
			_last_game = new
			game_joined.emit(_game_id)
			placement_phase_started.emit(1)
			return

	if gid != _game_id:
		return
	_last_game = new

	if next_state == "PLACEMENT_P2" and prev_state != "PLACEMENT_P2":
		placement_phase_started.emit(2)

	if next_phase == "RESOLVE_MOVEMENT" and prev_phase != "RESOLVE_MOVEMENT":
		movement_rolled.emit(int(new.get("movementPoints", 0)))

	if next_state == "GAME_OVER" and prev_state != "GAME_OVER":
		game_over.emit(int(new.get("winner", 0)))

	# Always emit state update so HUD + TurnManager stay in sync
	game_state_updated.emit({
		"current_player":  int(new.get("currentPlayer",  1)),
		"phase":           str(new.get("phase",          "PLAY_CARD")),
		"movement_points": int(new.get("movementPoints", 0)),
		"state":           str(new.get("state",          "PLAYING")),
		"winner":          int(new.get("winner",         0)),
	})

# ── pawn ──────────────────────────────────────────────────────────────────────
func _apply_pawn(dels: Array, ins: Array) -> void:
	var old_by_id: Dictionary = {}
	for r in dels:
		old_by_id[int(r.get("pawnId", -1))] = r
	for r in ins:
		var pid := int(r.get("pawnId", -1))
		if old_by_id.has(pid):
			_on_pawn_update(old_by_id[pid], r)
			old_by_id.erase(pid)
		else:
			_on_pawn_insert(r)
	for r in old_by_id.values():
		_on_pawn_delete(r)

func _on_pawn_insert(row: Dictionary) -> void:
	if not _mine(row):
		return
	_pawns[int(row["pawnId"])] = row
	_try_board_sync()

func _on_pawn_update(old: Dictionary, new: Dictionary) -> void:
	if not _mine(new):
		return
	_pawns[int(new["pawnId"])] = new
	# placed false→true: all pawns are now on the board
	if not bool(old.get("placed", false)) and bool(new.get("placed", false)):
		_try_board_sync()
		return
	# Position changed: pawn moved during gameplay
	if old.get("col") != new.get("col") or old.get("row") != new.get("row"):
		pawn_moved.emit(int(old["col"]), int(old["row"]), int(new["col"]), int(new["row"]))

func _on_pawn_delete(row: Dictionary) -> void:
	if not _mine(row):
		return
	_pawns.erase(int(row["pawnId"]))
	pawn_removed.emit(int(row["col"]), int(row["row"]), int(row["team"]))

func _try_board_sync() -> void:
	if _game_id == -1:
		return
	var all: Array = _pawns.values().filter(func(p: Dictionary) -> bool: return _mine(p))
	if all.size() != 16:
		return
	if not all.all(func(p: Dictionary) -> bool: return bool(p.get("placed", false))):
		return
	board_sync.emit(all.map(func(p: Dictionary) -> Dictionary:
		return {"col": int(p["col"]), "row": int(p["row"]),
				"team": int(p["team"]), "pawn_id": int(p["pawnId"])}))

# ── card_hand ─────────────────────────────────────────────────────────────────
func _apply_card_hand(dels: Array, ins: Array) -> void:
	var changed: Dictionary = {}
	for r in dels:
		if not _mine(r):
			continue
		_hand_cache.erase(_hkey(r))
		changed[int(r["player"])] = true
	for r in ins:
		if not _mine(r):
			continue
		_hand_cache[_hkey(r)] = r
		changed[int(r["player"])] = true
	for p in changed:
		_emit_hand(p)

func _hkey(r: Dictionary) -> String:
	return "%d_%d_%d" % [int(r.get("gameId", 0)), int(r.get("player", 0)), int(r.get("slotIndex", 0))]

func _emit_hand(player: int) -> void:
	var rows: Array = _hand_cache.values().filter(
		func(r: Dictionary) -> bool: return _mine(r) and int(r.get("player", -1)) == player)
	rows.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("slotIndex", 0)) < int(b.get("slotIndex", 0)))
	hand_updated.emit(player, rows.map(func(r: Dictionary) -> String:
		return str(r.get("cardType", "MOVEMENT"))))

# ── pending_attack ────────────────────────────────────────────────────────────
func _apply_pending_attack(ins: Array) -> void:
	for r in ins:
		if not _mine(r):
			continue
		attack_declared.emit({
			"attacker_col": int(r["attackerCol"]), "attacker_row": int(r["attackerRow"]),
			"defender_col": int(r["defenderCol"]), "defender_row": int(r["defenderRow"]),
			"attack_roll":  int(r["attackRoll"]),  "die_sides":    int(r["dieSides"]),
			"die_label":    str(r["dieLabel"]),
		})

# ── HTTP reducer call ─────────────────────────────────────────────────────────
func _call_reducer(reducer: String, args: Array) -> void:
	var http := HTTPRequest.new()
	add_child(http)
	http.request_completed.connect(
		func(_res: int, code: int, _hdrs: PackedStringArray, _body: PackedByteArray) -> void:
			if code < 200 or code >= 300:
				push_warning("[SpacetimeClient] %s → HTTP %d" % [reducer, code])
				if reducer in ["CreateGame", "JoinGame"]:
					join_failed.emit("%s failed (HTTP %d)" % [reducer, code])
			http.queue_free()
	)
	var base := _LOCAL_HTTP if _USE_LOCAL else _MAINCLOUD_HTTP
	var hdrs := PackedStringArray(["Content-Type: application/json"])
	if _token != "":
		hdrs.append("Authorization: Bearer " + _token)
	var err := http.request(
		"%s/v1/database/%s/call/%s" % [base, _MODULE, reducer],
		hdrs, HTTPClient.METHOD_POST, JSON.stringify(args))
	if err != OK:
		push_error("[SpacetimeClient] HTTPRequest error %d calling %s" % [err, reducer])
		http.queue_free()

# ── Token persistence ─────────────────────────────────────────────────────────
func _load_token() -> String:
	if not FileAccess.file_exists(_TOKEN_PATH):
		return ""
	var f := FileAccess.open(_TOKEN_PATH, FileAccess.READ)
	if f == null:
		return ""
	var t := f.get_as_text().strip_edges()
	f.close()
	return t

func _save_token(tok: String) -> void:
	var f := FileAccess.open(_TOKEN_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("[SpacetimeClient] Could not save token to " + _TOKEN_PATH)
		return
	f.store_string(tok)
	f.close()
