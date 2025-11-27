extends RefCounted
class_name ChunkMeshGenerator

## ChunkMeshGenerator - Generates smooth terrain meshes from voxel data
## Uses Marching Cubes algorithm for Valheim-style smooth terrain
## Takes Minecraft-resolution voxels and outputs smooth, natural-looking meshes

const ChunkDataClass = preload("res://shared/custom_terrain/chunk_data.gd")

# Surface threshold - density values above this are considered solid
const SURFACE_THRESHOLD: float = 0.5

# Marching cubes lookup tables
# Edge table: which edges are cut for each of 256 cube configurations
var edge_table: PackedInt32Array
# Triangle table: which triangles to create for each configuration
var tri_table: Array  # Array of PackedInt32Array

# Pre-computed edge vertices for interpolation
const EDGE_VERTICES: Array = [
	[0, 1], [1, 2], [2, 3], [3, 0],  # Bottom edges
	[4, 5], [5, 6], [6, 7], [7, 4],  # Top edges
	[0, 4], [1, 5], [2, 6], [3, 7]   # Vertical edges
]

# Cube corner offsets (local coordinates)
const CORNER_OFFSETS: Array = [
	Vector3(0, 0, 0), Vector3(1, 0, 0), Vector3(1, 0, 1), Vector3(0, 0, 1),  # Bottom
	Vector3(0, 1, 0), Vector3(1, 1, 0), Vector3(1, 1, 1), Vector3(0, 1, 1)   # Top
]

func _init() -> void:
	_init_marching_cubes_tables()

## Initialize the marching cubes lookup tables
func _init_marching_cubes_tables() -> void:
	# Edge table - 256 entries indicating which edges are crossed
	edge_table = PackedInt32Array([
		0x0, 0x109, 0x203, 0x30a, 0x406, 0x50f, 0x605, 0x70c,
		0x80c, 0x905, 0xa0f, 0xb06, 0xc0a, 0xd03, 0xe09, 0xf00,
		0x190, 0x99, 0x393, 0x29a, 0x596, 0x49f, 0x795, 0x69c,
		0x99c, 0x895, 0xb9f, 0xa96, 0xd9a, 0xc93, 0xf99, 0xe90,
		0x230, 0x339, 0x33, 0x13a, 0x636, 0x73f, 0x435, 0x53c,
		0xa3c, 0xb35, 0x83f, 0x936, 0xe3a, 0xf33, 0xc39, 0xd30,
		0x3a0, 0x2a9, 0x1a3, 0xaa, 0x7a6, 0x6af, 0x5a5, 0x4ac,
		0xbac, 0xaa5, 0x9af, 0x8a6, 0xfaa, 0xea3, 0xda9, 0xca0,
		0x460, 0x569, 0x663, 0x76a, 0x66, 0x16f, 0x265, 0x36c,
		0xc6c, 0xd65, 0xe6f, 0xf66, 0x86a, 0x963, 0xa69, 0xb60,
		0x5f0, 0x4f9, 0x7f3, 0x6fa, 0x1f6, 0xff, 0x3f5, 0x2fc,
		0xdfc, 0xcf5, 0xfff, 0xef6, 0x9fa, 0x8f3, 0xbf9, 0xaf0,
		0x650, 0x759, 0x453, 0x55a, 0x256, 0x35f, 0x55, 0x15c,
		0xe5c, 0xf55, 0xc5f, 0xd56, 0xa5a, 0xb53, 0x859, 0x950,
		0x7c0, 0x6c9, 0x5c3, 0x4ca, 0x3c6, 0x2cf, 0x1c5, 0xcc,
		0xfcc, 0xec5, 0xdcf, 0xcc6, 0xbca, 0xac3, 0x9c9, 0x8c0,
		0x8c0, 0x9c9, 0xac3, 0xbca, 0xcc6, 0xdcf, 0xec5, 0xfcc,
		0xcc, 0x1c5, 0x2cf, 0x3c6, 0x4ca, 0x5c3, 0x6c9, 0x7c0,
		0x950, 0x859, 0xb53, 0xa5a, 0xd56, 0xc5f, 0xf55, 0xe5c,
		0x15c, 0x55, 0x35f, 0x256, 0x55a, 0x453, 0x759, 0x650,
		0xaf0, 0xbf9, 0x8f3, 0x9fa, 0xef6, 0xfff, 0xcf5, 0xdfc,
		0x2fc, 0x3f5, 0xff, 0x1f6, 0x6fa, 0x7f3, 0x4f9, 0x5f0,
		0xb60, 0xa69, 0x963, 0x86a, 0xf66, 0xe6f, 0xd65, 0xc6c,
		0x36c, 0x265, 0x16f, 0x66, 0x76a, 0x663, 0x569, 0x460,
		0xca0, 0xda9, 0xea3, 0xfaa, 0x8a6, 0x9af, 0xaa5, 0xbac,
		0x4ac, 0x5a5, 0x6af, 0x7a6, 0xaa, 0x1a3, 0x2a9, 0x3a0,
		0xd30, 0xc39, 0xf33, 0xe3a, 0x936, 0x83f, 0xb35, 0xa3c,
		0x53c, 0x435, 0x73f, 0x636, 0x13a, 0x33, 0x339, 0x230,
		0xe90, 0xf99, 0xc93, 0xd9a, 0xa96, 0xb9f, 0x895, 0x99c,
		0x69c, 0x795, 0x49f, 0x596, 0x29a, 0x393, 0x99, 0x190,
		0xf00, 0xe09, 0xd03, 0xc0a, 0xb06, 0xa0f, 0x905, 0x80c,
		0x70c, 0x605, 0x50f, 0x406, 0x30a, 0x203, 0x109, 0x0
	])

	# Triangle table - complete 256 entry marching cubes lookup table
	# Each entry is a list of edge indices forming triangles, terminated by -1
	tri_table = _create_full_tri_table()

## Create the complete marching cubes triangle table (all 256 configurations)
func _create_full_tri_table() -> Array:
	var table: Array = []
	table.resize(256)

	# Standard marching cubes triangle table
	# Format: [edge0, edge1, edge2, edge3, edge4, edge5, ..., -1]
	# Each triplet forms a triangle, -1 terminates
	table[0] = [-1]
	table[1] = [0, 8, 3, -1]
	table[2] = [0, 1, 9, -1]
	table[3] = [1, 8, 3, 9, 8, 1, -1]
	table[4] = [1, 2, 10, -1]
	table[5] = [0, 8, 3, 1, 2, 10, -1]
	table[6] = [9, 2, 10, 0, 2, 9, -1]
	table[7] = [2, 8, 3, 2, 10, 8, 10, 9, 8, -1]
	table[8] = [3, 11, 2, -1]
	table[9] = [0, 11, 2, 8, 11, 0, -1]
	table[10] = [1, 9, 0, 2, 3, 11, -1]
	table[11] = [1, 11, 2, 1, 9, 11, 9, 8, 11, -1]
	table[12] = [3, 10, 1, 11, 10, 3, -1]
	table[13] = [0, 10, 1, 0, 8, 10, 8, 11, 10, -1]
	table[14] = [3, 9, 0, 3, 11, 9, 11, 10, 9, -1]
	table[15] = [9, 8, 10, 10, 8, 11, -1]
	table[16] = [4, 7, 8, -1]
	table[17] = [4, 3, 0, 7, 3, 4, -1]
	table[18] = [0, 1, 9, 8, 4, 7, -1]
	table[19] = [4, 1, 9, 4, 7, 1, 7, 3, 1, -1]
	table[20] = [1, 2, 10, 8, 4, 7, -1]
	table[21] = [3, 4, 7, 3, 0, 4, 1, 2, 10, -1]
	table[22] = [9, 2, 10, 9, 0, 2, 8, 4, 7, -1]
	table[23] = [2, 10, 9, 2, 9, 7, 2, 7, 3, 7, 9, 4, -1]
	table[24] = [8, 4, 7, 3, 11, 2, -1]
	table[25] = [11, 4, 7, 11, 2, 4, 2, 0, 4, -1]
	table[26] = [9, 0, 1, 8, 4, 7, 2, 3, 11, -1]
	table[27] = [4, 7, 11, 9, 4, 11, 9, 11, 2, 9, 2, 1, -1]
	table[28] = [3, 10, 1, 3, 11, 10, 7, 8, 4, -1]
	table[29] = [1, 11, 10, 1, 4, 11, 1, 0, 4, 7, 11, 4, -1]
	table[30] = [4, 7, 8, 9, 0, 11, 9, 11, 10, 11, 0, 3, -1]
	table[31] = [4, 7, 11, 4, 11, 9, 9, 11, 10, -1]
	table[32] = [9, 5, 4, -1]
	table[33] = [9, 5, 4, 0, 8, 3, -1]
	table[34] = [0, 5, 4, 1, 5, 0, -1]
	table[35] = [8, 5, 4, 8, 3, 5, 3, 1, 5, -1]
	table[36] = [1, 2, 10, 9, 5, 4, -1]
	table[37] = [3, 0, 8, 1, 2, 10, 4, 9, 5, -1]
	table[38] = [5, 2, 10, 5, 4, 2, 4, 0, 2, -1]
	table[39] = [2, 10, 5, 3, 2, 5, 3, 5, 4, 3, 4, 8, -1]
	table[40] = [9, 5, 4, 2, 3, 11, -1]
	table[41] = [0, 11, 2, 0, 8, 11, 4, 9, 5, -1]
	table[42] = [0, 5, 4, 0, 1, 5, 2, 3, 11, -1]
	table[43] = [2, 1, 5, 2, 5, 8, 2, 8, 11, 4, 8, 5, -1]
	table[44] = [10, 3, 11, 10, 1, 3, 9, 5, 4, -1]
	table[45] = [4, 9, 5, 0, 8, 1, 8, 10, 1, 8, 11, 10, -1]
	table[46] = [5, 4, 0, 5, 0, 11, 5, 11, 10, 11, 0, 3, -1]
	table[47] = [5, 4, 8, 5, 8, 10, 10, 8, 11, -1]
	table[48] = [9, 7, 8, 5, 7, 9, -1]
	table[49] = [9, 3, 0, 9, 5, 3, 5, 7, 3, -1]
	table[50] = [0, 7, 8, 0, 1, 7, 1, 5, 7, -1]
	table[51] = [1, 5, 3, 3, 5, 7, -1]
	table[52] = [9, 7, 8, 9, 5, 7, 10, 1, 2, -1]
	table[53] = [10, 1, 2, 9, 5, 0, 5, 3, 0, 5, 7, 3, -1]
	table[54] = [8, 0, 2, 8, 2, 5, 8, 5, 7, 10, 5, 2, -1]
	table[55] = [2, 10, 5, 2, 5, 3, 3, 5, 7, -1]
	table[56] = [7, 9, 5, 7, 8, 9, 3, 11, 2, -1]
	table[57] = [9, 5, 7, 9, 7, 2, 9, 2, 0, 2, 7, 11, -1]
	table[58] = [2, 3, 11, 0, 1, 8, 1, 7, 8, 1, 5, 7, -1]
	table[59] = [11, 2, 1, 11, 1, 7, 7, 1, 5, -1]
	table[60] = [9, 5, 8, 8, 5, 7, 10, 1, 3, 10, 3, 11, -1]
	table[61] = [5, 7, 0, 5, 0, 9, 7, 11, 0, 1, 0, 10, 11, 10, 0, -1]
	table[62] = [11, 10, 0, 11, 0, 3, 10, 5, 0, 8, 0, 7, 5, 7, 0, -1]
	table[63] = [11, 10, 5, 7, 11, 5, -1]
	table[64] = [10, 6, 5, -1]
	table[65] = [0, 8, 3, 5, 10, 6, -1]
	table[66] = [9, 0, 1, 5, 10, 6, -1]
	table[67] = [1, 8, 3, 1, 9, 8, 5, 10, 6, -1]
	table[68] = [1, 6, 5, 2, 6, 1, -1]
	table[69] = [1, 6, 5, 1, 2, 6, 3, 0, 8, -1]
	table[70] = [9, 6, 5, 9, 0, 6, 0, 2, 6, -1]
	table[71] = [5, 9, 8, 5, 8, 2, 5, 2, 6, 3, 2, 8, -1]
	table[72] = [2, 3, 11, 10, 6, 5, -1]
	table[73] = [11, 0, 8, 11, 2, 0, 10, 6, 5, -1]
	table[74] = [0, 1, 9, 2, 3, 11, 5, 10, 6, -1]
	table[75] = [5, 10, 6, 1, 9, 2, 9, 11, 2, 9, 8, 11, -1]
	table[76] = [6, 3, 11, 6, 5, 3, 5, 1, 3, -1]
	table[77] = [0, 8, 11, 0, 11, 5, 0, 5, 1, 5, 11, 6, -1]
	table[78] = [3, 11, 6, 0, 3, 6, 0, 6, 5, 0, 5, 9, -1]
	table[79] = [6, 5, 9, 6, 9, 11, 11, 9, 8, -1]
	table[80] = [5, 10, 6, 4, 7, 8, -1]
	table[81] = [4, 3, 0, 4, 7, 3, 6, 5, 10, -1]
	table[82] = [1, 9, 0, 5, 10, 6, 8, 4, 7, -1]
	table[83] = [10, 6, 5, 1, 9, 7, 1, 7, 3, 7, 9, 4, -1]
	table[84] = [6, 1, 2, 6, 5, 1, 4, 7, 8, -1]
	table[85] = [1, 2, 5, 5, 2, 6, 3, 0, 4, 3, 4, 7, -1]
	table[86] = [8, 4, 7, 9, 0, 5, 0, 6, 5, 0, 2, 6, -1]
	table[87] = [7, 3, 9, 7, 9, 4, 3, 2, 9, 5, 9, 6, 2, 6, 9, -1]
	table[88] = [3, 11, 2, 7, 8, 4, 10, 6, 5, -1]
	table[89] = [5, 10, 6, 4, 7, 2, 4, 2, 0, 2, 7, 11, -1]
	table[90] = [0, 1, 9, 4, 7, 8, 2, 3, 11, 5, 10, 6, -1]
	table[91] = [9, 2, 1, 9, 11, 2, 9, 4, 11, 7, 11, 4, 5, 10, 6, -1]
	table[92] = [8, 4, 7, 3, 11, 5, 3, 5, 1, 5, 11, 6, -1]
	table[93] = [5, 1, 11, 5, 11, 6, 1, 0, 11, 7, 11, 4, 0, 4, 11, -1]
	table[94] = [0, 5, 9, 0, 6, 5, 0, 3, 6, 11, 6, 3, 8, 4, 7, -1]
	table[95] = [6, 5, 9, 6, 9, 11, 4, 7, 9, 7, 11, 9, -1]
	table[96] = [10, 4, 9, 6, 4, 10, -1]
	table[97] = [4, 10, 6, 4, 9, 10, 0, 8, 3, -1]
	table[98] = [10, 0, 1, 10, 6, 0, 6, 4, 0, -1]
	table[99] = [8, 3, 1, 8, 1, 6, 8, 6, 4, 6, 1, 10, -1]
	table[100] = [1, 4, 9, 1, 2, 4, 2, 6, 4, -1]
	table[101] = [3, 0, 8, 1, 2, 9, 2, 4, 9, 2, 6, 4, -1]
	table[102] = [0, 2, 4, 4, 2, 6, -1]
	table[103] = [8, 3, 2, 8, 2, 4, 4, 2, 6, -1]
	table[104] = [10, 4, 9, 10, 6, 4, 11, 2, 3, -1]
	table[105] = [0, 8, 2, 2, 8, 11, 4, 9, 10, 4, 10, 6, -1]
	table[106] = [3, 11, 2, 0, 1, 6, 0, 6, 4, 6, 1, 10, -1]
	table[107] = [6, 4, 1, 6, 1, 10, 4, 8, 1, 2, 1, 11, 8, 11, 1, -1]
	table[108] = [9, 6, 4, 9, 3, 6, 9, 1, 3, 11, 6, 3, -1]
	table[109] = [8, 11, 1, 8, 1, 0, 11, 6, 1, 9, 1, 4, 6, 4, 1, -1]
	table[110] = [3, 11, 6, 3, 6, 0, 0, 6, 4, -1]
	table[111] = [6, 4, 8, 11, 6, 8, -1]
	table[112] = [7, 10, 6, 7, 8, 10, 8, 9, 10, -1]
	table[113] = [0, 7, 3, 0, 10, 7, 0, 9, 10, 6, 7, 10, -1]
	table[114] = [10, 6, 7, 1, 10, 7, 1, 7, 8, 1, 8, 0, -1]
	table[115] = [10, 6, 7, 10, 7, 1, 1, 7, 3, -1]
	table[116] = [1, 2, 6, 1, 6, 8, 1, 8, 9, 8, 6, 7, -1]
	table[117] = [2, 6, 9, 2, 9, 1, 6, 7, 9, 0, 9, 3, 7, 3, 9, -1]
	table[118] = [7, 8, 0, 7, 0, 6, 6, 0, 2, -1]
	table[119] = [7, 3, 2, 6, 7, 2, -1]
	table[120] = [2, 3, 11, 10, 6, 8, 10, 8, 9, 8, 6, 7, -1]
	table[121] = [2, 0, 7, 2, 7, 11, 0, 9, 7, 6, 7, 10, 9, 10, 7, -1]
	table[122] = [1, 8, 0, 1, 7, 8, 1, 10, 7, 6, 7, 10, 2, 3, 11, -1]
	table[123] = [11, 2, 1, 11, 1, 7, 10, 6, 1, 6, 7, 1, -1]
	table[124] = [8, 9, 6, 8, 6, 7, 9, 1, 6, 11, 6, 3, 1, 3, 6, -1]
	table[125] = [0, 9, 1, 11, 6, 7, -1]
	table[126] = [7, 8, 0, 7, 0, 6, 3, 11, 0, 11, 6, 0, -1]
	table[127] = [7, 11, 6, -1]
	table[128] = [7, 6, 11, -1]
	table[129] = [3, 0, 8, 11, 7, 6, -1]
	table[130] = [0, 1, 9, 11, 7, 6, -1]
	table[131] = [8, 1, 9, 8, 3, 1, 11, 7, 6, -1]
	table[132] = [10, 1, 2, 6, 11, 7, -1]
	table[133] = [1, 2, 10, 3, 0, 8, 6, 11, 7, -1]
	table[134] = [2, 9, 0, 2, 10, 9, 6, 11, 7, -1]
	table[135] = [6, 11, 7, 2, 10, 3, 10, 8, 3, 10, 9, 8, -1]
	table[136] = [7, 2, 3, 6, 2, 7, -1]
	table[137] = [7, 0, 8, 7, 6, 0, 6, 2, 0, -1]
	table[138] = [2, 7, 6, 2, 3, 7, 0, 1, 9, -1]
	table[139] = [1, 6, 2, 1, 8, 6, 1, 9, 8, 8, 7, 6, -1]
	table[140] = [10, 7, 6, 10, 1, 7, 1, 3, 7, -1]
	table[141] = [10, 7, 6, 1, 7, 10, 1, 8, 7, 1, 0, 8, -1]
	table[142] = [0, 3, 7, 0, 7, 10, 0, 10, 9, 6, 10, 7, -1]
	table[143] = [7, 6, 10, 7, 10, 8, 8, 10, 9, -1]
	table[144] = [6, 8, 4, 11, 8, 6, -1]
	table[145] = [3, 6, 11, 3, 0, 6, 0, 4, 6, -1]
	table[146] = [8, 6, 11, 8, 4, 6, 9, 0, 1, -1]
	table[147] = [9, 4, 6, 9, 6, 3, 9, 3, 1, 11, 3, 6, -1]
	table[148] = [6, 8, 4, 6, 11, 8, 2, 10, 1, -1]
	table[149] = [1, 2, 10, 3, 0, 11, 0, 6, 11, 0, 4, 6, -1]
	table[150] = [4, 11, 8, 4, 6, 11, 0, 2, 9, 2, 10, 9, -1]
	table[151] = [10, 9, 3, 10, 3, 2, 9, 4, 3, 11, 3, 6, 4, 6, 3, -1]
	table[152] = [8, 2, 3, 8, 4, 2, 4, 6, 2, -1]
	table[153] = [0, 4, 2, 4, 6, 2, -1]
	table[154] = [1, 9, 0, 2, 3, 4, 2, 4, 6, 4, 3, 8, -1]
	table[155] = [1, 9, 4, 1, 4, 2, 2, 4, 6, -1]
	table[156] = [8, 1, 3, 8, 6, 1, 8, 4, 6, 6, 10, 1, -1]
	table[157] = [10, 1, 0, 10, 0, 6, 6, 0, 4, -1]
	table[158] = [4, 6, 3, 4, 3, 8, 6, 10, 3, 0, 3, 9, 10, 9, 3, -1]
	table[159] = [10, 9, 4, 6, 10, 4, -1]
	table[160] = [4, 9, 5, 7, 6, 11, -1]
	table[161] = [0, 8, 3, 4, 9, 5, 11, 7, 6, -1]
	table[162] = [5, 0, 1, 5, 4, 0, 7, 6, 11, -1]
	table[163] = [11, 7, 6, 8, 3, 4, 3, 5, 4, 3, 1, 5, -1]
	table[164] = [9, 5, 4, 10, 1, 2, 7, 6, 11, -1]
	table[165] = [6, 11, 7, 1, 2, 10, 0, 8, 3, 4, 9, 5, -1]
	table[166] = [7, 6, 11, 5, 4, 10, 4, 2, 10, 4, 0, 2, -1]
	table[167] = [3, 4, 8, 3, 5, 4, 3, 2, 5, 10, 5, 2, 11, 7, 6, -1]
	table[168] = [7, 2, 3, 7, 6, 2, 5, 4, 9, -1]
	table[169] = [9, 5, 4, 0, 8, 6, 0, 6, 2, 6, 8, 7, -1]
	table[170] = [3, 6, 2, 3, 7, 6, 1, 5, 0, 5, 4, 0, -1]
	table[171] = [6, 2, 8, 6, 8, 7, 2, 1, 8, 4, 8, 5, 1, 5, 8, -1]
	table[172] = [9, 5, 4, 10, 1, 6, 1, 7, 6, 1, 3, 7, -1]
	table[173] = [1, 6, 10, 1, 7, 6, 1, 0, 7, 8, 7, 0, 9, 5, 4, -1]
	table[174] = [4, 0, 10, 4, 10, 5, 0, 3, 10, 6, 10, 7, 3, 7, 10, -1]
	table[175] = [7, 6, 10, 7, 10, 8, 5, 4, 10, 4, 8, 10, -1]
	table[176] = [6, 9, 5, 6, 11, 9, 11, 8, 9, -1]
	table[177] = [3, 6, 11, 0, 6, 3, 0, 5, 6, 0, 9, 5, -1]
	table[178] = [0, 11, 8, 0, 5, 11, 0, 1, 5, 5, 6, 11, -1]
	table[179] = [6, 11, 3, 6, 3, 5, 5, 3, 1, -1]
	table[180] = [1, 2, 10, 9, 5, 11, 9, 11, 8, 11, 5, 6, -1]
	table[181] = [0, 11, 3, 0, 6, 11, 0, 9, 6, 5, 6, 9, 1, 2, 10, -1]
	table[182] = [11, 8, 5, 11, 5, 6, 8, 0, 5, 10, 5, 2, 0, 2, 5, -1]
	table[183] = [6, 11, 3, 6, 3, 5, 2, 10, 3, 10, 5, 3, -1]
	table[184] = [5, 8, 9, 5, 2, 8, 5, 6, 2, 3, 8, 2, -1]
	table[185] = [9, 5, 6, 9, 6, 0, 0, 6, 2, -1]
	table[186] = [1, 5, 8, 1, 8, 0, 5, 6, 8, 3, 8, 2, 6, 2, 8, -1]
	table[187] = [1, 5, 6, 2, 1, 6, -1]
	table[188] = [1, 3, 6, 1, 6, 10, 3, 8, 6, 5, 6, 9, 8, 9, 6, -1]
	table[189] = [10, 1, 0, 10, 0, 6, 9, 5, 0, 5, 6, 0, -1]
	table[190] = [0, 3, 8, 5, 6, 10, -1]
	table[191] = [10, 5, 6, -1]
	table[192] = [11, 5, 10, 7, 5, 11, -1]
	table[193] = [11, 5, 10, 11, 7, 5, 8, 3, 0, -1]
	table[194] = [5, 11, 7, 5, 10, 11, 1, 9, 0, -1]
	table[195] = [10, 7, 5, 10, 11, 7, 9, 8, 1, 8, 3, 1, -1]
	table[196] = [11, 1, 2, 11, 7, 1, 7, 5, 1, -1]
	table[197] = [0, 8, 3, 1, 2, 7, 1, 7, 5, 7, 2, 11, -1]
	table[198] = [9, 7, 5, 9, 2, 7, 9, 0, 2, 2, 11, 7, -1]
	table[199] = [7, 5, 2, 7, 2, 11, 5, 9, 2, 3, 2, 8, 9, 8, 2, -1]
	table[200] = [2, 5, 10, 2, 3, 5, 3, 7, 5, -1]
	table[201] = [8, 2, 0, 8, 5, 2, 8, 7, 5, 10, 2, 5, -1]
	table[202] = [9, 0, 1, 5, 10, 3, 5, 3, 7, 3, 10, 2, -1]
	table[203] = [9, 8, 2, 9, 2, 1, 8, 7, 2, 10, 2, 5, 7, 5, 2, -1]
	table[204] = [1, 3, 5, 3, 7, 5, -1]
	table[205] = [0, 8, 7, 0, 7, 1, 1, 7, 5, -1]
	table[206] = [9, 0, 3, 9, 3, 5, 5, 3, 7, -1]
	table[207] = [9, 8, 7, 5, 9, 7, -1]
	table[208] = [5, 8, 4, 5, 10, 8, 10, 11, 8, -1]
	table[209] = [5, 0, 4, 5, 11, 0, 5, 10, 11, 11, 3, 0, -1]
	table[210] = [0, 1, 9, 8, 4, 10, 8, 10, 11, 10, 4, 5, -1]
	table[211] = [10, 11, 4, 10, 4, 5, 11, 3, 4, 9, 4, 1, 3, 1, 4, -1]
	table[212] = [2, 5, 1, 2, 8, 5, 2, 11, 8, 4, 5, 8, -1]
	table[213] = [0, 4, 11, 0, 11, 3, 4, 5, 11, 2, 11, 1, 5, 1, 11, -1]
	table[214] = [0, 2, 5, 0, 5, 9, 2, 11, 5, 4, 5, 8, 11, 8, 5, -1]
	table[215] = [9, 4, 5, 2, 11, 3, -1]
	table[216] = [2, 5, 10, 3, 5, 2, 3, 4, 5, 3, 8, 4, -1]
	table[217] = [5, 10, 2, 5, 2, 4, 4, 2, 0, -1]
	table[218] = [3, 10, 2, 3, 5, 10, 3, 8, 5, 4, 5, 8, 0, 1, 9, -1]
	table[219] = [5, 10, 2, 5, 2, 4, 1, 9, 2, 9, 4, 2, -1]
	table[220] = [8, 4, 5, 8, 5, 3, 3, 5, 1, -1]
	table[221] = [0, 4, 5, 1, 0, 5, -1]
	table[222] = [8, 4, 5, 8, 5, 3, 9, 0, 5, 0, 3, 5, -1]
	table[223] = [9, 4, 5, -1]
	table[224] = [4, 11, 7, 4, 9, 11, 9, 10, 11, -1]
	table[225] = [0, 8, 3, 4, 9, 7, 9, 11, 7, 9, 10, 11, -1]
	table[226] = [1, 10, 11, 1, 11, 4, 1, 4, 0, 7, 4, 11, -1]
	table[227] = [3, 1, 4, 3, 4, 8, 1, 10, 4, 7, 4, 11, 10, 11, 4, -1]
	table[228] = [4, 11, 7, 9, 11, 4, 9, 2, 11, 9, 1, 2, -1]
	table[229] = [9, 7, 4, 9, 11, 7, 9, 1, 11, 2, 11, 1, 0, 8, 3, -1]
	table[230] = [11, 7, 4, 11, 4, 2, 2, 4, 0, -1]
	table[231] = [11, 7, 4, 11, 4, 2, 8, 3, 4, 3, 2, 4, -1]
	table[232] = [2, 9, 10, 2, 7, 9, 2, 3, 7, 7, 4, 9, -1]
	table[233] = [9, 10, 7, 9, 7, 4, 10, 2, 7, 8, 7, 0, 2, 0, 7, -1]
	table[234] = [3, 7, 10, 3, 10, 2, 7, 4, 10, 1, 10, 0, 4, 0, 10, -1]
	table[235] = [1, 10, 2, 8, 7, 4, -1]
	table[236] = [4, 9, 1, 4, 1, 7, 7, 1, 3, -1]
	table[237] = [4, 9, 1, 4, 1, 7, 0, 8, 1, 8, 7, 1, -1]
	table[238] = [4, 0, 3, 7, 4, 3, -1]
	table[239] = [4, 8, 7, -1]
	table[240] = [9, 10, 8, 10, 11, 8, -1]
	table[241] = [3, 0, 9, 3, 9, 11, 11, 9, 10, -1]
	table[242] = [0, 1, 10, 0, 10, 8, 8, 10, 11, -1]
	table[243] = [3, 1, 10, 11, 3, 10, -1]
	table[244] = [1, 2, 11, 1, 11, 9, 9, 11, 8, -1]
	table[245] = [3, 0, 9, 3, 9, 11, 1, 2, 9, 2, 11, 9, -1]
	table[246] = [0, 2, 11, 8, 0, 11, -1]
	table[247] = [3, 2, 11, -1]
	table[248] = [2, 3, 8, 2, 8, 10, 10, 8, 9, -1]
	table[249] = [9, 10, 2, 0, 9, 2, -1]
	table[250] = [2, 3, 8, 2, 8, 10, 0, 1, 8, 1, 10, 8, -1]
	table[251] = [1, 10, 2, -1]
	table[252] = [1, 3, 8, 9, 1, 8, -1]
	table[253] = [0, 9, 1, -1]
	table[254] = [0, 3, 8, -1]
	table[255] = [-1]

	# Convert to PackedInt32Array for each entry
	var result: Array = []
	result.resize(256)
	for idx in 256:
		result[idx] = PackedInt32Array(table[idx])
	return result

## Generate mesh for a chunk
## Returns ArrayMesh ready to be displayed
## lod_level: 0 = full detail, 1 = half detail, 2 = quarter detail, etc.
func generate_mesh(chunk, neighbor_chunks: Dictionary = {}, lod_level: int = 0) -> ArrayMesh:
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()

	var chunk_origin: Vector3 = chunk.get_world_origin()

	# Only process Y range with actual surface (huge optimization!)
	var y_range: Vector2i = chunk.get_surface_y_range()
	var min_y_local: int = y_range.x + 128  # Convert world Y to local index
	var max_y_local: int = y_range.y + 128

	# Clamp to valid range
	min_y_local = max(0, min_y_local)
	max_y_local = min(255, max_y_local)

	# LOD step size: lod 0 = step 1, lod 1 = step 2, lod 2 = step 4
	var step: int = 1 << lod_level  # 1, 2, 4, 8...

	# Iterate through voxels only near the surface
	# Process full chunk size - _get_density handles fetching from neighbors for edge cubes
	var x: int = 0
	while x < ChunkDataClass.CHUNK_SIZE_XZ:
		var z: int = 0
		while z < ChunkDataClass.CHUNK_SIZE_XZ:
			var y_local: int = min_y_local
			while y_local < max_y_local:
				_process_cube_lod(chunk, neighbor_chunks, x, y_local, z,
					chunk_origin, vertices, normals, uvs, indices, step)
				y_local += step
			z += step
		x += step

	# Create the mesh
	if vertices.size() == 0:
		return null

	# Validate mesh data before creating surface
	if vertices.size() != normals.size() or vertices.size() != uvs.size():
		push_error("[ChunkMeshGenerator] Array size mismatch: vertices=%d normals=%d uvs=%d" % [vertices.size(), normals.size(), uvs.size()])
		return null

	if indices.size() % 3 != 0:
		push_error("[ChunkMeshGenerator] Invalid index count: %d (must be multiple of 3)" % indices.size())
		return null

	# Additional safety check - ensure indices are valid
	if indices.size() > 0:
		for idx in indices:
			if idx >= vertices.size():
				push_error("[ChunkMeshGenerator] Invalid index %d (vertices size: %d)" % [idx, vertices.size()])
				return null

	var mesh := ArrayMesh.new()
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices

	# Try to add surface - this may fail silently if arrays are malformed
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	# Verify the surface was actually created
	if mesh.get_surface_count() == 0:
		push_error("[ChunkMeshGenerator] Failed to create mesh surface! vertices=%d indices=%d" % [vertices.size(), indices.size()])
		return null

	return mesh

## Process a single cube in the marching cubes algorithm
func _process_cube(chunk, neighbors: Dictionary,
		x: int, y_local: int, z: int, chunk_origin: Vector3,
		vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array) -> void:

	# Get density values at all 8 corners
	var corner_densities: PackedFloat32Array = PackedFloat32Array()
	corner_densities.resize(8)

	var all_inside: bool = true
	var all_outside: bool = true

	for i in 8:
		var offset: Vector3 = CORNER_OFFSETS[i]
		var cx: int = x + int(offset.x)
		var cy: int = y_local + int(offset.y)
		var cz: int = z + int(offset.z)
		var density: float = _get_density(chunk, neighbors, cx, cy, cz)
		corner_densities[i] = density

		# Track if all corners are same side
		if density >= SURFACE_THRESHOLD:
			all_outside = false
		else:
			all_inside = false

	# Early out: if all corners are the same (all solid or all air), skip
	if all_inside or all_outside:
		return

	# Calculate cube index (which corners are inside the surface)
	var cube_index: int = 0
	for i in 8:
		if corner_densities[i] >= SURFACE_THRESHOLD:
			cube_index |= (1 << i)

	# If cube is entirely inside or outside, no triangles needed
	if edge_table[cube_index] == 0:
		return

	# Find vertices where surface intersects cube edges
	var edge_vertices: Array = []
	edge_vertices.resize(12)

	var world_y := ChunkDataClass.local_to_world_y(y_local)

	for i in 12:
		if edge_table[cube_index] & (1 << i):
			var v1_idx: int = EDGE_VERTICES[i][0]
			var v2_idx: int = EDGE_VERTICES[i][1]
			var v1: Vector3 = CORNER_OFFSETS[v1_idx]
			var v2: Vector3 = CORNER_OFFSETS[v2_idx]
			var d1: float = corner_densities[v1_idx]
			var d2: float = corner_densities[v2_idx]

			# Interpolate position where surface crosses edge
			var t: float = (SURFACE_THRESHOLD - d1) / (d2 - d1 + 0.0001)
			t = clamp(t, 0.0, 1.0)

			var world_pos := Vector3(
				chunk_origin.x + x + v1.x + t * (v2.x - v1.x),
				world_y + v1.y + t * (v2.y - v1.y),
				chunk_origin.z + z + v1.z + t * (v2.z - v1.z)
			)
			edge_vertices[i] = world_pos

	# Generate triangles from triangle table
	var tris: PackedInt32Array = tri_table[cube_index]
	var base_vertex: int = vertices.size()

	var i: int = 0
	while i < tris.size() and tris[i] != -1:
		# Safety check - ensure edge vertices exist
		var edge_idx0: int = tris[i]
		var edge_idx1: int = tris[i + 1]
		var edge_idx2: int = tris[i + 2]

		if edge_vertices[edge_idx0] == null or edge_vertices[edge_idx1] == null or edge_vertices[edge_idx2] == null:
			i += 3
			continue

		var v0: Vector3 = edge_vertices[edge_idx0]
		var v1: Vector3 = edge_vertices[edge_idx1]
		var v2: Vector3 = edge_vertices[edge_idx2]

		# Add vertices in reversed order for correct face culling
		var vi: int = vertices.size()
		vertices.append(v0)
		vertices.append(v2)
		vertices.append(v1)

		# Calculate normal for the swapped triangle (v0, v2, v1)
		# For CCW winding viewed from front: normal = (B-A) × (C-A)
		# With A=v0, B=v2, C=v1: normal = (v2-v0) × (v1-v0)
		# But since we swapped winding, we need to negate to point outward
		var normal := (v1 - v0).cross(v2 - v0).normalized()

		# Add normals (same for all 3 vertices of triangle)
		normals.append(normal)
		normals.append(normal)
		normals.append(normal)

		# Add UVs (simple world-space mapping)
		uvs.append(Vector2(v0.x * 0.1, v0.z * 0.1))
		uvs.append(Vector2(v2.x * 0.1, v2.z * 0.1))
		uvs.append(Vector2(v1.x * 0.1, v1.z * 0.1))

		# Add indices
		indices.append(vi)
		indices.append(vi + 1)
		indices.append(vi + 2)

		i += 3

## Process a cube with LOD support (variable step size)
func _process_cube_lod(chunk, neighbors: Dictionary,
		x: int, y_local: int, z: int, chunk_origin: Vector3,
		vertices: PackedVector3Array, normals: PackedVector3Array,
		uvs: PackedVector2Array, indices: PackedInt32Array, step: int) -> void:

	# Get density values at all 8 corners (scaled by step size)
	var corner_densities: PackedFloat32Array = PackedFloat32Array()
	corner_densities.resize(8)

	var all_inside: bool = true
	var all_outside: bool = true

	for i in 8:
		var offset: Vector3 = CORNER_OFFSETS[i]
		var cx: int = x + int(offset.x) * step
		var cy: int = y_local + int(offset.y) * step
		var cz: int = z + int(offset.z) * step
		var density: float = _get_density(chunk, neighbors, cx, cy, cz)
		corner_densities[i] = density

		if density >= SURFACE_THRESHOLD:
			all_outside = false
		else:
			all_inside = false

	if all_inside or all_outside:
		return

	var cube_index: int = 0
	for i in 8:
		if corner_densities[i] >= SURFACE_THRESHOLD:
			cube_index |= (1 << i)

	if edge_table[cube_index] == 0:
		return

	var edge_vertices: Array = []
	edge_vertices.resize(12)

	var world_y := ChunkDataClass.local_to_world_y(y_local)

	for i in 12:
		if edge_table[cube_index] & (1 << i):
			var v1_idx: int = EDGE_VERTICES[i][0]
			var v2_idx: int = EDGE_VERTICES[i][1]
			var v1: Vector3 = CORNER_OFFSETS[v1_idx] * step
			var v2: Vector3 = CORNER_OFFSETS[v2_idx] * step
			var d1: float = corner_densities[v1_idx]
			var d2: float = corner_densities[v2_idx]

			var t: float = (SURFACE_THRESHOLD - d1) / (d2 - d1 + 0.0001)
			t = clamp(t, 0.0, 1.0)

			var world_pos := Vector3(
				chunk_origin.x + x + v1.x + t * (v2.x - v1.x),
				world_y + v1.y + t * (v2.y - v1.y),
				chunk_origin.z + z + v1.z + t * (v2.z - v1.z)
			)
			edge_vertices[i] = world_pos

	var tris: PackedInt32Array = tri_table[cube_index]

	var i: int = 0
	while i < tris.size() and tris[i] != -1:
		var edge_idx0: int = tris[i]
		var edge_idx1: int = tris[i + 1]
		var edge_idx2: int = tris[i + 2]

		if edge_vertices[edge_idx0] == null or edge_vertices[edge_idx1] == null or edge_vertices[edge_idx2] == null:
			i += 3
			continue

		var v0: Vector3 = edge_vertices[edge_idx0]
		var v1: Vector3 = edge_vertices[edge_idx1]
		var v2: Vector3 = edge_vertices[edge_idx2]

		var vi: int = vertices.size()
		vertices.append(v0)
		vertices.append(v2)
		vertices.append(v1)

		# Calculate normal for swapped triangle (v0, v2, v1) - points outward from terrain
		var normal := (v1 - v0).cross(v2 - v0).normalized()

		normals.append(normal)
		normals.append(normal)
		normals.append(normal)

		uvs.append(Vector2(v0.x * 0.1, v0.z * 0.1))
		uvs.append(Vector2(v2.x * 0.1, v2.z * 0.1))
		uvs.append(Vector2(v1.x * 0.1, v1.z * 0.1))

		indices.append(vi)
		indices.append(vi + 1)
		indices.append(vi + 2)

		i += 3

## Get density at a position, checking neighbor chunks if needed
func _get_density(chunk, neighbors: Dictionary, x: int, y_local: int, z: int) -> float:
	# Check if we're still within the chunk
	if x >= 0 and x < ChunkDataClass.CHUNK_SIZE_XZ and z >= 0 and z < ChunkDataClass.CHUNK_SIZE_XZ:
		return chunk.get_voxel(x, y_local, z)

	# Need to check neighbor chunk
	var nx: int = chunk.chunk_x
	var nz: int = chunk.chunk_z

	if x >= ChunkDataClass.CHUNK_SIZE_XZ:
		nx += 1
		x -= ChunkDataClass.CHUNK_SIZE_XZ
	elif x < 0:
		nx -= 1
		x += ChunkDataClass.CHUNK_SIZE_XZ

	if z >= ChunkDataClass.CHUNK_SIZE_XZ:
		nz += 1
		z -= ChunkDataClass.CHUNK_SIZE_XZ
	elif z < 0:
		nz -= 1
		z += ChunkDataClass.CHUNK_SIZE_XZ

	var key := ChunkDataClass.make_key(nx, nz)
	if neighbors.has(key):
		return neighbors[key].get_voxel(x, y_local, z)

	# No neighbor data available - assume air
	return 0.0

## Generate collision shape from mesh
func generate_collision_shape(mesh: ArrayMesh) -> ConcavePolygonShape3D:
	if mesh == null or mesh.get_surface_count() == 0:
		return null

	var shape := ConcavePolygonShape3D.new()
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Build face array from indexed vertices
	var faces := PackedVector3Array()
	for i in range(0, indices.size(), 3):
		faces.append(vertices[indices[i]])
		faces.append(vertices[indices[i + 1]])
		faces.append(vertices[indices[i + 2]])

	shape.set_faces(faces)
	return shape
