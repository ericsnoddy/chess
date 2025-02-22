extends Sprite2D

const BOARD_SIZE = 8
const CELL_WIDTH = 18
const HALF_CELL = CELL_WIDTH / 2
const BOARD_LENGTH = CELL_WIDTH * 8

const TEXTURE_HOLDER = preload("res://scenes/texture_holder.tscn")

# preload images
const BLACK_BISHOP = preload("res://assets/black_bishop.png")
const BLACK_KING = preload("res://assets/black_king.png")
const BLACK_KNIGHT = preload("res://assets/black_knight.png")
const BLACK_PAWN = preload("res://assets/black_pawn.png")
const BLACK_QUEEN = preload("res://assets/black_queen.png")
const BLACK_ROOK = preload("res://assets/black_rook.png")
const WHITE_BISHOP = preload("res://assets/white_bishop.png")
const WHITE_KING = preload("res://assets/white_king.png")
const WHITE_KNIGHT = preload("res://assets/white_knight.png")
const WHITE_PAWN = preload("res://assets/white_pawn.png")
const WHITE_QUEEN = preload("res://assets/white_queen.png")
const WHITE_ROOK = preload("res://assets/white_rook.png")

const TURN_BLACK = preload("res://assets/turn-black.png")
const TURN_WHITE = preload("res://assets/turn-white.png")
const PIECE_MOVE = preload("res://assets/Piece_move.png")

@onready var pieces := $Pieces
@onready var dots := $Dots
@onready var turn := $Turn

# Positive numbers are white, negative numbers are black; values are:
# 6 King
# 5 Queen
# 4 Rook
# 3 Bishop
# 2 Knight
# 1 Pawn
# 0 (empty square)

# variables
# hold the position of a piece: board[0][0] is index of piece at [0,0]
var board : Array
# white's turn = true, black's turn = false
var white : bool = true
# Two states for the player: "selecting" = selecting a move, "confirming" = confirming the move
var state : String = "selecting"
# hold possible moves for currently selected piece
var moves := []
# hold information on (white, black) pawn 1st pawn movement starting in col = 0
var pawn_data : Array[Vector2]
var selected_piece : Vector2
# Move history... pos : (x,y) = (row,col) piece: (z,w) = (moved, captured = 0)
var move_history : Array[Vector4] = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# bottom-left is [0,0]: see key above for piece values
	board.append([4, 2, 3, 6, 5, 3, 2, 4])	# white pieces, [0,0] -> [0,7]
	board.append([1, 1, 1, 1, 0, 1, 1, 1])	# [1,0] -> [1,7]
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([-1, -1, -1, -1, -1, -1, -1, -1])
	board.append([-4, -2, -3, -6, -5, -3, -2, -4])	# [7,0] -> [7,7]
	
	display_board()
	
	# this holds data on pawns' first moves: 0 (no move) or 1 or 2 (spaces):
	# for determining move, capture, and en passant eligibilities
	pawn_data.resize(8)
	pawn_data.fill(Vector2())
	
	## debug
	#pawn_data[5] = Vector2(2,0)
	#pawn_data[6] = Vector2(0,2)
	#move_history.append_array([Vector4(4,5,1,0), Vector4(4, 6, -1, 0)])

func _input(event) -> void:
	if event is InputEventMouseButton && event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# don't register interaction if mouse is outside area of the board
			var mouse_pos : Vector2 = get_global_mouse_position()
			if is_mouse_out(mouse_pos): 
				return
			# nearest whole number / cell width = row/col index
			# Coords are relative to the CanvasItem, not main display screen
			# hence why we have to remove negatives from the y-part
			var col = snapped(mouse_pos.x, 0) / CELL_WIDTH
			var row = abs(snapped(mouse_pos.y, 0)) / CELL_WIDTH
			
			# If in selection mode: If it's white's turn and a white piece is selected,
			# or it's black turn and a black piece is selected:
			if state == "selecting":
				if (white and board[row][col] > 0) or (!white and board[row][col] < 0):
					selected_piece = Vector2(row, col)
					show_options()
					state = "confirming"


func show_options() -> void:
	moves = get_moves(selected_piece)
	# If there are no legal moves, revert to previous state
	if moves.is_empty():
		state = "selecting"
		return
	show_dots()


func show_dots() -> void:
	for move in moves:
		var holder := TEXTURE_HOLDER.instantiate()
		dots.add_child(holder)
		holder.texture = PIECE_MOVE
		# (row, col)
		holder.global_position = Vector2(move.y * CELL_WIDTH + HALF_CELL, -move.x * CELL_WIDTH - HALF_CELL)


func get_moves(piece: Vector2) -> Array:
	var valid_moves : Array[Vector2] = []
	var target : int = board[piece.x][piece.y]
	# Remember vars are relative to the Array so here x is the ROW not the column
	match abs(target):
		1: valid_moves = get_pawn_moves(selected_piece)
		2: valid_moves = get_knight_moves(selected_piece)
		3: valid_moves = get_bishop_moves(selected_piece)
		4: valid_moves = get_rook_moves(selected_piece)
		5: valid_moves = get_queen_moves(selected_piece)
		6: valid_moves = get_king_moves(selected_piece)
	return valid_moves
	

# Logic for possible moves for each piece
func is_in_bounds(coords: Vector2) -> bool:
	# First check that the coords exist (on board)
	if coords.x >= 0 and coords.x < BOARD_SIZE and coords.y >= 0 and coords.y < BOARD_SIZE:
		return true
	return false
	
	
func is_empty(coords: Vector2) -> bool:
	return board[coords.x][coords.y] == 0
	
	
func is_opponent(coords: Vector2) -> bool:
	var piece : int = board[coords.x][coords.y]
	# if white and piece is black (or vice versa) - valid
	if (white and piece < 0) or (!white and piece > 0):
		return true
	return false


func is_last_move(pos: Vector2) -> bool:
	var last_move : Vector4 = move_history.back()
	return pos == Vector2(last_move.x, last_move.y)


# 1 - PAWN
func get_pawn_moves(pawn: Vector2) -> Array[Vector2]:
	# Pawn can move forward or diagonally if capturing, or 1 or 2 spaces first move
	# or en passante if 1 square into opponents half AND opp moves 2 forward prev move
	var _moves : Array[Vector2] = []
	
	# Get info if pawn has moved yet 2 - yes two, 1 - yes one, 0 - no
	var col_data : Vector2 = pawn_data[selected_piece.y]
	var pawn_spaces = col_data.x if white else col_data.y
	# determine if pawn has moved yet and how many spaces
	var has_moved : int = col_data.x if white else col_data.y
	
	# Build array of possible directions - white is always moving up
	var directions : Array[Vector2] = []
	if white:
		directions = [Vector2(1,0)]
		if has_moved == 0:
			directions.append(Vector2(2,0))
		directions.append_array([Vector2(1,-1), Vector2(1,1)])
	else:
		directions = [Vector2(-1,0)]
		if has_moved == 0:
			directions.append(Vector2(-2,0))
		directions.append_array([Vector2(-1,-1), Vector2(-1,1)])
	# check passant
	directions.append_array([Vector2(0,-1), Vector2(0,1)])

	# check directions
	var pos : Vector2 = pawn

	for dir in directions:
		pos += dir
		if is_in_bounds(pos):
			# check vertical
			if dir.y == 0 and !is_opponent(pos):
				_moves.append(pos)
			# check passant left - 
			elif dir == Vector2(0,-1):
				if is_opponent(pos) and can_passant(pos):
					_moves.append(pos)
			# check passant right
			elif dir == Vector2(0,1):
				if is_opponent(pos) and can_passant(pos):
					_moves.append(pos)
			# check diagonals
			else:
				if is_opponent(pos):
					_moves.append(pos)
		pos = pawn
	return _moves


# accepts a position to check - left OR right
func can_passant(pos) -> bool:
	# from last_move: (w,x) is (row, col) and (y,z) is (move, capture) info
	var last_move : Vector4 = move_history.back()
	# must be one row past center
	if (white and selected_piece.x == 4) or (!white and selected_piece.x == 3):
		# must have opponent directly to the left or right who moved last turn
		if is_opponent(pos) and is_last_move(pos):
			# must be a pawn
			if abs(last_move.z) == 1:
				# returns (white pawn moved, black pawn moved) for col index
				var moved : Vector2 = pawn_data[last_move.y]
				# Must have moved 2 spaces
				if (white and moved.y == 2) or (!white and moved.x == 2):
					return true
	return false


# 2 - KNIGHT
func get_knight_moves(knight: Vector2) -> Array[Vector2]:
	var _moves : Array[Vector2] = []

	# could also split into halves or quadrants but whatever
	var directions: Array[Vector2] = [
		Vector2(2,1), Vector2(1,2), Vector2(-1,2), Vector2(-2,1), 
		Vector2(-2,-1), Vector2(-1,-2), Vector2(1,-2), Vector2(2, -1)
	]
	for dir in directions:
		var pos : Vector2 = knight
		pos += dir
		if is_in_bounds(pos) and is_empty(pos):
			_moves.append(pos)
		pos = knight
	return _moves


# 3 - BISHOP
func get_bishop_moves(bishop: Vector2) -> Array[Vector2]:
	# Similar logic to ROOK and QUEEN below (see ROOK for comments)
	var _moves : Array[Vector2] = []
	var directions_diag = [Vector2(1,-1), Vector2(-1,-1), Vector2(1,1), Vector2(-1,1)]
	
	for dir in directions_diag:
		var pos := bishop
		pos += dir
		while is_in_bounds(pos):
			if is_empty(pos):
				_moves.append(pos)
			elif is_opponent(pos):
				_moves.append(pos)
				break
			else:
				break
			pos += dir
	return _moves

# 4 - ROOK
func get_rook_moves(rook: Vector2) -> Array[Vector2]:
	var _moves : Array[Vector2] = []
	# look down, up, left, right
	var directions := [Vector2.DOWN,Vector2.UP, Vector2.RIGHT, Vector2.LEFT]
	# Check in each direction for valid moves until see own piece or out of bounds
	for dir in directions:
		var pos := rook
		pos += dir
		# keep checking until end of board
		while is_in_bounds(pos):
			# if empty or opponent, the move is valid: add pos to list
			if is_empty(pos):
				_moves.append(pos)
			elif is_opponent(pos):
				_moves.append(pos)
				break
			# All valid moves exhausted, check the next direction
			else:
				break 
			pos += dir
	return _moves


# 5 - QUEEN
func get_queen_moves(queen: Vector2) -> Array[Vector2]:
	# Similar logic as ROOK
	var _moves : Array[Vector2] = []
	var directions = [
		Vector2(0,-1),Vector2(0,1), Vector2(1,0), Vector2(-1,0),
		Vector2(1,-1), Vector2(-1,-1), Vector2(1,1), Vector2(-1,1)
	]
	
	for dir in directions:
		var pos := queen
		pos += dir
		while is_in_bounds(pos):
			if is_empty(pos):
				_moves.append(pos)
			elif is_opponent(pos):
				_moves.append(pos)
				break
			else:
				break
			pos += dir
	return _moves


# 6 - KING
func get_king_moves(king: Vector2) -> Array[Vector2]:
	var _moves : Array[Vector2] = []
	var directions : Array[Vector2] = [
		Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(-1,1),
		Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1)
	]
	var pos : Vector2 = king
	for dir in directions:
		pos += dir
		if is_in_bounds(pos) && is_empty(pos) && not is_in_check(pos):
			_moves.append(pos)
		pos = king
	return _moves

func is_in_check(check_pos: Vector2) -> bool:
	# temporarily change color to get proper movesets
	white = !white
	var opp_moves : Array[Vector2] = []

	return false
	
	
func is_in_check2(check_pos: Vector2, directions: Array[Vector2]) -> bool:
	print("check pos: %s" % [check_pos])
	# directions for bishop, rook, queen
	var directions_extended : Array[Vector2] = [
		Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(-1,1),
		Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1)
	]
	# directions for knights
	var directions_knight : Array[Vector2] = [
		Vector2(2,1), Vector2(1,2), Vector2(-1,2), Vector2(-2,1), 
		Vector2(-2,-1), Vector2(-1,-2), Vector2(1,-2), Vector2(2, -1)
	]
	# direction for pawns, combining white and black
	var directions_pawn : Array[Vector2] = [Vector2(1,-1), Vector2(1,1), Vector2(-1,-1), Vector2(-1,1)]
	
	# check rooks, bishops, and queens
	for dir in directions_extended:
		var pos = check_pos
		pos += dir
		while is_in_bounds(pos):
			var opp : int = board[pos.x][pos.y]
			# if a pawn or knight in the way, safe
			if abs(opp) == 1 || abs(opp) == 2:
				print("pawn or knight blocks: %s" % [pos])
				break
			# if own color in the way, safe
			if (white && opp > 0) || (!white && opp < 0):
				print("own piece blocks: %s" % [pos])
				break
			if white && (opp == -3 || opp == -4 || opp == -5):
				print ("1 opp at %s" % pos)
				return false
			if !white && (opp == 3 || opp == 4 || opp == 5):
				print ("2 opp at %s" % pos)
				return false
			pos += dir
		pos = check_pos
		
	# check knight positions
	for dir in directions_knight:
		var pos = check_pos
		pos += dir
		if (white && board[pos.x][pos.y] == -2) || (!white && board[pos.x][pos.y] == 2):
			print ("3 opp at %s" % pos)
			return false
		pos = check_pos
		
	# check pawn positions
	for dir in directions_pawn:
		var pos = check_pos
		pos += dir
		var piece : int = board[pos.x][pos.y]
		if (white && piece < 0 && pos.x > 0) || (!white && piece > 0 && pos.x < 0):
			print ("4 opp at %s" % pos)
			return false
		pos = check_pos
		
	return true


func is_mouse_out(mouse_pos: Vector2) -> bool:
	if (
		mouse_pos.x < 0 or mouse_pos.x > BOARD_LENGTH 
		or mouse_pos.y > 0 or mouse_pos.y < -BOARD_LENGTH
	):
		return true
	return false	


func display_board() -> void:
	for row in BOARD_SIZE:
		for col in BOARD_SIZE:
			# make a temporary sprite; we'll give it a position and a texture
			var holder := TEXTURE_HOLDER.instantiate()
			pieces.add_child(holder)
			holder.global_position = Vector2(col * CELL_WIDTH + HALF_CELL, -row * CELL_WIDTH - HALF_CELL)
			
			match board[row][col]:
				-6: holder.texture = BLACK_KING
				-5: holder.texture = BLACK_QUEEN
				-4: holder.texture = BLACK_ROOK
				-3: holder.texture = BLACK_BISHOP
				-2: holder.texture = BLACK_KNIGHT
				-1: holder.texture = BLACK_PAWN
				0: holder.texture = null				
				6: holder.texture = WHITE_KING
				5: holder.texture = WHITE_QUEEN
				4: holder.texture = WHITE_ROOK
				3: holder.texture = WHITE_BISHOP
				2: holder.texture = WHITE_KNIGHT
				1: holder.texture = WHITE_PAWN
