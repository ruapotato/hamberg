class_name PlayerConstants
extends RefCounted

## Player Constants - All tunable player parameters in one place
## Import with: const PC = preload("res://shared/player/player_constants.gd")
## Access with: PC.WALK_SPEED, PC.MAX_STAMINA, etc.

# =============================================================================
# MOVEMENT
# =============================================================================
const WALK_SPEED: float = 5.0
const SPRINT_SPEED: float = 8.0
const JUMP_VELOCITY: float = 10.0
const ACCELERATION: float = 10.0
const FRICTION: float = 8.0
const AIR_CONTROL: float = 0.3
const HEAD_HEIGHT: float = 1.50
const STEP_HEIGHT: float = 0.35  # Max height for auto-step (stairs, floor boards)

# =============================================================================
# COMBAT - BASIC ATTACKS
# =============================================================================
const ATTACK_COOLDOWN_TIME: float = 0.3
const ATTACK_ANIMATION_TIME: float = 0.3
const KNIFE_ANIMATION_TIME: float = 0.225  # 25% faster
const SWORD_ANIMATION_TIME: float = 0.3
const AXE_ANIMATION_TIME: float = 0.45

# =============================================================================
# COMBAT - COMBOS
# =============================================================================
const COMBO_WINDOW: float = 1.2  # Time to continue combo
const MAX_COMBO: int = 3

# =============================================================================
# COMBAT - SPECIAL ATTACKS
# =============================================================================
const SPECIAL_ATTACK_ANIMATION_TIME: float = 0.5
const KNIFE_SPECIAL_ANIMATION_TIME: float = 0.4  # Lunge
const SWORD_SPECIAL_ANIMATION_TIME: float = 0.6  # Jab
const AXE_SPECIAL_ANIMATION_TIME: float = 0.8   # Spin
const LUNGE_FORWARD_FORCE: float = 15.0
const LUNGE_HIT_RADIUS: float = 1.5

# =============================================================================
# BLOCKING & PARRY
# =============================================================================
const PARRY_WINDOW: float = 0.2  # Parry timing window
const BLOCK_DAMAGE_REDUCTION: float = 0.8  # 80% reduction
const BLOCK_SPEED_MULTIPLIER: float = 0.4  # 40% speed while blocking

# =============================================================================
# STUN
# =============================================================================
const STUN_DURATION: float = 1.5
const STUN_DAMAGE_MULTIPLIER: float = 1.5  # Extra damage when stunned

# =============================================================================
# STAMINA
# =============================================================================
const BASE_STAMINA: float = 50.0  # Base stamina without food
const MAX_STAMINA: float = 200.0  # Maximum possible with best food
const STAMINA_REGEN_RATE: float = 6.0  # Per second (reduced from 15)
const STAMINA_REGEN_DELAY: float = 1.0  # Delay after use
const SPRINT_STAMINA_DRAIN: float = 10.0  # Per second
const JUMP_STAMINA_COST: float = 10.0
const EXHAUSTED_RECOVERY_THRESHOLD: float = 0.10  # 10% to recover
const EXHAUSTED_SPEED_MULTIPLIER: float = 0.6  # 60% speed when exhausted

# =============================================================================
# BRAIN POWER (MAGIC)
# =============================================================================
const BASE_BRAIN_POWER: float = 25.0  # Base BP without food
const MAX_BRAIN_POWER: float = 150.0  # Maximum possible with best food
const BRAIN_POWER_REGEN_RATE: float = 5.0  # Per second (reduced from 10)
const BRAIN_POWER_REGEN_DELAY: float = 2.0  # Delay after use

# =============================================================================
# HEALTH
# =============================================================================
const BASE_HEALTH: float = 25.0  # Base health without food (fragile!)
const MAX_HEALTH: float = 200.0  # Maximum possible with best food
const FALL_DEATH_TIME: float = 15.0  # Seconds below ground before death

# =============================================================================
# FOOD SYSTEM (Valheim-style)
# =============================================================================
const MAX_FOOD_SLOTS: int = 3  # Can eat up to 3 different foods
const FOOD_DECAY_WARNING: float = 120.0  # Warn when food has 2 min left

# =============================================================================
# NETWORKING
# =============================================================================
const MAX_INPUT_HISTORY: int = 60  # 2 seconds at 30 fps
const INTERPOLATION_DELAY: float = 0.1  # 100ms

# =============================================================================
# ANIMATION
# =============================================================================
const LANDING_ANIMATION_TIME: float = 0.2

# =============================================================================
# TERRAIN
# =============================================================================
const TERRAIN_PREVIEW_DURATION: float = 0.8
