# Mixamo animations to download for the player (cacB)

For EVERY clip below, use the SAME export settings:
  - Format:  FBX Binary (.fbx)
  - Skin:    "Without Skin"   (we apply these onto cacB's existing skeleton)
  - FPS:     30
  - Keyframe Reduction: none / uniform

Search each on mixamo.com, then Download with the settings above, and
SAVE INTO THIS FOLDER using the exact filename in the left column.

| Save as            | Mixamo search term            | Extra setting          | Used for          |
|--------------------|-------------------------------|------------------------|-------------------|
| idle.fbx           | "Sword And Shield Idle"       | In Place: ON           | standing          |
| run.fbx            | "Sword And Shield Run" (or Run)| In Place: ON          | moving (WASD)     |
| attack_slash.fbx   | "Sword And Shield Slash"      | In Place: ON           | melee (Left click)|
| attack_cast.fbx    | "Standing 2H Magic Attack 01" | In Place: ON           | magic (Right click)|
| hit.fbx            | "Sword And Shield Impact"     | In Place: ON           | taking damage     |
| death.fbx          | "Sword And Shield Death" (or Dying)| In Place: ON      | death             |
| dodge.fbx          | "Sword And Shield Roll" (or Roll)| In Place: ON         | dodge (Ctrl)      |

Optional nice-to-have:
| jump.fbx           | "Jump"                        | In Place: ON           | jump (Space)      |

Notes:
- "Sword And Shield ___" clips keep a consistent fighting style; if a name
  isn't found, any close match works (e.g. plain "Running", "Dying").
- If a clip plays too fast/slow we can retime it in Godot, don't worry about it.
- Don't rename the bones or change the character — just download the motion.
