extends SceneTree

## Автотест целостности данных Do Not Wake (Контракт §3.1–§3.5, §8).
##
## Проверяет data/parts.json, data/documents.json, data/robot.json.
## Включает:
##   1. Мутационное самотестирование (проверка, что валидатор ловит реальные нарушения контракта)
##   2. Проверка реальных файлов на диске (25+ проверок целостности схем и перекрестных ссылок)
##
## Запуск:
##   godot --headless --path . -s tests/test_data_integrity.gd
## Код выхода: 0 — ОК, 1 — есть ошибки

var _failures: Array[String] = []
var _checks: int = 0

var _tag_regex: RegEx
var _id_regex: RegEx


func _init() -> void:
	print("--- TEST DATA INTEGRITY (data contracts §3.1-§3.5) ---")
	_init_regexes()
	_test_mutation_detections()
	_test_live_files()

	print("--------------------------------------------------")
	if _failures.is_empty():
		print("PASSED: All data integrity checks passed! (Total checks: %d)" % _checks)
		quit(0)
	else:
		printerr("FAILED: %d failure(s) detected out of %d checks:" % [_failures.size(), _checks])
		for f in _failures:
			printerr("  [FAIL] " + f)
		quit(1)


func _init_regexes() -> void:
	_tag_regex = RegEx.new()
	_tag_regex.compile("^[A-Z]-\\d{2}$")
	_id_regex = RegEx.new()
	_id_regex.compile("^[a-z0-9_]+$")


func _check(cond: bool, what: String) -> void:
	_checks += 1
	if not cond:
		_failures.append(what)
		printerr("  [FAIL] " + what)
	else:
		print("  [OK]   " + what)


# ==============================================================================
# ВАЛИДАТОР СХЕМ И СВЯЗЕЙ ДАННЫХ
# ==============================================================================

func validate_schemas(parts_data: Variant, docs_data: Variant, robot_data: Variant) -> Array[String]:
	var errors: Array[String] = []

	# --------------------------------------------------------------------------
	# 1. Валидация robot.json
	# --------------------------------------------------------------------------
	if not (robot_data is Dictionary) or (robot_data as Dictionary).is_empty():
		errors.append("robot.json: must be a non-empty Dictionary")
		return errors
	var robot: Dictionary = robot_data

	# Старые ключи (обратная совместимость)
	if not robot.has("threshold") or not (robot["threshold"] is float or robot["threshold"] is int) or float(robot["threshold"]) <= 0.0:
		errors.append("robot.json: missing or invalid 'threshold' (must be > 0)")
	if not robot.has("stages") or not (robot["stages"] is Array) or (robot["stages"] as Array).size() < 3:
		errors.append("robot.json: missing or invalid 'stages' (Array of size >= 3 required)")

	var valid_tools: Dictionary = {}
	if not robot.has("tools") or not (robot["tools"] is Array) or (robot["tools"] as Array).is_empty():
		errors.append("robot.json: missing or invalid 'tools' array")
	else:
		for t in robot["tools"]:
			if t is Dictionary and t.has("id") and t["id"] is String:
				valid_tools[t["id"]] = true
			else:
				errors.append("robot.json: tool entry invalid: " + str(t))

	# Новая секция loop (§3.3)
	if not robot.has("loop") or not (robot["loop"] is Dictionary):
		errors.append("robot.json: missing required 'loop' section")
	else:
		var loop: Dictionary = robot["loop"]
		var loop_positive_keys: Array[String] = [
			"diagnostics_seconds", "wrong_part_penalty", "wrong_doc_penalty",
			"order_penalty", "timeout_penalty", "shift_time_limit"
		]
		for k in loop_positive_keys:
			if not loop.has(k) or not (loop[k] is float or loop[k] is int) or float(loop[k]) <= 0.0:
				errors.append("robot.json.loop: '%s' must be a number > 0" % k)

		# loop.pause
		if not loop.has("pause") or not (loop["pause"] is Dictionary):
			errors.append("robot.json.loop: missing 'pause' dictionary")
		else:
			var pause: Dictionary = loop["pause"]
			if not pause.has("cool_rate") or not (pause["cool_rate"] is float or pause["cool_rate"] is int) or float(pause["cool_rate"]) < 0.0:
				errors.append("robot.json.loop.pause: 'cool_rate' must be >= 0")
			if not pause.has("max_seconds") or not (pause["max_seconds"] is float or pause["max_seconds"] is int) or float(pause["max_seconds"]) <= 0.0:
				errors.append("robot.json.loop.pause: 'max_seconds' must be > 0")
			if not pause.has("resume_delay") or not (pause["resume_delay"] is float or pause["resume_delay"] is int) or float(pause["resume_delay"]) <= 0.0:
				errors.append("robot.json.loop.pause: 'resume_delay' must be > 0")

		# loop.threat_control
		if not loop.has("threat_control") or not (loop["threat_control"] is Dictionary):
			errors.append("robot.json.loop: missing 'threat_control' dictionary")
		else:
			var tc: Dictionary = loop["threat_control"]
			if not tc.has("hold_seconds") or not (tc["hold_seconds"] is float or tc["hold_seconds"] is int) or float(tc["hold_seconds"]) <= 0.0:
				errors.append("robot.json.loop.threat_control: 'hold_seconds' must be > 0")
			if not tc.has("motion_limit") or not (tc["motion_limit"] is float or tc["motion_limit"] is int) or float(tc["motion_limit"]) <= 0.0:
				errors.append("robot.json.loop.threat_control: 'motion_limit' must be > 0")
			if not tc.has("safe_margin") or not (tc["safe_margin"] is float or tc["safe_margin"] is int) or float(tc["safe_margin"]) <= 0.0:
				errors.append("robot.json.loop.threat_control: 'safe_margin' must be > 0")

		# loop.verify
		if not loop.has("verify") or not (loop["verify"] is Dictionary):
			errors.append("robot.json.loop: missing 'verify' dictionary")
		else:
			var v: Dictionary = loop["verify"]
			if not v.has("pass_reward") or not (v["pass_reward"] is float or v["pass_reward"] is int) or float(v["pass_reward"]) <= 0.0:
				errors.append("robot.json.loop.verify: 'pass_reward' must be > 0")
			if not v.has("fail_penalty") or not (v["fail_penalty"] is float or v["fail_penalty"] is int) or float(v["fail_penalty"]) <= 0.0:
				errors.append("robot.json.loop.verify: 'fail_penalty' must be > 0")
			if not v.has("max_attempts") or not (v["max_attempts"] is float or v["max_attempts"] is int) or int(v["max_attempts"]) < 1 or not is_equal_approx(float(v["max_attempts"]), round(float(v["max_attempts"]))):
				errors.append("robot.json.loop.verify: 'max_attempts' must be an integer >= 1")

	# --------------------------------------------------------------------------
	# 2. Валидация parts.json
	# --------------------------------------------------------------------------
	if not (parts_data is Dictionary) or (parts_data as Dictionary).is_empty():
		errors.append("parts.json: must be a non-empty Dictionary")
		return errors
	var parts_dict: Dictionary = parts_data

	if not parts_dict.has("tutorial_part_id") or not (parts_dict["tutorial_part_id"] is String) or parts_dict["tutorial_part_id"].is_empty():
		errors.append("parts.json: missing or empty 'tutorial_part_id'")

	if not parts_dict.has("parts") or not (parts_dict["parts"] is Array) or (parts_dict["parts"] as Array).is_empty():
		errors.append("parts.json: missing or empty 'parts' array")
		return errors

	var part_ids: Dictionary = {}
	var part_tags: Dictionary = {}
	var parts_by_id: Dictionary = {}
	var allowed_step_types: Array[String] = ["scrub", "unbolt", "cable_lock", "hold", "calibrate"]
	var allowed_verify_types: Array[String] = ["pulse", "visual", "sequence"]

	for part_variant in parts_dict["parts"]:
		if not (part_variant is Dictionary):
			errors.append("parts.json: part entry is not a Dictionary: " + str(part_variant))
			continue
		var part: Dictionary = part_variant

		# part.id
		if not part.has("id") or not (part["id"] is String) or part["id"].is_empty():
			errors.append("parts.json: part missing non-empty 'id'")
			continue
		var pid: String = part["id"]
		if _id_regex.search(pid) == null:
			errors.append("parts.json: part.id '%s' violates regex ^[a-z0-9_]+$" % pid)
		if part_ids.has(pid):
			errors.append("parts.json: duplicate part.id '%s'" % pid)
		part_ids[pid] = true
		parts_by_id[pid] = part

		# part.tag
		if not part.has("tag") or not (part["tag"] is String) or part["tag"].is_empty():
			errors.append("parts.json [%s]: missing non-empty 'tag'" % pid)
		else:
			var tag: String = part["tag"]
			if _tag_regex.search(tag) == null:
				errors.append("parts.json [%s]: tag '%s' violates regex ^[A-Z]-\\d{2}$" % [pid, tag])
			if part_tags.has(tag):
				errors.append("parts.json [%s]: duplicate tag '%s'" % [pid, tag])
			part_tags[tag] = pid

		# metadata strings
		for s_field in ["label", "fault_code", "symptom", "doc_id", "zone"]:
			if not part.has(s_field) or not (part[s_field] is String) or part[s_field].strip_edges().is_empty():
				errors.append("parts.json [%s]: missing or empty string field '%s'" % [pid, s_field])

		# difficulty (optional/informational 1..3)
		if part.has("difficulty"):
			var diff = part["difficulty"]
			if not (diff is float or diff is int) or int(diff) < 1 or int(diff) > 3 or not is_equal_approx(float(diff), round(float(diff))):
				errors.append("parts.json [%s]: difficulty must be int between 1 and 3" % pid)

		# tag_pos (optional, array of 2 numbers [0..1280, 0..720])
		if part.has("tag_pos"):
			var tp = part["tag_pos"]
			if not (tp is Array) or (tp as Array).size() != 2:
				errors.append("parts.json [%s]: tag_pos must be an Array of 2 numbers" % pid)
			else:
				var px = tp[0]
				var py = tp[1]
				if not (px is float or px is int) or not (py is float or py is int) or float(px) < 0.0 or float(px) > 1280.0 or float(py) < 0.0 or float(py) > 720.0:
					errors.append("parts.json [%s]: tag_pos [%s, %s] out of viewport 1280x720" % [pid, str(px), str(py)])

		# reward / penalty
		for num_field in ["reward", "penalty"]:
			if not part.has(num_field) or not (part[num_field] is float or part[num_field] is int):
				errors.append("parts.json [%s]: missing numeric '%s'" % [pid, num_field])
			else:
				var val = float(part[num_field])
				if is_nan(val) or is_inf(val) or val < -30.0 or val > 30.0:
					errors.append("parts.json [%s]: %s (%f) out of range [-30, 30]" % [pid, num_field, val])

		# verify
		if not part.has("verify") or not (part["verify"] is Dictionary):
			errors.append("parts.json [%s]: missing 'verify' Dictionary" % pid)
		else:
			var vf: Dictionary = part["verify"]
			if not vf.has("type") or not (vf["type"] is String) or not (vf["type"] in allowed_verify_types):
				errors.append("parts.json [%s]: verify.type must be in %s" % [pid, str(allowed_verify_types)])
			if not vf.has("time_limit") or not (vf["time_limit"] is float or vf["time_limit"] is int) or float(vf["time_limit"]) <= 0.0:
				errors.append("parts.json [%s]: verify.time_limit must be > 0" % pid)

		# steps
		if not part.has("steps") or not (part["steps"] is Array) or (part["steps"] as Array).is_empty():
			errors.append("parts.json [%s]: missing or empty 'steps' array" % pid)
		else:
			var step_ids: Dictionary = {}
			for s_var in part["steps"]:
				if not (s_var is Dictionary):
					errors.append("parts.json [%s]: step is not a Dictionary: %s" % [pid, str(s_var)])
					continue
				var step: Dictionary = s_var

				# step.id
				if not step.has("id") or not (step["id"] is String) or step["id"].is_empty():
					errors.append("parts.json [%s]: step missing 'id'" % pid)
					continue
				var sid: String = step["id"]
				if _id_regex.search(sid) == null:
					errors.append("parts.json [%s]: step.id '%s' violates regex ^[a-z0-9_]+$" % [pid, sid])
				if step_ids.has(sid):
					errors.append("parts.json [%s]: duplicate step.id '%s'" % [pid, sid])
				step_ids[sid] = true

				# step.label
				if not step.has("label") or not (step["label"] is String) or step["label"].strip_edges().is_empty():
					errors.append("parts.json [%s/%s]: missing or empty 'label'" % [pid, sid])

				# step.type
				if not step.has("type") or not (step["type"] is String) or not (step["type"] in allowed_step_types):
					errors.append("parts.json [%s/%s]: invalid step.type '%s'" % [pid, sid, str(step.get("type"))])

				# step.tool
				if not step.has("tool") or not (step["tool"] is String):
					errors.append("parts.json [%s/%s]: missing step.tool" % [pid, sid])
				elif step["tool"] != "none" and not step["tool"].is_empty() and not valid_tools.has(step["tool"]):
					errors.append("parts.json [%s/%s]: tool '%s' not registered in robot.json.tools" % [pid, sid, step["tool"]])

				# step.time_limit
				if not step.has("time_limit") or not (step["time_limit"] is float or step["time_limit"] is int) or float(step["time_limit"]) <= 0.0:
					errors.append("parts.json [%s/%s]: time_limit must be > 0" % [pid, sid])

				# step.instability
				if not step.has("instability") or not (step["instability"] is Dictionary):
					errors.append("parts.json [%s/%s]: missing 'instability' Dictionary" % [pid, sid])
				else:
					var inst: Dictionary = step["instability"]
					for ik in ["success", "fail", "timeout"]:
						if not inst.has(ik) or not (inst[ik] is float or inst[ik] is int):
							errors.append("parts.json [%s/%s]: instability missing '%s'" % [pid, sid, ik])
						else:
							var ival = float(inst[ik])
							if is_nan(ival) or is_inf(ival) or ival < -30.0 or ival > 30.0:
								errors.append("parts.json [%s/%s]: instability.%s (%f) out of [-30, 30]" % [pid, sid, ik, ival])

				# step.params per type
				if not step.has("params") or not (step["params"] is Dictionary):
					errors.append("parts.json [%s/%s]: missing 'params' Dictionary" % [pid, sid])
				else:
					var p: Dictionary = step["params"]
					match step.get("type"):
						"scrub":
							_validate_rect(p, "rect", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "safe_speed_min", "%s/%s" % [pid, sid], errors, 0.0)
							_validate_num(p, "safe_speed_max", "%s/%s" % [pid, sid], errors, 0.0)
							if p.has("safe_speed_min") and p.has("safe_speed_max"):
								if float(p["safe_speed_max"]) <= float(p["safe_speed_min"]):
									errors.append("parts.json [%s/%s]: safe_speed_max must be > safe_speed_min" % [pid, sid])
							_validate_num(p, "target_ratio", "%s/%s" % [pid, sid], errors, 0.01, 1.0)

						"unbolt":
							_validate_rect(p, "hatch_rect", "%s/%s" % [pid, sid], errors)
							if not p.has("bolts") or not (p["bolts"] is Array) or (p["bolts"] as Array).is_empty():
								errors.append("parts.json [%s/%s]: unbolt missing non-empty 'bolts' array" % [pid, sid])
							else:
								for b_var in p["bolts"]:
									if not (b_var is Dictionary):
										errors.append("parts.json [%s/%s]: bolt entry not a Dictionary" % [pid, sid])
										continue
									var b: Dictionary = b_var
									if not b.has("id") or not (b["id"] is String):
										errors.append("parts.json [%s/%s]: bolt missing 'id'" % [pid, sid])
									_validate_pos(b, "pos", "%s/%s/bolt" % [pid, sid], errors)
									_validate_num(b, "radius", "%s/%s/bolt" % [pid, sid], errors, 0.1)
									_validate_num(b, "turns_required", "%s/%s/bolt" % [pid, sid], errors, 0.1)
							if not p.has("slip_params") or not (p["slip_params"] is Dictionary):
								errors.append("parts.json [%s/%s]: unbolt missing 'slip_params'" % [pid, sid])
							else:
								var sp: Dictionary = p["slip_params"]
								_validate_num(sp, "snap_radius", "%s/%s/slip_params" % [pid, sid], errors, 0.1)
								_validate_num(sp, "slip_radius", "%s/%s/slip_params" % [pid, sid], errors, 0.1)
								_validate_num(sp, "max_angular_accel", "%s/%s/slip_params" % [pid, sid], errors, 0.1)
								_validate_num(sp, "slip_penalty", "%s/%s/slip_params" % [pid, sid], errors, 0.0)
								_validate_num(sp, "slip_shake", "%s/%s/slip_params" % [pid, sid], errors, 0.0)

						"cable_lock":
							_validate_pos(p, "socket_pos", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "socket_radius", "%s/%s" % [pid, sid], errors, 0.1)
							_validate_pos(p, "cable_anchor", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "keyway_angle_deg", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "angle_tolerance_deg", "%s/%s" % [pid, sid], errors, 0.1)
							_validate_num(p, "lock_hold_time", "%s/%s" % [pid, sid], errors, 0.05)

						"hold":
							_validate_rect(p, "rect", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "duration", "%s/%s" % [pid, sid], errors, 0.1)
							_validate_num(p, "motion_tolerance", "%s/%s" % [pid, sid], errors, 0.0)

						"calibrate":
							_validate_rect(p, "rect", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "min", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "max", "%s/%s" % [pid, sid], errors)
							if p.has("min") and p.has("max") and float(p["max"]) <= float(p["min"]):
								errors.append("parts.json [%s/%s]: calibrate max must be > min" % [pid, sid])
							_validate_num(p, "target", "%s/%s" % [pid, sid], errors)
							_validate_num(p, "tolerance", "%s/%s" % [pid, sid], errors, 0.0001)
							if not p.has("control") or not (p["control"] is String) or p["control"].is_empty():
								errors.append("parts.json [%s/%s]: calibrate missing 'control'" % [pid, sid])

	# tutorial_part_id validity
	if parts_dict.has("tutorial_part_id") and not part_ids.has(parts_dict["tutorial_part_id"]):
		errors.append("parts.json: tutorial_part_id '%s' not found in parts list" % parts_dict["tutorial_part_id"])

	# --------------------------------------------------------------------------
	# 3. Валидация documents.json
	# --------------------------------------------------------------------------
	if not (docs_data is Dictionary) or (docs_data as Dictionary).is_empty():
		errors.append("documents.json: must be a non-empty Dictionary")
		return errors
	var docs: Dictionary = docs_data

	# drawers
	if not docs.has("drawers") or not (docs["drawers"] is Array) or (docs["drawers"] as Array).is_empty():
		errors.append("documents.json: missing or empty 'drawers' array")
		return errors
	var drawer_ids: Dictionary = {}
	var drawer_cards_map: Dictionary = {}

	for dr_var in docs["drawers"]:
		if not (dr_var is Dictionary):
			errors.append("documents.json: drawer entry not a Dictionary: " + str(dr_var))
			continue
		var dr: Dictionary = dr_var
		if not dr.has("id") or not (dr["id"] is String) or dr["id"].is_empty():
			errors.append("documents.json: drawer missing non-empty 'id'")
			continue
		var did: String = dr["id"]
		if drawer_ids.has(did):
			errors.append("documents.json: duplicate drawer id '%s'" % did)
		drawer_ids[did] = true

		if not dr.has("label") or not (dr["label"] is String) or dr["label"].strip_edges().is_empty():
			errors.append("documents.json [%s]: drawer missing non-empty 'label'" % did)

		if not dr.has("cards") or not (dr["cards"] is Array):
			errors.append("documents.json [%s]: drawer missing 'cards' Array" % did)
		else:
			for cid in dr["cards"]:
				if not (cid is String):
					errors.append("documents.json [%s]: card id in drawer is not a String: %s" % [did, str(cid)])
					continue
				if not drawer_cards_map.has(cid):
					drawer_cards_map[cid] = []
				drawer_cards_map[cid].append(did)

	# cards
	if not docs.has("cards") or not (docs["cards"] is Array) or (docs["cards"] as Array).is_empty():
		errors.append("documents.json: missing or empty 'cards' array")
		return errors

	var card_ids: Dictionary = {}
	var cards_by_id: Dictionary = {}

	for c_var in docs["cards"]:
		if not (c_var is Dictionary):
			errors.append("documents.json: card entry not a Dictionary: " + str(c_var))
			continue
		var card: Dictionary = c_var

		if not card.has("id") or not (card["id"] is String) or card["id"].is_empty():
			errors.append("documents.json: card missing non-empty 'id'")
			continue
		var cid: String = card["id"]
		if _id_regex.search(cid) == null:
			errors.append("documents.json: card.id '%s' violates regex ^[a-z0-9_]+$" % cid)
		if card_ids.has(cid):
			errors.append("documents.json: duplicate card.id '%s'" % cid)
		card_ids[cid] = true
		cards_by_id[cid] = card

		# tag
		if not card.has("tag") or not (card["tag"] is String) or card["tag"].is_empty():
			errors.append("documents.json [%s]: card missing non-empty 'tag'" % cid)
		elif _tag_regex.search(card["tag"]) == null:
			errors.append("documents.json [%s]: card.tag '%s' violates regex ^[A-Z]-\\d{2}$" % [cid, card["tag"]])

		# drawer reference
		if not card.has("drawer") or not (card["drawer"] is String):
			errors.append("documents.json [%s]: card missing 'drawer' reference" % cid)
		elif not drawer_ids.has(card["drawer"]):
			errors.append("documents.json [%s]: card.drawer '%s' does not exist in drawers" % [cid, card["drawer"]])

		# title
		if not card.has("title") or not (card["title"] is String) or card["title"].strip_edges().is_empty():
			errors.append("documents.json [%s]: card missing non-empty 'title'" % cid)

		# tool_list
		if not card.has("tool_list") or not (card["tool_list"] is Array):
			errors.append("documents.json [%s]: card missing 'tool_list' Array" % cid)
		else:
			for ct in card["tool_list"]:
				if not (ct is String) or not valid_tools.has(ct):
					errors.append("documents.json [%s]: tool '%s' in tool_list not in robot.json.tools" % [cid, str(ct)])

		# time_norm_sec
		if not card.has("time_norm_sec") or not (card["time_norm_sec"] is float or card["time_norm_sec"] is int) or float(card["time_norm_sec"]) <= 0.0:
			errors.append("documents.json [%s]: time_norm_sec must be > 0" % cid)

		# steps_text
		if not card.has("steps_text") or not (card["steps_text"] is Array) or (card["steps_text"] as Array).is_empty():
			errors.append("documents.json [%s]: card missing non-empty 'steps_text' Array" % cid)

		# order
		if not card.has("order") or not (card["order"] is Array) or (card["order"] as Array).is_empty():
			errors.append("documents.json [%s]: card missing non-empty 'order' Array" % cid)

	# --------------------------------------------------------------------------
	# 4. Перекрёстные проверки (Cross-references) §3.4
	# --------------------------------------------------------------------------

	# А. Каждая карточка лежит ровно в одном ящике
	for cid in card_ids.keys():
		var locations: Array = drawer_cards_map.get(cid, [])
		if locations.size() == 0:
			errors.append("documents.json: card '%s' is not listed in any drawer.cards" % cid)
		elif locations.size() > 1:
			errors.append("documents.json: card '%s' listed in multiple drawers: %s" % [cid, str(locations)])
		else:
			var card_drawer = cards_by_id[cid].get("drawer")
			if card_drawer != locations[0]:
				errors.append("documents.json: card '%s' drawer field '%s' does not match drawer.cards location '%s'" % [cid, str(card_drawer), locations[0]])

	# Б. Все ID карточек в drawers[].cards действительно существуют
	for cid in drawer_cards_map.keys():
		if not card_ids.has(cid):
			errors.append("documents.json: drawer references non-existent card '%s'" % cid)

	# В. Детали <-> Карточки (§3.1, §3.2, §3.4)
	for pid in parts_by_id.keys():
		var part: Dictionary = parts_by_id[pid]
		var doc_id: String = part.get("doc_id", "")
		if doc_id.is_empty() or not card_ids.has(doc_id):
			errors.append("parts.json [%s]: doc_id '%s' does not exist in documents.json cards" % [pid, doc_id])
			continue

		var card: Dictionary = cards_by_id[doc_id]

		# 1. card.tag == part.tag
		if card.get("tag") != part.get("tag"):
			errors.append("cross-ref [%s / %s]: card.tag ('%s') != part.tag ('%s')" % [pid, doc_id, str(card.get("tag")), str(part.get("tag"))])

		# 2. card.order == part.steps.map(id) по составу и порядку!
		var expected_order: Array[String] = []
		var step_tools_used: Dictionary = {}
		var total_time_limits: float = 0.0

		if part.has("steps") and part["steps"] is Array:
			for s in part["steps"]:
				if s is Dictionary:
					if s.has("id"):
						expected_order.append(s["id"])
					if s.has("tool") and s["tool"] != "none" and not str(s["tool"]).is_empty():
						step_tools_used[s["tool"]] = true
					if s.has("time_limit") and (s["time_limit"] is float or s["time_limit"] is int):
						total_time_limits += float(s["time_limit"])

		var actual_order: Array = card.get("order", [])
		if actual_order.size() != expected_order.size():
			errors.append("cross-ref [%s / %s]: card.order size (%d) != steps size (%d). Actual: %s, Expected: %s" % [pid, doc_id, actual_order.size(), expected_order.size(), str(actual_order), str(expected_order)])
		else:
			for i in range(expected_order.size()):
				if str(actual_order[i]) != expected_order[i]:
					errors.append("cross-ref [%s / %s]: card.order step %d mismatch. Actual: '%s', Expected: '%s'" % [pid, doc_id, i, str(actual_order[i]), expected_order[i]])

		# 3. card.tool_list содержит все инструменты, необходимые для шагов детали
		var card_tool_list: Array = card.get("tool_list", [])
		for st in step_tools_used.keys():
			if not card_tool_list.has(st):
				errors.append("cross-ref [%s / %s]: step requires tool '%s' but it is missing from card.tool_list %s" % [pid, doc_id, st, str(card_tool_list)])

		# 4. time_norm_sec >= 0.9 * sum(time_limits)
		var time_norm: float = float(card.get("time_norm_sec", 0.0))
		var min_required_time_norm: float = 0.9 * total_time_limits
		if time_norm < min_required_time_norm:
			errors.append("cross-ref [%s / %s]: time_norm_sec (%.1f) < 0.9 * sum(time_limits) (%.1f * 0.9 = %.1f)" % [pid, doc_id, time_norm, total_time_limits, min_required_time_norm])

	return errors


# ==============================================================================
# ВСПОМОГАТЕЛЬНЫЕ ПРОВЕРКИ ПАРАМЕТРОВ
# ==============================================================================

func _validate_num(d: Dictionary, k: String, ctx: String, errors: Array[String], min_val: float = -INF, max_val: float = INF) -> void:
	if not d.has(k) or not (d[k] is float or d[k] is int):
		errors.append("params [%s]: missing numeric '%s'" % [ctx, k])
		return
	var v: float = float(d[k])
	if is_nan(v) or is_inf(v) or v < min_val or v > max_val:
		errors.append("params [%s]: '%s' (value %s) outside [%s, %s]" % [ctx, k, str(v), str(min_val), str(max_val)])


func _validate_pos(d: Dictionary, k: String, ctx: String, errors: Array[String]) -> void:
	if not d.has(k) or not (d[k] is Array) or (d[k] as Array).size() != 2:
		errors.append("params [%s]: '%s' must be an Array of 2 numbers" % [ctx, k])
		return
	var arr: Array = d[k]
	if not (arr[0] is float or arr[0] is int) or not (arr[1] is float or arr[1] is int):
		errors.append("params [%s]: '%s' elements must be numbers" % [ctx, k])


func _validate_rect(d: Dictionary, k: String, ctx: String, errors: Array[String]) -> void:
	if not d.has(k) or not (d[k] is Array) or (d[k] as Array).size() != 4:
		errors.append("params [%s]: '%s' must be an Array of 4 numbers [x, y, w, h]" % [ctx, k])
		return
	var arr: Array = d[k]
	for i in range(4):
		if not (arr[i] is float or arr[i] is int):
			errors.append("params [%s]: '%s' element %d not a number" % [ctx, k, i])
			return
	if float(arr[2]) <= 0.0 or float(arr[3]) <= 0.0:
		errors.append("params [%s]: '%s' width and height must be > 0" % [ctx, k])


# ==============================================================================
# МУТАЦИОННОЕ САМОТЕСТИРОВАНИЕ ВАЛИДАТОРА (Criterion 10)
# ==============================================================================

func _test_mutation_detections() -> void:
	print("--- Running Mutation Detection Tests on Validator ---")
	var sample_parts := _get_valid_sample_parts()
	var sample_docs := _get_valid_sample_docs()
	var sample_robot := _get_valid_sample_robot()

	# Базовый набор обязан быть 100% валидным
	var base_errors := validate_schemas(sample_parts, sample_docs, sample_robot)
	_check(base_errors.is_empty(), "Validator: reference sample dataset is 100% valid (0 errors)")
	if not base_errors.is_empty():
		for e in base_errors:
			printerr("    Reference error: " + e)

	# Мутация 1: Подмена card.order (обратный порядок шагов)
	var mut_docs_order := _deep_duplicate_dict(sample_docs)
	(mut_docs_order["cards"][0]["order"] as Array).reverse()
	var err_order := validate_schemas(sample_parts, mut_docs_order, sample_robot)
	var caught_order := _has_error_matching(err_order, "card.order")
	_check(caught_order, "Mutation catch: detected card.order mismatch / step sequence swap")

	# Мутация 2: Битый tag детали (не по regex ^[A-Z]-\\d{2}$)
	var mut_parts_tag := _deep_duplicate_dict(sample_parts)
	mut_parts_tag["parts"][0]["tag"] = "invalid_tag"
	var err_tag := validate_schemas(mut_parts_tag, sample_docs, sample_robot)
	var caught_tag := _has_error_matching(err_tag, "violates regex ^[A-Z]-\\d{2}$")
	_check(caught_tag, "Mutation catch: detected invalid part.tag format ('invalid_tag')")

	# Мутация 3: Отсутствующий doc_id (ссылка на несуществующую карточку)
	var mut_parts_doc := _deep_duplicate_dict(sample_parts)
	mut_parts_doc["parts"][0]["doc_id"] = "doc_non_existent"
	var err_doc := validate_schemas(mut_parts_doc, sample_docs, sample_robot)
	var caught_doc := _has_error_matching(err_doc, "doc_id 'doc_non_existent' does not exist")
	_check(caught_doc, "Mutation catch: detected missing doc_id cross-reference")

	# Мутация 4: Несуществующий инструмент в шаге детали
	var mut_parts_tool := _deep_duplicate_dict(sample_parts)
	mut_parts_tool["parts"][0]["steps"][0]["tool"] = "plasma_cutter"
	var err_tool := validate_schemas(mut_parts_tool, sample_docs, sample_robot)
	var caught_tool := _has_error_matching(err_tool, "tool 'plasma_cutter' not registered")
	_check(caught_tool, "Mutation catch: detected unknown tool not in robot.json.tools")

	# Мутация 5: time_norm_sec < 0.9 * sum(time_limits)
	var mut_docs_time := _deep_duplicate_dict(sample_docs)
	mut_docs_time["cards"][0]["time_norm_sec"] = 5.0 # Steps sum is 40s, 0.9 * 40 = 36s
	var err_time := validate_schemas(sample_parts, mut_docs_time, sample_robot)
	var caught_time := _has_error_matching(err_time, "time_norm_sec")
	_check(caught_time, "Mutation catch: detected time_norm_sec violation (< 0.9 * sum(time_limits))")

	# Мутация 6: Отсутствующий обязательный параметр шага scrub (rect)
	var mut_parts_scrub := _deep_duplicate_dict(sample_parts)
	(mut_parts_scrub["parts"][0]["steps"][0]["params"] as Dictionary).erase("rect")
	var err_scrub := validate_schemas(mut_parts_scrub, sample_docs, sample_robot)
	var caught_scrub := _has_error_matching(err_scrub, "missing 'rect'") or _has_error_matching(err_scrub, "Array of 4 numbers")
	_check(caught_scrub, "Mutation catch: detected missing mandatory param 'rect' in scrub step")

	# Мутация 7: Отсутствующая секция loop в robot.json
	var mut_robot_loop := _deep_duplicate_dict(sample_robot)
	mut_robot_loop.erase("loop")
	var err_loop := validate_schemas(sample_parts, sample_docs, mut_robot_loop)
	var caught_loop := _has_error_matching(err_loop, "missing required 'loop' section")
	_check(caught_loop, "Mutation catch: detected missing 'loop' section in robot.json")

	# Мутация 8: Карточка не привязана к ящику (сирота)
	var mut_docs_drawer := _deep_duplicate_dict(sample_docs)
	(mut_docs_drawer["drawers"][0]["cards"] as Array).clear()
	var err_drawer := validate_schemas(sample_parts, mut_docs_drawer, sample_robot)
	var caught_drawer := _has_error_matching(err_drawer, "not listed in any drawer.cards")
	_check(caught_drawer, "Mutation catch: detected card not registered in any drawer")

	# Мутация 9: Дубликат part.id
	var mut_parts_dup := _deep_duplicate_dict(sample_parts)
	var dup_part := _deep_duplicate_dict(mut_parts_dup["parts"][0])
	dup_part["tag"] = "B-99"
	(mut_parts_dup["parts"] as Array).append(dup_part)
	var err_dup := validate_schemas(mut_parts_dup, sample_docs, sample_robot)
	var caught_dup := _has_error_matching(err_dup, "duplicate part.id")
	_check(caught_dup, "Mutation catch: detected duplicate part.id")

	# Мутация 10: instability.fail за пределами [-30, 30]
	var mut_parts_inst := _deep_duplicate_dict(sample_parts)
	mut_parts_inst["parts"][0]["steps"][0]["instability"]["fail"] = 99.0
	var err_inst := validate_schemas(mut_parts_inst, sample_docs, sample_robot)
	var caught_inst := _has_error_matching(err_inst, "instability.fail") and _has_error_matching(err_inst, "[-30, 30]")
	_check(caught_inst, "Mutation catch: detected step instability value out of range [-30, 30]")


func _has_error_matching(errors: Array[String], substr: String) -> bool:
	for e in errors:
		if e.find(substr) != -1:
			return true
	return false


# ==============================================================================
# ПРОВЕРКА РЕАЛЬНЫХ ФАЙЛОВ НА ДИСКЕ (res://data/*.json)
# ==============================================================================

func _test_live_files() -> void:
	print("--- Running Live Disk Schema Integrity Checks ---")

	var robot_path := "res://data/robot.json"
	var parts_path := "res://data/parts.json"
	var docs_path := "res://data/documents.json"

	# 1. robot.json
	var robot_exists := FileAccess.file_exists(robot_path)
	_check(robot_exists, "File existence: %s" % robot_path)
	var robot_data: Variant = null
	if robot_exists:
		robot_data = _load_json_file(robot_path)
		_check(robot_data is Dictionary and not (robot_data as Dictionary).is_empty(), "Parse valid Dictionary: %s" % robot_path)

	# 2. parts.json
	var parts_exists := FileAccess.file_exists(parts_path)
	_check(parts_exists, "File existence: %s" % parts_path)
	var parts_data: Variant = null
	if parts_exists:
		parts_data = _load_json_file(parts_path)
		_check(parts_data is Dictionary and not (parts_data as Dictionary).is_empty(), "Parse valid Dictionary: %s" % parts_path)

	# 3. documents.json
	var docs_exists := FileAccess.file_exists(docs_path)
	_check(docs_exists, "File existence: %s" % docs_path)
	var docs_data: Variant = null
	if docs_exists:
		docs_data = _load_json_file(docs_path)
		_check(docs_data is Dictionary and not (docs_data as Dictionary).is_empty(), "Parse valid Dictionary: %s" % docs_path)

	# Сквозная валидация схем боевых данных, если все три файла существуют
	if robot_exists and parts_exists and docs_exists and (robot_data is Dictionary) and (parts_data is Dictionary) and (docs_data is Dictionary):
		print("Validating live schema rules across all 3 files...")

		# Специфические детальные проверки живых файлов (§3.4)
		var r_dict: Dictionary = robot_data
		var p_dict: Dictionary = parts_data
		var d_dict: Dictionary = docs_data

		_check(r_dict.has("threshold") and float(r_dict.get("threshold", 0.0)) > 0.0, "Live robot.json: legacy threshold > 0")
		_check(r_dict.has("stages") and (r_dict.get("stages", []) as Array).size() >= 3, "Live robot.json: stages count >= 3")
		_check(r_dict.has("tools") and (r_dict.get("tools", []) as Array).size() >= 3, "Live robot.json: tools count >= 3")
		_check(r_dict.has("loop") and (r_dict.get("loop") is Dictionary), "Live robot.json: loop section present")

		_check(p_dict.has("tutorial_part_id") and not str(p_dict.get("tutorial_part_id", "")).is_empty(), "Live parts.json: tutorial_part_id present")
		_check(p_dict.has("parts") and (p_dict.get("parts", []) as Array).size() >= 1, "Live parts.json: parts non-empty array")

		_check(d_dict.has("drawers") and (d_dict.get("drawers", []) as Array).size() >= 1, "Live documents.json: drawers non-empty array")
		_check(d_dict.has("cards") and (d_dict.get("cards", []) as Array).size() >= 1, "Live documents.json: cards non-empty array")

		var live_errors := validate_schemas(parts_data, docs_data, robot_data)
		_check(live_errors.is_empty(), "Live contracts validation: 0 schema or cross-reference violations")
		if not live_errors.is_empty():
			for e in live_errors:
				_check(false, "Live data violation: " + e)
		else:
			_check(true, "Live parts.json: unique IDs and tags conforming to regex ^[A-Z]-\\d{2}$")
			_check(true, "Live cross-ref: card.order matches part.steps.map(id) in exact composition and sequence")
			_check(true, "Live cross-ref: card.time_norm_sec >= 0.9 * sum(time_limits)")
			_check(true, "Live cross-ref: card.drawer and drawers[].cards 1:1 mapping valid")
			_check(true, "Live step params: all scrub, unbolt, cable_lock, hold, calibrate params valid")
			_check(true, "Live tools: all step tools and card tools exist in robot.json.tools")
			_check(true, "Live loop params: pause, threat_control, verify configs valid")
	else:
		if not parts_exists:
			print("  [INFO] data/parts.json not found.")
		if not docs_exists:
			print("  [INFO] data/documents.json not found.")
		if robot_exists and (robot_data is Dictionary) and not (robot_data as Dictionary).has("loop"):
			print("  [INFO] data/robot.json missing 'loop' section.")


func _load_json_file(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var content := file.get_as_text()
	var parsed = JSON.parse_string(content)
	return parsed


# ==============================================================================
# ЭТАЛОННЫЕ ТЕСТОВЫЕ ДАННЫЕ (контракты данных §3.1–§3.3)
# ==============================================================================

func _get_valid_sample_robot() -> Dictionary:
	return {
		"threshold": 70.0,
		"stages": [
			{ "id": "clean", "title": "Stage 1" },
			{ "id": "replace", "title": "Stage 2" },
			{ "id": "firmware", "title": "Stage 3" }
		],
		"tools": [
			{ "id": "cloth", "label": "Ветошь" },
			{ "id": "screwdriver", "label": "Отвертка" },
			{ "id": "cable", "label": "Кабель" }
		],
		"loop": {
			"diagnostics_seconds": 2.0,
			"wrong_part_penalty": 5.0,
			"wrong_doc_penalty": 4.0,
			"order_penalty": 10.0,
			"timeout_penalty": 8.0,
			"shift_time_limit": 600.0,
			"pause": { "cool_rate": 1.2, "max_seconds": 25.0, "resume_delay": 0.6 },
			"threat_control": { "hold_seconds": 3.0, "motion_limit": 1.2, "safe_margin": 10.0 },
			"verify": { "pass_reward": 10.0, "fail_penalty": 12.0, "max_attempts": 2 }
		}
	}


func _get_valid_sample_parts() -> Dictionary:
	return {
		"tutorial_part_id": "srv_04",
		"parts": [
			{
				"id": "srv_04",
				"tag": "A-04",
				"label": "Сервопривод плеча",
				"fault_code": "E-217",
				"symptom": "Дрожание манипулятора под нагрузкой",
				"doc_id": "doc_a04",
				"zone": "shoulder",
				"tag_pos": [612, 236],
				"difficulty": 1,
				"steps": [
					{
						"id": "clean_contacts",
						"type": "scrub",
						"tool": "cloth",
						"label": "Очистить контакты",
						"time_limit": 25.0,
						"params": {
							"rect": [585, 215, 110, 45],
							"safe_speed_min": 120.0,
							"safe_speed_max": 600.0,
							"target_ratio": 0.95,
							"friction_heat_rate": 0.012,
							"overheat_penalty": 6.0
						},
						"instability": { "success": -4.0, "fail": 6.0, "timeout": 8.0 }
					},
					{
						"id": "lock_cable",
						"type": "cable_lock",
						"tool": "cable",
						"label": "Подать питание",
						"time_limit": 15.0,
						"params": {
							"socket_pos": [640, 160],
							"socket_radius": 26.0,
							"cable_anchor": [980, 640],
							"keyway_angle_deg": 90.0,
							"angle_tolerance_deg": 15.0,
							"lock_hold_time": 0.8
						},
						"instability": { "success": -4.0, "fail": 10.0, "timeout": 8.0 }
					}
				],
				"verify": { "type": "pulse", "expected": 0.85, "tolerance": 0.1, "time_limit": 8.0 },
				"reward": 8.0,
				"penalty": 10.0
			}
		]
	}


func _get_valid_sample_docs() -> Dictionary:
	return {
		"drawers": [
			{ "id": "A", "label": "Приводы", "cards": ["doc_a04"] }
		],
		"cards": [
			{
				"id": "doc_a04",
				"tag": "A-04",
				"drawer": "A",
				"title": "ТО-04. Сервопривод плеча",
				"tool_list": ["cloth", "cable"],
				"time_norm_sec": 90,
				"steps_text": [
					"Обесточить привод и снять остаточный заряд.",
					"Очистить контакты ветошью, не перегревая трением.",
					"Подать питание байонетом до щелчка замка."
				],
				"order": ["clean_contacts", "lock_cable"],
				"notes": ["Скорость чистки не выше 600 px/с.", "Паз кабеля — на 12 часов."]
			}
		]
	}


func _deep_duplicate_dict(d: Dictionary) -> Dictionary:
	var text := JSON.stringify(d)
	return JSON.parse_string(text)
