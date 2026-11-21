class_name Surfaces
extends RefCounted
## Materials made from the photographed texture sets in assets/textures.
## Each set is <name>_diff.jpg, <name>_nor.jpg and <name>_rough.jpg.


## `metres` is how much real-world surface one tile of the texture covers.
## World-mapped surfaces line up across separate meshes, like the road's pieces.
static func photo(tex_name: String, metres: float, tint := Color.WHITE, world_mapped := true) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = tint
	m.albedo_texture = load("res://assets/textures/%s_diff.jpg" % tex_name)
	m.normal_enabled = true
	m.normal_texture = load("res://assets/textures/%s_nor.jpg" % tex_name)
	m.roughness = 1.0
	m.roughness_texture = load("res://assets/textures/%s_rough.jpg" % tex_name)
	m.uv1_triplanar = true
	m.uv1_world_triplanar = world_mapped
	m.uv1_triplanar_sharpness = 12.0
	m.uv1_scale = Vector3.ONE / metres
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
	return m
