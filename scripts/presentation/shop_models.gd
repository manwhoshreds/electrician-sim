class_name ShopModels
extends RefCounted
## Simple models of what's for sale on TradesmanGear.com, for the product
## pictures. The van is the game's own.

const BLACK := Color(0.06, 0.06, 0.07)
const ALUMINUM := Color(0.72, 0.74, 0.76)
const RED := Color(0.72, 0.08, 0.06)


static func model(id: String) -> Node3D:
	var m := Node3D.new()
	var B := Preview3D
	match id:
		"truck_toolbox":
			B.block(m, Vector3(1.78, 0.42, 0.5), Vector3.ZERO, BLACK, 0.7, 0.35)
			B.block(m, Vector3(1.8, 0.03, 0.52), Vector3(0, 0.22, 0), BLACK.lightened(0.08), 0.8, 0.3)
			for x in [-0.6, 0.6]:
				B.block(m, Vector3(0.12, 0.06, 0.02), Vector3(x, 0.1, 0.26), ALUMINUM, 0.9, 0.2)
		"bed_drawers":
			B.block(m, Vector3(1.6, 0.3, 1.2), Vector3.ZERO, Color(0.25, 0.26, 0.27), 0.6, 0.4)
			for x in [-0.4, 0.4]:
				B.block(m, Vector3(0.7, 0.24, 0.02), Vector3(x, 0, 0.61), Color(0.12, 0.12, 0.13), 0.5, 0.4)
				B.block(m, Vector3(0.2, 0.03, 0.03), Vector3(x, 0.05, 0.63), ALUMINUM, 0.9, 0.2)
		"ladder_rack":
			for x in [-0.75, 0.75]:
				for z in [-0.8, 0.8]:
					B.rod(m, 0.025, 0.9, Vector3(x, 0.45, z), ALUMINUM)
				B.rod(m, 0.025, 1.6, Vector3(x, 0.9, 0), ALUMINUM, Vector3(PI / 2, 0, 0))
			for z in [-0.8, 0.8]:
				B.rod(m, 0.025, 1.5, Vector3(0, 0.9, z), ALUMINUM, Vector3(0, 0, PI / 2))
		"light_bar":
			B.block(m, Vector3(0.52, 0.08, 0.07), Vector3.ZERO, BLACK, 0.6, 0.3)
			for i in 10:
				var led := B.block(m, Vector3(0.035, 0.035, 0.01), Vector3(-0.22 + i * 0.049, 0, 0.037), Color(0.9, 0.95, 1.0), 0.0, 0.1)
				(led.material_override as StandardMaterial3D).emission_enabled = true
				(led.material_override as StandardMaterial3D).emission = Color(0.85, 0.92, 1.0)
		"work_van":
			m.add_child((load("res://assets/van/van.glb") as PackedScene).instantiate())
		"headlamp":
			var band := MeshInstance3D.new()
			var torus := TorusMesh.new()
			torus.inner_radius = 0.075
			torus.outer_radius = 0.09
			band.mesh = torus
			band.material_override = B.mat(BLACK, 0.0, 0.8)
			band.rotation.x = PI / 2
			m.add_child(band)
			B.block(m, Vector3(0.06, 0.04, 0.035), Vector3(0, 0, 0.09), Color(0.85, 0.5, 0.05), 0.1, 0.4)
			B.rod(m, 0.014, 0.01, Vector3(0, 0, 0.11), Color(0.9, 0.95, 1.0), Vector3(PI / 2, 0, 0))
		"tool_bag":
			B.block(m, Vector3(0.46, 0.26, 0.24), Vector3.ZERO, Color(0.12, 0.12, 0.12), 0.0, 0.9)
			B.block(m, Vector3(0.47, 0.06, 0.25), Vector3(0, -0.11, 0), Color(0.85, 0.55, 0.05), 0.0, 0.8)
			B.rod(m, 0.012, 0.36, Vector3(0, 0.2, 0), ALUMINUM, Vector3(0, 0, PI / 2))
			B.rod(m, 0.01, 0.08, Vector3(-0.17, 0.16, 0), ALUMINUM)
			B.rod(m, 0.01, 0.08, Vector3(0.17, 0.16, 0), ALUMINUM)
		"rolling_toolbox":
			for i in 3:
				B.block(m, Vector3(0.55, 0.22 + i * 0.03, 0.36), Vector3(0, 0.15 + i * 0.27, 0), RED, 0.2, 0.5)
				B.block(m, Vector3(0.56, 0.03, 0.37), Vector3(0, 0.27 + i * 0.27, 0), BLACK, 0.2, 0.5)
			for x in [-0.22, 0.22]:
				B.rod(m, 0.06, 0.05, Vector3(x, 0.04, -0.12), BLACK, Vector3(0, 0, PI / 2))
		"gloves":
			for x in [-0.07, 0.07]:
				var g := MeshInstance3D.new()
				var c := CapsuleMesh.new()
				c.radius = 0.05
				c.height = 0.28
				g.mesh = c
				g.material_override = B.mat(Color(0.92, 0.45, 0.08), 0.0, 0.7)
				g.position = Vector3(x, 0, 0)
				g.rotation.z = x * 2.0
				m.add_child(g)
				B.block(m, Vector3(0.11, 0.06, 0.11), Vector3(x * 1.3, -0.15, 0), Color(0.55, 0.4, 0.25), 0.0, 0.9)
		"work_boots":
			for x in [-0.08, 0.08]:
				B.block(m, Vector3(0.11, 0.18, 0.13), Vector3(x, 0.09, -0.04), Color(0.4, 0.26, 0.13), 0.0, 0.8)
				B.block(m, Vector3(0.11, 0.08, 0.3), Vector3(x, 0.04, 0.04), Color(0.4, 0.26, 0.13), 0.0, 0.8)
				B.block(m, Vector3(0.12, 0.025, 0.31), Vector3(x, 0.005, 0.04), BLACK, 0.0, 0.9)
		"drill_kit":
			B.block(m, Vector3(0.24, 0.09, 0.07), Vector3(0, 0.12, 0), RED, 0.1, 0.5)          # body
			B.rod(m, 0.022, 0.08, Vector3(0.16, 0.12, 0), BLACK, Vector3(0, 0, PI / 2))           # chuck
			B.rod(m, 0.005, 0.07, Vector3(0.23, 0.12, 0), ALUMINUM, Vector3(0, 0, PI / 2))        # bit
			B.block(m, Vector3(0.06, 0.16, 0.06), Vector3(-0.04, 0.0, 0), BLACK, 0.0, 0.8)      # grip
			B.block(m, Vector3(0.11, 0.07, 0.09), Vector3(-0.04, -0.11, 0), BLACK, 0.1, 0.6)    # battery
			B.block(m, Vector3(0.1, 0.07, 0.09), Vector3(0.2, -0.11, 0.05), RED, 0.1, 0.5)      # spare battery
		"hole_saw_kit":
			B.block(m, Vector3(0.36, 0.06, 0.24), Vector3(0, -0.03, 0), BLACK, 0.1, 0.6)
			for i in 5:
				var r := 0.025 + i * 0.008
				B.rod(m, r, 0.05, Vector3(-0.14 + i * 0.07, 0.025, -0.03 + (i % 2) * 0.06), Color(0.85, 0.7, 0.15), Vector3.ZERO, 20)
		"voltage_tester":
			B.rod(m, 0.014, 0.16, Vector3.ZERO, Color(0.95, 0.75, 0.05), Vector3(0, 0, PI / 2))
			B.rod(m, 0.01, 0.04, Vector3(0.1, 0, 0), Color(0.9, 0.2, 0.15), Vector3(0, 0, PI / 2))
			B.block(m, Vector3(0.03, 0.006, 0.012), Vector3(-0.05, 0.015, 0), BLACK, 0.3, 0.4)
		"wire_strippers":
			for s in [-1.0, 1.0]:
				B.block(m, Vector3(0.11, 0.012, 0.025), Vector3(0.07, 0, 0), ALUMINUM, 0.9, 0.25).rotation.y = s * 0.12
				B.block(m, Vector3(0.12, 0.022, 0.03), Vector3(-0.05, 0, s * 0.03), Color(0.95, 0.45, 0.08), 0.0, 0.7).rotation.y = s * 0.25
		"fish_tape":
			var reel := MeshInstance3D.new()
			var t := TorusMesh.new()
			t.inner_radius = 0.1
			t.outer_radius = 0.14
			reel.mesh = t
			reel.material_override = B.mat(Color(0.95, 0.75, 0.05), 0.1, 0.5)
			reel.rotation.x = PI / 2
			m.add_child(reel)
			B.block(m, Vector3(0.05, 0.12, 0.03), Vector3(0, -0.17, 0), BLACK, 0.0, 0.8)
			B.rod(m, 0.004, 0.2, Vector3(0.22, -0.12, 0), ALUMINUM, Vector3(0, 0, PI / 2))
		_:
			B.block(m, Vector3(0.3, 0.3, 0.3), Vector3.ZERO, Color(0.6, 0.6, 0.6))
	return m
