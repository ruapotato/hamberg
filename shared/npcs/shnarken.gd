extends Node3D
class_name Shnarken

## Shnarken - Snarky frog/toad shopkeeper NPC
## Lives in a giant boot hut, mocks players, sells gear and upgrades

signal interaction_requested(shnarken: Shnarken)

@export var shnarken_name: String = "Shnarken"
@export var biome_id: int = 1  # Which biome this Shnarken serves

# Visual components
var body_container: Node3D
var head: Node3D
var left_eye: MeshInstance3D
var right_eye: MeshInstance3D
var throat_pouch: MeshInstance3D

# Animation state
var idle_time: float = 0.0
var blink_timer: float = 0.0
var next_blink: float = 3.0
var is_blinking: bool = false
var throat_wobble: float = 0.0
var is_talking: bool = false

# Hopping movement
var home_position: Vector3 = Vector3.ZERO  # Center point to hop around
var hop_target: Vector3 = Vector3.ZERO  # Current hop destination
var is_hopping: bool = false
var hop_timer: float = 0.0
var next_hop_time: float = 2.0
var hop_progress: float = 0.0
var hop_start_pos: Vector3 = Vector3.ZERO
var hop_height: float = 0.5
var hop_duration: float = 0.4
var hop_radius: float = 4.0  # How far from home to hop

# Interaction
var player_nearby: bool = false
var interaction_area: Area3D

func _ready() -> void:
	_setup_body()
	_setup_interaction_area()
	# Set home position after a frame to get correct global position
	call_deferred("_initialize_hopping")

func _initialize_hopping() -> void:
	home_position = global_position
	hop_target = global_position
	next_hop_time = randf_range(1.0, 3.0)

func _process(delta: float) -> void:
	idle_time += delta
	_update_idle_animation(delta)
	_update_blink(delta)
	_update_hopping(delta)
	if is_talking:
		_update_throat_wobble(delta)

# =============================================================================
# BODY SETUP - Detailed Frog/Toad Merchant
# =============================================================================

func _setup_body() -> void:
	body_container = Node3D.new()
	body_container.name = "BodyContainer"
	add_child(body_container)

	var scale_factor: float = 1.0

	# === MATERIALS ===

	# Skin - mottled green/brown with slight shine
	var skin_mat = StandardMaterial3D.new()
	skin_mat.albedo_color = Color(0.3, 0.45, 0.25, 1)  # Swampy green
	skin_mat.roughness = 0.6
	skin_mat.metallic = 0.1  # Slight wet sheen

	# Belly - lighter yellow/orange
	var belly_mat = StandardMaterial3D.new()
	belly_mat.albedo_color = Color(0.7, 0.6, 0.3, 1)  # Yellow-orange
	belly_mat.roughness = 0.5

	# Warts - darker bumps
	var wart_mat = StandardMaterial3D.new()
	wart_mat.albedo_color = Color(0.25, 0.35, 0.2, 1)
	wart_mat.roughness = 0.8

	# Eye material - yellow with vertical pupil
	var eye_mat = StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.9, 0.8, 0.2, 1)  # Golden yellow
	eye_mat.emission_enabled = true
	eye_mat.emission = Color(0.4, 0.35, 0.1, 1)
	eye_mat.emission_energy_multiplier = 0.3

	# Pupil - black vertical slit
	var pupil_mat = StandardMaterial3D.new()
	pupil_mat.albedo_color = Color(0.05, 0.05, 0.05, 1)

	# Vest material - fancy red/burgundy
	var vest_mat = StandardMaterial3D.new()
	vest_mat.albedo_color = Color(0.5, 0.15, 0.15, 1)  # Burgundy
	vest_mat.roughness = 0.7

	# Gold trim/buttons
	var gold_mat = StandardMaterial3D.new()
	gold_mat.albedo_color = Color(0.85, 0.7, 0.2, 1)
	gold_mat.metallic = 0.8
	gold_mat.roughness = 0.3

	# Spectacles - glass/metal
	var glasses_mat = StandardMaterial3D.new()
	glasses_mat.albedo_color = Color(0.7, 0.7, 0.8, 0.3)
	glasses_mat.metallic = 0.9
	glasses_mat.roughness = 0.1

	# === MAIN BODY (fat squashed sphere) ===
	var body = MeshInstance3D.new()
	var body_mesh = SphereMesh.new()
	body_mesh.radius = 0.4 * scale_factor
	body_mesh.height = 0.6 * scale_factor  # Squashed
	body.mesh = body_mesh
	body.material_override = skin_mat
	body.position = Vector3(0, 0.4 * scale_factor, 0)
	body_container.add_child(body)

	# Belly (front bulge)
	var belly = MeshInstance3D.new()
	var belly_mesh = SphereMesh.new()
	belly_mesh.radius = 0.32 * scale_factor
	belly_mesh.height = 0.5 * scale_factor
	belly.mesh = belly_mesh
	belly.material_override = belly_mat
	belly.position = Vector3(0, 0.35 * scale_factor, 0.15 * scale_factor)
	body_container.add_child(belly)

	# === WARTS (scattered bumps) ===
	var wart_positions = [
		Vector3(0.25, 0.5, 0.2), Vector3(-0.2, 0.55, 0.15),
		Vector3(0.3, 0.35, -0.1), Vector3(-0.28, 0.4, -0.15),
		Vector3(0.15, 0.6, -0.2), Vector3(-0.1, 0.58, 0.25),
		Vector3(0.22, 0.3, 0.25), Vector3(-0.25, 0.32, 0.2),
	]
	for wart_pos in wart_positions:
		var wart = MeshInstance3D.new()
		var wart_mesh = SphereMesh.new()
		wart_mesh.radius = randf_range(0.02, 0.04) * scale_factor
		wart_mesh.height = wart_mesh.radius * 1.5
		wart.mesh = wart_mesh
		wart.material_override = wart_mat
		wart.position = wart_pos * scale_factor
		body_container.add_child(wart)

	# === HEAD (wide and flat) ===
	head = Node3D.new()
	head.name = "Head"
	head.position = Vector3(0, 0.55 * scale_factor, 0.2 * scale_factor)
	body_container.add_child(head)

	var head_mesh_inst = MeshInstance3D.new()
	var head_mesh = SphereMesh.new()
	head_mesh.radius = 0.28 * scale_factor
	head_mesh.height = 0.22 * scale_factor  # Very flat
	head_mesh_inst.mesh = head_mesh
	head_mesh_inst.material_override = skin_mat
	head.add_child(head_mesh_inst)

	# Wide mouth (curved box)
	var mouth = MeshInstance3D.new()
	var mouth_mesh = BoxMesh.new()
	mouth_mesh.size = Vector3(0.35, 0.04, 0.15) * scale_factor
	mouth.mesh = mouth_mesh
	mouth.material_override = pupil_mat  # Dark mouth line
	mouth.position = Vector3(0, -0.05 * scale_factor, 0.15 * scale_factor)
	head.add_child(mouth)

	# Mouth corners (grumpy downturn)
	for side in [-1, 1]:
		var corner = MeshInstance3D.new()
		var corner_mesh = BoxMesh.new()
		corner_mesh.size = Vector3(0.03, 0.03, 0.08) * scale_factor
		corner.mesh = corner_mesh
		corner.material_override = pupil_mat
		corner.position = Vector3(0.16 * side * scale_factor, -0.07 * scale_factor, 0.12 * scale_factor)
		corner.rotation.z = 0.3 * side
		head.add_child(corner)

	# === BULGING EYES (on top of head) ===
	for side in [-1, 1]:
		var eye_stalk = Node3D.new()
		eye_stalk.name = "Eye_" + ("L" if side == -1 else "R")
		eye_stalk.position = Vector3(0.12 * side * scale_factor, 0.12 * scale_factor, 0.05 * scale_factor)
		head.add_child(eye_stalk)

		# Eyeball
		var eyeball = MeshInstance3D.new()
		var eye_mesh = SphereMesh.new()
		eye_mesh.radius = 0.08 * scale_factor
		eye_mesh.height = 0.16 * scale_factor
		eyeball.mesh = eye_mesh
		eyeball.material_override = eye_mat
		eye_stalk.add_child(eyeball)

		# Pupil (vertical slit)
		var pupil = MeshInstance3D.new()
		var pupil_mesh = CylinderMesh.new()
		pupil_mesh.top_radius = 0.015 * scale_factor
		pupil_mesh.bottom_radius = 0.015 * scale_factor
		pupil_mesh.height = 0.06 * scale_factor
		pupil.mesh = pupil_mesh
		pupil.material_override = pupil_mat
		pupil.position = Vector3(0, 0, 0.065 * scale_factor)
		pupil.rotation.x = PI / 2
		eye_stalk.add_child(pupil)

		# Eyelid (half-closed, judgmental)
		var eyelid = MeshInstance3D.new()
		var lid_mesh = SphereMesh.new()
		lid_mesh.radius = 0.085 * scale_factor
		lid_mesh.height = 0.1 * scale_factor
		eyelid.mesh = lid_mesh
		eyelid.material_override = skin_mat
		eyelid.position = Vector3(0, 0.03 * scale_factor, 0)
		eye_stalk.add_child(eyelid)

		if side == -1:
			left_eye = eyeball
		else:
			right_eye = eyeball

	# === SPECTACLES (pince-nez style) ===
	# Nose bridge
	var nose_bridge = MeshInstance3D.new()
	var bridge_mesh = CylinderMesh.new()
	bridge_mesh.top_radius = 0.008 * scale_factor
	bridge_mesh.bottom_radius = 0.008 * scale_factor
	bridge_mesh.height = 0.12 * scale_factor
	nose_bridge.mesh = bridge_mesh
	nose_bridge.material_override = gold_mat
	nose_bridge.position = Vector3(0, 0.08 * scale_factor, 0.22 * scale_factor)
	nose_bridge.rotation.z = PI / 2
	head.add_child(nose_bridge)

	# Lens frames
	for side in [-1, 1]:
		var frame = MeshInstance3D.new()
		var frame_mesh = TorusMesh.new()
		frame_mesh.inner_radius = 0.03 * scale_factor
		frame_mesh.outer_radius = 0.038 * scale_factor
		frame.mesh = frame_mesh
		frame.material_override = gold_mat
		frame.position = Vector3(0.06 * side * scale_factor, 0.08 * scale_factor, 0.23 * scale_factor)
		frame.rotation.x = PI / 2
		head.add_child(frame)

		# Glass lens
		var lens = MeshInstance3D.new()
		var lens_mesh = CylinderMesh.new()
		lens_mesh.top_radius = 0.03 * scale_factor
		lens_mesh.bottom_radius = 0.03 * scale_factor
		lens_mesh.height = 0.005 * scale_factor
		lens.mesh = lens_mesh
		lens.material_override = glasses_mat
		lens.position = Vector3(0.06 * side * scale_factor, 0.08 * scale_factor, 0.23 * scale_factor)
		lens.rotation.x = PI / 2
		head.add_child(lens)

	# === THROAT POUCH (wobbly when talking) ===
	throat_pouch = MeshInstance3D.new()
	var pouch_mesh = SphereMesh.new()
	pouch_mesh.radius = 0.15 * scale_factor
	pouch_mesh.height = 0.12 * scale_factor
	throat_pouch.mesh = pouch_mesh
	throat_pouch.material_override = belly_mat
	throat_pouch.position = Vector3(0, 0.25 * scale_factor, 0.35 * scale_factor)
	body_container.add_child(throat_pouch)

	# === ARMS (stubby with webbed hands) ===
	for side in [-1, 1]:
		var arm = Node3D.new()
		arm.position = Vector3(0.35 * side * scale_factor, 0.4 * scale_factor, 0.1 * scale_factor)
		body_container.add_child(arm)

		# Upper arm
		var upper = MeshInstance3D.new()
		var upper_mesh = CapsuleMesh.new()
		upper_mesh.radius = 0.06 * scale_factor
		upper_mesh.height = 0.18 * scale_factor
		upper.mesh = upper_mesh
		upper.material_override = skin_mat
		upper.rotation.z = 0.8 * side
		upper.rotation.x = 0.3
		upper.position = Vector3(0.08 * side * scale_factor, -0.05 * scale_factor, 0)
		arm.add_child(upper)

		# Hand (webbed, 3 fingers)
		var hand = Node3D.new()
		hand.position = Vector3(0.18 * side * scale_factor, -0.12 * scale_factor, 0.05 * scale_factor)
		arm.add_child(hand)

		# Palm
		var palm = MeshInstance3D.new()
		var palm_mesh = SphereMesh.new()
		palm_mesh.radius = 0.04 * scale_factor
		palm_mesh.height = 0.03 * scale_factor
		palm.mesh = palm_mesh
		palm.material_override = skin_mat
		hand.add_child(palm)

		# Fingers (3 webbed)
		for f in range(3):
			var finger = MeshInstance3D.new()
			var finger_mesh = CapsuleMesh.new()
			finger_mesh.radius = 0.015 * scale_factor
			finger_mesh.height = 0.06 * scale_factor
			finger.mesh = finger_mesh
			finger.material_override = skin_mat
			var angle = (f - 1) * 0.4
			finger.position = Vector3(sin(angle) * 0.04 * scale_factor, -0.03 * scale_factor, cos(angle) * 0.04 * scale_factor)
			finger.rotation.x = 0.3
			finger.rotation.z = angle * 0.5
			hand.add_child(finger)

	# === LEGS (thick back legs, squatting) ===
	for side in [-1, 1]:
		var leg = Node3D.new()
		leg.position = Vector3(0.2 * side * scale_factor, 0.15 * scale_factor, -0.1 * scale_factor)
		body_container.add_child(leg)

		# Thigh (thick)
		var thigh = MeshInstance3D.new()
		var thigh_mesh = CapsuleMesh.new()
		thigh_mesh.radius = 0.1 * scale_factor
		thigh_mesh.height = 0.2 * scale_factor
		thigh.mesh = thigh_mesh
		thigh.material_override = skin_mat
		thigh.rotation.x = -0.5
		thigh.rotation.z = 0.3 * side
		thigh.position = Vector3(0.05 * side * scale_factor, -0.05 * scale_factor, 0)
		leg.add_child(thigh)

		# Foot (big webbed)
		var foot = MeshInstance3D.new()
		var foot_mesh = SphereMesh.new()
		foot_mesh.radius = 0.1 * scale_factor
		foot_mesh.height = 0.05 * scale_factor
		foot.mesh = foot_mesh
		foot.material_override = skin_mat
		foot.position = Vector3(0.12 * side * scale_factor, -0.15 * scale_factor, 0.1 * scale_factor)
		leg.add_child(foot)

		# Toes (4 webbed)
		for t in range(4):
			var toe = MeshInstance3D.new()
			var toe_mesh = CapsuleMesh.new()
			toe_mesh.radius = 0.018 * scale_factor
			toe_mesh.height = 0.08 * scale_factor
			toe.mesh = toe_mesh
			toe.material_override = skin_mat
			var angle = (t - 1.5) * 0.35
			toe.position = Vector3(0.12 * side * scale_factor + sin(angle) * 0.06 * scale_factor, -0.17 * scale_factor, 0.18 * scale_factor + cos(angle) * 0.02 * scale_factor)
			toe.rotation.x = 0.4
			leg.add_child(toe)

	# === MERCHANT VEST ===
	var vest = MeshInstance3D.new()
	var vest_mesh = SphereMesh.new()
	vest_mesh.radius = 0.38 * scale_factor
	vest_mesh.height = 0.45 * scale_factor
	vest.mesh = vest_mesh
	vest.material_override = vest_mat
	vest.position = Vector3(0, 0.42 * scale_factor, 0.02 * scale_factor)
	vest.scale = Vector3(0.85, 0.7, 0.6)  # Flattened to look like vest
	body_container.add_child(vest)

	# Vest opening (V-neck showing belly)
	var vest_cut = MeshInstance3D.new()
	var cut_mesh = CylinderMesh.new()
	cut_mesh.top_radius = 0.0
	cut_mesh.bottom_radius = 0.15 * scale_factor
	cut_mesh.height = 0.25 * scale_factor
	vest_cut.mesh = cut_mesh
	vest_cut.material_override = belly_mat
	vest_cut.position = Vector3(0, 0.35 * scale_factor, 0.22 * scale_factor)
	vest_cut.rotation.x = -0.3
	body_container.add_child(vest_cut)

	# Gold buttons (straining)
	for i in range(2):
		var button = MeshInstance3D.new()
		var button_mesh = SphereMesh.new()
		button_mesh.radius = 0.025 * scale_factor
		button.mesh = button_mesh
		button.material_override = gold_mat
		button.position = Vector3(0.12 * scale_factor, 0.35 * scale_factor - i * 0.12 * scale_factor, 0.32 * scale_factor)
		body_container.add_child(button)

		# Matching button on other side
		var button2 = MeshInstance3D.new()
		button2.mesh = button_mesh
		button2.material_override = gold_mat
		button2.position = Vector3(-0.12 * scale_factor, 0.35 * scale_factor - i * 0.12 * scale_factor, 0.32 * scale_factor)
		body_container.add_child(button2)

# =============================================================================
# INTERACTION
# =============================================================================

func _setup_interaction_area() -> void:
	interaction_area = Area3D.new()
	interaction_area.name = "InteractionArea"
	add_child(interaction_area)

	var shape = CollisionShape3D.new()
	var sphere = SphereShape3D.new()
	sphere.radius = 2.5  # Interaction range
	shape.shape = sphere
	interaction_area.add_child(shape)

	interaction_area.body_entered.connect(_on_body_entered)
	interaction_area.body_exited.connect(_on_body_exited)

func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("players") and body.get("is_local_player"):
		player_nearby = true
		print("[Shnarken] Player entered interaction range")

func _on_body_exited(body: Node3D) -> void:
	if body.is_in_group("players") and body.get("is_local_player"):
		player_nearby = false
		print("[Shnarken] Player left interaction range")

func interact() -> void:
	if player_nearby:
		interaction_requested.emit(self)

func _input(event: InputEvent) -> void:
	if player_nearby and event.is_action_pressed("interact"):
		interact()

# =============================================================================
# ANIMATIONS
# =============================================================================

func _update_idle_animation(delta: float) -> void:
	# Only do idle bob when not hopping
	if not is_hopping:
		# Gentle body bob
		if body_container:
			body_container.position.y = sin(idle_time * 1.5) * 0.02

	# Slight head sway (always)
	if head:
		head.rotation.y = sin(idle_time * 0.8) * 0.05
		head.rotation.z = sin(idle_time * 1.2) * 0.02

func _update_hopping(delta: float) -> void:
	if is_hopping:
		# Currently in a hop
		hop_progress += delta / hop_duration
		if hop_progress >= 1.0:
			# Hop complete
			hop_progress = 1.0
			is_hopping = false
			global_position = hop_target
			global_position.y = home_position.y  # Reset to ground level
			if body_container:
				body_container.position.y = 0
			next_hop_time = randf_range(1.5, 4.0)
			hop_timer = 0.0
		else:
			# Interpolate position with arc
			var t := hop_progress
			# Smoothstep for horizontal movement
			var smooth_t := t * t * (3.0 - 2.0 * t)
			var new_pos := hop_start_pos.lerp(hop_target, smooth_t)
			# Parabolic arc for height (peaks at t=0.5)
			var height_offset := hop_height * 4.0 * t * (1.0 - t)
			new_pos.y = home_position.y + height_offset
			global_position = new_pos

			# Squash and stretch animation
			if body_container:
				if t < 0.3:
					# Launching - stretch vertically
					body_container.scale = Vector3(0.85, 1.2, 0.85)
				elif t > 0.7:
					# Landing - squash
					body_container.scale = Vector3(1.15, 0.8, 1.15)
				else:
					# Mid-air - normal
					body_container.scale = Vector3.ONE
	else:
		# Reset scale when not hopping
		if body_container and body_container.scale != Vector3.ONE:
			body_container.scale = body_container.scale.lerp(Vector3.ONE, delta * 10.0)

		# Wait for next hop
		hop_timer += delta
		if hop_timer >= next_hop_time:
			_start_hop()

func _start_hop() -> void:
	# Pick a random point around home position
	var angle := randf() * TAU
	var distance := randf_range(1.5, hop_radius)
	var offset := Vector3(cos(angle) * distance, 0, sin(angle) * distance)

	hop_start_pos = global_position
	hop_target = home_position + offset
	hop_target.y = home_position.y

	# Face the hop direction
	var direction := (hop_target - global_position).normalized()
	if direction.length() > 0.1:
		rotation.y = atan2(direction.x, direction.z)

	is_hopping = true
	hop_progress = 0.0

	# Vary hop height based on distance
	var hop_distance := global_position.distance_to(hop_target)
	hop_height = 0.3 + (hop_distance * 0.1)
	hop_duration = 0.3 + (hop_distance * 0.05)

func _update_blink(delta: float) -> void:
	blink_timer += delta

	if not is_blinking and blink_timer >= next_blink:
		is_blinking = true
		blink_timer = 0.0
		next_blink = randf_range(2.0, 5.0)

		# Quick blink animation
		if left_eye:
			var tween = create_tween()
			tween.tween_property(left_eye, "scale:y", 0.1, 0.08)
			tween.tween_property(left_eye, "scale:y", 1.0, 0.08)
			tween.tween_callback(func(): is_blinking = false)

		# Sometimes blink eyes independently
		if right_eye and randf() > 0.3:
			var tween2 = create_tween()
			tween2.tween_interval(randf_range(0.0, 0.1))
			tween2.tween_property(right_eye, "scale:y", 0.1, 0.08)
			tween2.tween_property(right_eye, "scale:y", 1.0, 0.08)

func _update_throat_wobble(delta: float) -> void:
	throat_wobble += delta * 15.0
	if throat_pouch:
		throat_pouch.scale.y = 1.0 + sin(throat_wobble) * 0.3
		throat_pouch.scale.x = 1.0 + cos(throat_wobble * 1.3) * 0.15

func start_talking() -> void:
	is_talking = true
	throat_wobble = 0.0

func stop_talking() -> void:
	is_talking = false
	if throat_pouch:
		var tween = create_tween()
		tween.tween_property(throat_pouch, "scale", Vector3.ONE, 0.2)

# =============================================================================
# DIALOGUE
# =============================================================================

func get_greeting_dialogue(player: Node) -> String:
	# Check player's gear and return appropriate mockery
	var equipment = player.get_node_or_null("Equipment")
	if not equipment:
		return _get_naked_dialogue()

	var has_armor = false
	var has_weapon = false
	var armor_set = ""

	# Check armor
	for slot in [1, 2, 3, 4]:  # HEAD, CHEST, LEGS, CAPE
		var item_id = equipment.get_equipped_item(slot)
		if not item_id.is_empty():
			has_armor = true
			if "pig" in item_id:
				armor_set = "pig"
			elif "deer" in item_id:
				armor_set = "deer"

	# Check weapon
	var weapon_id = equipment.get_equipped_item(0)  # MAIN_HAND
	if not weapon_id.is_empty() and weapon_id != "fists":
		has_weapon = true

	# Return appropriate dialogue
	if not has_armor and not has_weapon:
		return _get_naked_dialogue()
	elif not has_armor:
		return _get_no_armor_dialogue()
	elif not has_weapon:
		return _get_no_weapon_dialogue(armor_set)
	else:
		return _get_geared_dialogue(armor_set)

func _get_naked_dialogue() -> String:
	var lines = [
		"By the swamp! Cover yourself! You're more naked than a fresh-hatched tadpole!",
		"No armor? No weapon? The pigs must be LAUGHING at you. IF you've even seen one...",
		"A muddy nudist in MY shop? How delightfully pathetic.",
		"You call yourself an adventurer? I've seen better-equipped pond scum!",
	]
	return lines[randi() % lines.size()]

func _get_no_armor_dialogue() -> String:
	var lines = [
		"Nice weapon! Shame about the... everything else. Ever heard of ARMOR?",
		"Planning to fight naked, are we? Bold strategy. Stupid, but bold.",
		"The pigs aren't THAT hard to catch. Unless you're scared of a little oinking?",
	]
	return lines[randi() % lines.size()]

func _get_no_weapon_dialogue(armor_set: String) -> String:
	if armor_set == "pig":
		var lines = [
			"Ooh, pig leather! Did you wrestle it yourself or just find it dead? Where's your wand?",
			"Nice pig suit! Now go kill a Gahnome for its resin. You DO know what resin is for, right?",
		]
		return lines[randi() % lines.size()]
	else:
		var lines = [
			"All dressed up with nothing to hit things with. Charming.",
			"Armor but no weapon? Planning to hug the monsters to death?",
		]
		return lines[randi() % lines.size()]

func _get_geared_dialogue(armor_set: String) -> String:
	var lines = [
		"Well, well! You're almost competent! How... disappointing. I was enjoying the show.",
		"Finally figured out how to dress yourself! Your mother would be so proud. If she could see past the smell.",
		"You're slightly less pathetic today. Don't let it go to your head.",
	]
	return lines[randi() % lines.size()]

func get_max_upgrade_dialogue() -> String:
	var lines = [
		"This is as good as it can be... without being as good as MY gear, of course.",
		"Maxed out! Still inferior to what I wear, naturally.",
		"Can't improve it further. Well, I COULD, but not for the likes of you.",
	]
	return lines[randi() % lines.size()]
