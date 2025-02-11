extends KinematicBody2D

class_name Ant

signal ant_name_label(a)
signal ant_fitness_label(a)
signal ant_motivation_label(a)
signal tile_detection_label(a,b)
signal collision_detection_label(a,b)
signal distance_to_home_label(a)

var AntsTileMap

export(Array, int, 1, 100) var hidden_layers_sizes:Array = [6, 3]

var life_timer : int = 0 
#var max_life_timer : int = 0 
var spawn_timer : int = 0
var cycle_timer : int = 0 
var cycle_left_timer : int = 0
var cycle_right_timer : int = 0
var collision_tiles_kill_timer : int = 0
var notMoving_timer : int = 0

var spawn : bool = false
var is_dead : bool = false #Ant isn't alive
var is_ready:bool = false #Ant is finished learning and is ready for population
var is_spawned:bool = true
var is_selected: bool = false #Ant is selected by mouse-click
var is_connected_to_GUI: bool = false

onready var start_tile : Vector2 = get_parent().get_parent().get_parent().get_HivePosition() #ants starting position on tileMap

var mapPosition_ant #ants actual position on tileMap
var mapPosition_ant_before #ants old position on tileMap
var last_used_tiles:Array #memory of last used tiles
var cycle_punishing_memorySize : int = 30 #size of memory from "last_used_tiles"
var cycle_punishing_countLimit : int = 3 #punish after X-double-used tiles

export (float) var rotation_speed = .03
export (float) var baseVelocity : float = 1.0
export (float) var speedFactor : float = 2
var velocity : float = baseVelocity * speedFactor
var collision : KinematicCollision2D

var inputs:Array = []
var inputs_written_0_und_1 : bool = false
var inputs_written_2_und_3 : bool = false

var ants_task : int #Actual task of the ant
var distance_to_home

var Organism = preload("res://neft_godot/scenes/Organism.tscn")
var Organism_Instance
var input_count = 0

var map_size = 5000 #HACK needs to be set to the actual map size 

var GUI

# Called when the node enters the scene tree for the first time.
func _ready():
	GUI = get_parent().get_parent().get_parent().get_node("GUI") #HACK implement Global GUI
	ants_task = 1 #Set ants starting Task to SEARCHING
	
	### SetUp instance of Organism ############################################
	Organism_Instance = Organism.instance()
	
	if Global.Option_Input_DistanceToNest:
		input_count = input_count + 1
	if Global.Option_Input_Rotation:
		input_count = input_count + 1
	if Global.Option_Input_Coordinations:
		input_count = input_count + 2
	if Global.Option_Input_CollisionDetection:
		input_count = input_count + 2
	if Global.Option_Input_TileDetection:
		input_count = input_count + 2
	
	Organism_Instance.input_size = input_count
	
	if Global.Option_Auto_HiddenLayerSizes:
		var layer1:int = int(ceil((input_count+1)/3*2)) #+1 for one output. #HACK: Formel doesn't work right (maybe does...confused becaused the +1, so check again later)
		var layer2:int = int(ceil(layer1/2))
		hidden_layers_sizes = [layer1, layer2]
		#print(hidden_layers_sizes)
	else: #FIXME whole else doesn't work
		var hiddenLayerStringArray = Global.Option_value_HiddenLayerSizes.split(",")
		for layerAsString in hiddenLayerStringArray:
			hidden_layers_sizes.append(int(layerAsString))
		#print(hidden_layers_sizes)
	
	Organism_Instance.hidden_layers_sizes = hidden_layers_sizes
	
	add_child(Organism_Instance)
	###########################################################################
	killThisOrganism(0) #Initial kill, to force spawn-timer!


func _physics_process(_delta):
	if is_selected:
		if !is_connected_to_GUI:
			connect("ant_name_label", GUI, "_on_Ant_ant_name_label")
			connect("ant_fitness_label", GUI, "_on_Ant_ant_fitness_label")
			connect("ant_motivation_label", GUI, "_on_Ant_ant_motivation_label")
			connect("tile_detection_label", GUI, "_on_Ant_tile_detection_label")
			connect("collision_detection_label", GUI, "_on_Ant_collision_detection_label")
			connect("distance_to_home_label", GUI, "_on_Ant_distance_to_home_label")
			is_connected_to_GUI = true
		emit_signal("ant_fitness_label", $Organism.get_fitness())
	
	AntsTileMap = get_parent().get_parent().get_parent().get_TileMap()
	if spawn:
		if spawn_timer == 0:
			respawn()
		spawn_timer = spawn_timer - 1
	
	if !is_dead: #"While" ant is living
		inputs = [] #Reset Array
		mapPosition_ant = AntsTileMap.world_to_map(self.position) 
		distance_to_home = (self.position).distance_to(start_tile)
		if Global.Option_Input_DistanceToNest:
			if is_selected:
				emit_signal("distance_to_home_label", distance_to_home/map_size)
			inputs.insert(inputs.size(), distance_to_home/map_size)
		
		if Global.Option_Input_Rotation:
			inputs.insert(inputs.size(), normalizeRotation(self.rotation_degrees+180))
		
		if Global.Option_Input_Coordinations:
			inputs.insert(inputs.size(), self.position.x/map_size)
			inputs.insert(inputs.size(), self.position.y/map_size)
		
		if Global.Option_lifeTimer:
			life_timer = life_timer + 1
			if is_selected:
				emit_signal("ant_motivation_label", Global.Option_value_lifeTimer - life_timer)
			if life_timer == Global.Option_value_lifeTimer: #3000 #ants "standard" living-cycle (possible to be resetted for good work)
				killThisOrganism(1)
				life_timer = 0

#		if Global.Option_maxLifeTimer:
#			max_life_timer = max_life_timer + 1
#			if max_life_timer == Global.Option_value_maxLifeTimer: #15000
#				killThisOrganism(1)
#				max_life_timer = 0
			
		match ants_task:
			1:  #SEARCH Searching for ... new Areas and Things
				searching()
				scan_for_collision() 
				scan_for_tiles() 
				kill_ant_for_cycling()
			2:  #DRAW TRAIL Drawing a pheremone trail back to home/nest/...
				draw_pheremone_trail() 
			3:  #CARRY Carrying something back to home/nest/...
				pass 
		
		organism_IO() #steer-organism


func move_ant(direction) -> void:
	collision = move_and_collide(direction)
	if direction != Vector2(0, 0):
		$AnimatedSprite.play()
	else:
		$AnimatedSprite.stop()
	if collision != null:
		collision_tiles_kill_timer = collision_tiles_kill_timer + 1
		if collision_tiles_kill_timer == 120:
			collision_tiles_kill_timer = 0
			killThisOrganism(2)
	else:
		collision_tiles_kill_timer = 0


func searching() -> void:
	var direction : Vector2 = Vector2(0, velocity).rotated(rotation)
	move_ant(direction)
	
	var cell_index = AntsTileMap.get_cellv(mapPosition_ant)
	if cell_index == 2:
		found_new_Area(mapPosition_ant)
	if cell_index == 1:
		found_way()


func draw_pheremone_trail() -> void:
	var direction : Vector2 = mapPosition_ant.direction_to(start_tile) * speedFactor
	move_ant(direction)
	AntsTileMap.set_cellv(mapPosition_ant, 1)


func carry_to_home():
	pass


func scan_for_collision() -> void:
	var leftCollisionPoint : Vector2 = $antennae_left.get_collision_point()
	var leftCollisionDistance : float = leftCollisionPoint.distance_to($antennae_left.get_global_transform().get_origin())
	var antennae_left : float = normalizeDistance(leftCollisionDistance)
	
	var rightCollisionPoint : Vector2 = $antennae_right.get_collision_point()
	var rightCollisionDistance : float = rightCollisionPoint.distance_to($antennae_right.get_global_transform().get_origin())
	var antennae_right : float = normalizeDistance(rightCollisionDistance)
	
	if Global.Option_Input_CollisionDetection:
		if is_selected:
			#print(leftCollisionDistance, " / ", rightCollisionDistance) 
			emit_signal("collision_detection_label", antennae_left, antennae_right)
		inputs.insert(inputs.size(), antennae_left) #FIXME !!!!! seems that the collision detection doesn't point in right direction.
		inputs.insert(inputs.size(), antennae_right)


func scan_for_tiles() -> void:
	var mapPosition_leftAntennae = AntsTileMap.world_to_map($antennaes.get_global_transform().origin+$antennaes.points[0].rotated(rotation)) 
	var cell_index_leftAntennae = AntsTileMap.get_cellv(mapPosition_leftAntennae)
	var normalizedTileIndex_leftAntennae  = normalizeTile(cell_index_leftAntennae)
	
	var rightAntennae_mapPosition = AntsTileMap.world_to_map($antennaes.get_global_transform().origin+$antennaes.points[2].rotated(rotation))
	var cell_index_rightAntennae = AntsTileMap.get_cellv(rightAntennae_mapPosition)
	var normalizedTileIndex_rightAntennae  = normalizeTile(cell_index_rightAntennae)
	
	if Global.Option_Input_TileDetection:
		if is_selected:
			emit_signal("tile_detection_label", normalizedTileIndex_leftAntennae,normalizedTileIndex_rightAntennae)
		inputs.insert(inputs.size(), normalizedTileIndex_leftAntennae)
		inputs.insert(inputs.size(), normalizedTileIndex_rightAntennae)
	

func organism_IO():
	var output:Array = [0]
	output = $Organism.think(inputs)
#	if is_selected:
#		print("Output: ", output)
	if output[0] > 0.5:
		steer_left()
	elif output[0] < -0.5:
		steer_right()
	else:
		cycle_left_timer = 0
		cycle_right_timer = 0


func kill_ant_for_cycling():
	if cycle_left_timer >= 300 || cycle_right_timer >= 300:
		killThisOrganism(3)


func found_new_Area(var _world2mapPosition):
	$Organism.add_fitness(1.1+(distance_to_home/50000)) #HACK #Fitness for finding new areas
	life_timer = 0 #Extend Lifecicle
	AntsTileMap.set_cellv(_world2mapPosition, 3)


func found_way():
	$Organism.add_fitness(0.1+(distance_to_home/50000))
	if collision == null:
		life_timer = 0 #Extend Lifecicle


func found_water():
	$Organism.add_fitness(0.6)
	life_timer = 0 #Extend Lifecicle
	self.rotation = mapPosition_ant.direction_to(start_tile).angle() - deg2rad(90)


func steer_right() -> void:
		rotate(rotation_speed * speedFactor)
		cycle_right_timer = cycle_right_timer +1


func steer_left() -> void:
		rotate(-rotation_speed * speedFactor)
		cycle_left_timer = cycle_left_timer +1


func get_is_ready() -> bool:
	return is_ready #Ant is finished learning and is ready for population


func get_is_spawned() -> bool:
	return is_spawned


func get_ant_position():
	return self.position


func reset() -> void:
#	var min_rotation = 0
#	var max_rotation = 359
#	var random_rotation = rand_range(min_rotation, max_rotation)
	start_tile = get_parent().get_parent().get_parent().get_HivePosition()
	transform = Transform2D(0, start_tile) #Resets the 2D-Rotation and 2D-Position by "transform" in Inspektor 


func respawn() -> void:
	is_ready = false
	visible = true
	is_dead = false
	spawn_timer = 0
	spawn = false
	is_spawned = true


func trigger_respawn(given_spawn_timer) -> void:
	spawn_timer = given_spawn_timer
	spawn = true
	is_spawned = false


func killThisOrganism(kill_reason:int) -> void:
	$AnimatedSprite.stop()
	if is_selected: 
		if kill_reason == 0:
			print(self.name, " just initial-kill, to force spawn countdown. (Fitness: ", $Organism.get_fitness(),")") #HACK Man könnte sie auch am Anfang gleich tot spawnen lassen, um ein unnötiges new_generation zu vermeiden!
		if kill_reason == 1:
			print(self.name, " has killed over Time. (Fitness: ", $Organism.get_fitness(),")")
		elif kill_reason == 2:
			print(self.name, " has killed by Collision. (Fitness: ", $Organism.get_fitness(),")")
		elif kill_reason == 3:
			print(self.name, " has killed for Cicling. (Fitness: ", $Organism.get_fitness(),")")
		elif kill_reason == 4:
			print(self.name, " by Button. (Fitness: ", $Organism.get_fitness(),")") #FIXME Killbutton killt nicht zuverlässig
		elif kill_reason == 5:
			print(self.name, " has killed for not Moving. (Fitness: ", $Organism.get_fitness(),")")
		elif kill_reason == 6:
			print(self.name, " has killed by Daytime. (Fitness: ", $Organism.get_fitness(),")")
		elif kill_reason == 7:
			print(self.name, " has killed by changing Level. (Fitness: ", $Organism.get_fitness(),")")
	is_ready = true
	is_dead = true
	visible = false
	last_used_tiles.clear()
	
	
func normalizeDistance(distanceToNormalize : float) -> float:
	if distanceToNormalize > 1000: #FIXME
		return 1.0
	return distanceToNormalize / 1000


func normalizeTile(tile_index : float) -> float:
	if (tile_index+1) >= 5 || tile_index < 0:
		return 1.0
	return ((tile_index+1) / 5)


func normalizeRotation(ants_rotation : float) -> float:
	ants_rotation = ants_rotation +1
	if ants_rotation <= 0:
		ants_rotation = 1
	
	if ants_rotation >= 361:
		return 1.0
	return ants_rotation / 361


func select_ant():
	$AnimatedSprite.modulate = Color(255, 255, 0, 255)
	emit_signal("ant_name_label", self.name)
	is_connected_to_GUI = false
	is_selected = true




func unselect_ant():
	$AnimatedSprite.modulate = Color(1, 1, 1, 1)
	emit_signal("ant_name_label", "/")
	emit_signal("ant_motivation_label", 0)
	is_selected = false



#-------------------------------------------------------------------------------
#In the object's code that you want to train, update the fitness with the methods of Organism
#    get_fitness()
#    set_fitness(new_fitness)
#    add_fitness(amount)
#-------------------------------------------------------------------------------
#Emine Junior - February 27, 2019
#1. create a population with as members as possible
#2. Create fitness for each member of the population. this fitness is based on 
#   certain goals you would have set for each member of the population.
#3. identify, breed and train these members with best fitness.
#4. Change the other members of the populations with less fitness, so that they
#   have the acceptable level of fitness as set by you based on some predefined goals.
#5. kill from the network those members with still lesser fitness level after step 4
#6. repeat step 2 until you maximize your network.
