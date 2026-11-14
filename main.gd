extends Node2D

const ARENA := Rect2(52, 82, 1176, 586)
const PLAYER_SPEED := 220.0
const BOT_SPEED := 132.0
const HUNTER_SPEED := 118.0
const OBJECTIVE_RADIUS := 46.0
const INTERACT_RADIUS := 62.0

var survivor: Dictionary
var companions: Array[Dictionary] = []
var hunter: Dictionary
var objectives: Array[Dictionary] = []
var walls: Array[Rect2] = []
var gate := Rect2(1165, 300, 38, 144)
var escaped := false
var failed := false
var elapsed := 0.0
var capture_timer := 0.0
var message := "Find and ignite the three signal fires."

func _ready() -> void:
	reset_match()

func reset_match() -> void:
	survivor = {"pos": Vector2(128, 610), "down": false, "health": 100.0, "color": Color("8ee6c2")}
	companions = [
		{"pos": Vector2(205, 570), "down": false, "health": 100.0, "color": Color("b7b0ff"), "target": -1},
		{"pos": Vector2(140, 505), "down": false, "health": 100.0, "color": Color("f5b4ce"), "target": -1},
		{"pos": Vector2(290, 620), "down": false, "health": 100.0, "color": Color("f6d37a"), "target": -1}
	]
	hunter = {"pos": Vector2(1060, 145), "color": Color("e85d61"), "attack_cd": 0.0}
	objectives = [
		{"pos": Vector2(330, 188), "progress": 0.0, "lit": false},
		{"pos": Vector2(705, 530), "progress": 0.0, "lit": false},
		{"pos": Vector2(1055, 210), "progress": 0.0, "lit": false}
	]
	walls = [Rect2(250, 310, 190, 38), Rect2(560, 210, 44, 185), Rect2(780, 435, 235, 40), Rect2(925, 105, 42, 160), Rect2(90, 400, 145, 38)]
	escaped = false
	failed = false
	elapsed = 0.0
	capture_timer = 0.0
	message = "Find and ignite the three signal fires."
	queue_redraw()

func _process(delta: float) -> void:
	if Input.is_key_pressed(KEY_R) and (escaped or failed):
		reset_match()
		return
	if escaped or failed:
		queue_redraw()
		return
	elapsed += delta
	move_survivor(delta)
	update_companions(delta)
	update_hunter(delta)
	update_objectives(delta)
	check_outcome()
	queue_redraw()

func move_survivor(delta: float) -> void:
	if survivor.down:
		return
	var direction := Vector2.ZERO
	if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP): direction.y -= 1
	if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN): direction.y += 1
	if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT): direction.x -= 1
	if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT): direction.x += 1
	if direction.length_squared() > 0.0:
		survivor.pos = move_safely(survivor.pos, direction.normalized() * PLAYER_SPEED * delta)

func update_companions(delta: float) -> void:
	for bot in companions:
		if bot.down:
			continue
		var threat: float = bot.pos.distance_to(hunter.pos)
		var direction := Vector2.ZERO
		if threat < 165.0:
			direction = (bot.pos - hunter.pos).normalized()
		else:
			var index := nearest_unlit_objective(bot.pos)
			if index >= 0:
				bot.target = index
				direction = (objectives[index].pos - bot.pos).normalized()
		if direction.length_squared() > 0.0:
			bot.pos = move_safely(bot.pos, direction * BOT_SPEED * delta)

func update_hunter(delta: float) -> void:
	hunter.attack_cd = maxf(0.0, hunter.attack_cd - delta)
	var target := survivor
	var target_distance: float = INF
	if not survivor.down:
		target_distance = hunter.pos.distance_to(survivor.pos)
	for bot in companions:
		if not bot.down and hunter.pos.distance_to(bot.pos) < target_distance:
			target = bot
			target_distance = hunter.pos.distance_to(bot.pos)
	if target_distance < INF:
		hunter.pos = move_safely(hunter.pos, (target.pos - hunter.pos).normalized() * HUNTER_SPEED * delta)
		if target_distance < 29.0 and hunter.attack_cd <= 0.0:
			damage_target(target)
			hunter.attack_cd = 1.15

func damage_target(target: Dictionary) -> void:
	target.health -= 34.0
	if target.health <= 0.0:
		target.down = true
		if target == survivor:
			message = "You are down. Stay alive while the team finishes the signal."

func update_objectives(delta: float) -> void:
	var active_index := nearest_unlit_objective(survivor.pos)
	var interacting := Input.is_key_pressed(KEY_E) or Input.is_key_pressed(KEY_SPACE)
	if active_index >= 0 and survivor.pos.distance_to(objectives[active_index].pos) < INTERACT_RADIUS and interacting and not survivor.down:
		objectives[active_index].progress = minf(100.0, objectives[active_index].progress + 26.0 * delta)
		message = "Igniting signal: %d%%" % objectives[active_index].progress
	for objective in objectives:
		if objective.lit:
			continue
		for bot in companions:
			if not bot.down and bot.pos.distance_to(objective.pos) < OBJECTIVE_RADIUS:
				objective.progress = minf(100.0, objective.progress + 7.0 * delta)
		if objective.progress >= 100.0:
			objective.lit = true
			message = "A signal fire is lit."
	if all_objectives_lit():
		message = "Extraction gate powered. Reach the bright eastern gate."

func check_outcome() -> void:
	if survivor.down:
		capture_timer += get_process_delta_time()
		if capture_timer > 8.0:
			failed = true
			message = "The dark claimed you. Press R to try again."
	else:
		capture_timer = 0.0
	if all_objectives_lit() and gate.grow(18.0).has_point(survivor.pos):
		escaped = true
		message = "You escaped the night. Press R for another run."

func nearest_unlit_objective(from: Vector2) -> int:
	var best := -1
	var best_distance := INF
	for i in objectives.size():
		if not objectives[i].lit:
			var distance := from.distance_to(objectives[i].pos)
			if distance < best_distance:
				best_distance = distance
				best = i
	return best

func all_objectives_lit() -> bool:
	for objective in objectives:
		if not objective.lit:
			return false
	return true

func move_safely(from: Vector2, movement: Vector2) -> Vector2:
	var result := (from + movement).clamp(ARENA.position + Vector2(13, 13), ARENA.end - Vector2(13, 13))
	for wall in walls:
		if wall.grow(12.0).has_point(result):
			return from
	return result

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(1280, 720)), Color("091011"))
	draw_rect(ARENA, Color("152123"), true)
	draw_rect(ARENA, Color("395052"), false, 2.0)
	for x in range(80, 1210, 74):
		for y in range(110, 650, 67):
			draw_circle(Vector2(x, y), 2.0, Color("29393a"))
	for wall in walls:
		draw_rect(wall, Color("344345"), true)
		draw_rect(wall, Color("6a7770"), false, 1.0)
	for objective in objectives:
		var flame_color := Color("ffbd55") if objective.lit else Color("405554")
		draw_circle(objective.pos, OBJECTIVE_RADIUS, Color(flame_color, 0.12))
		draw_circle(objective.pos, 15.0, flame_color)
		draw_rect(Rect2(objective.pos + Vector2(-25, 26), Vector2(50, 6)), Color("091011"), true)
		draw_rect(Rect2(objective.pos + Vector2(-25, 26), Vector2(objective.progress * 0.5, 6)), flame_color, true)
	var gate_color := Color("7ef2d1") if all_objectives_lit() else Color("384c4c")
	draw_rect(gate, gate_color, true)
	draw_rect(gate.grow(4.0), Color("b2fff0") if all_objectives_lit() else Color("526565"), false, 2.0)
	draw_agent(hunter.pos, hunter.color, "H")
	for bot in companions:
		draw_agent(bot.pos, Color("5d6267") if bot.down else bot.color, "x" if bot.down else "C")
	draw_agent(survivor.pos, Color("5d6267") if survivor.down else survivor.color, "x" if survivor.down else "Y")
	draw_hud()

func draw_agent(position: Vector2, color: Color, label: String) -> void:
	draw_circle(position, 13.0, Color("071011"))
	draw_circle(position, 10.0, color)
	draw_string(ThemeDB.fallback_font, position + Vector2(-4, 5), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color("071011"))

func draw_hud() -> void:
	draw_rect(Rect2(0, 0, 1280, 63), Color("0a1516e8"), true)
	draw_string(ThemeDB.fallback_font, Vector2(28, 28), "DARK ESCAPE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("d7fff2"))
	var lit_count := 0
	for objective in objectives:
		if objective.lit: lit_count += 1
	draw_string(ThemeDB.fallback_font, Vector2(28, 52), "SIGNALS %d/3   HEALTH %d" % [lit_count, maxf(0, survivor.health)], HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color("9fbeb8"))
	draw_string(ThemeDB.fallback_font, Vector2(380, 38), message, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("ffdf99"))
	draw_string(ThemeDB.fallback_font, Vector2(850, 52), "WASD / ARROWS move    E or SPACE interact", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color("9fbeb8"))
	if escaped or failed:
		draw_rect(Rect2(280, 260, 720, 150), Color("071011e8"), true)
		var result := "ESCAPED" if escaped else "CAPTURED"
		var result_color := Color("82f6ce") if escaped else Color("ff7777")
		draw_string(ThemeDB.fallback_font, Vector2(520, 320), result, HORIZONTAL_ALIGNMENT_CENTER, 240, 34, result_color)
		draw_string(ThemeDB.fallback_font, Vector2(430, 365), "Press R to restart the match", HORIZONTAL_ALIGNMENT_CENTER, 420, 20, Color("d7fff2"))
