class_name Layers
## Physics layer bits shared by all systems. Keep in sync with project.godot [layer_names].

const WORLD := 1 << 0
const PLAYER := 1 << 1
const COLOSSUS := 1 << 2

## Everything a climber or camera can collide with.
const SOLID := WORLD | COLOSSUS
