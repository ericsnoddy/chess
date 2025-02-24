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
# Two states for the player: "selecting" and "confirming""
var state : String = "selecting"
# hold possible moves for currently selected piece
var moves := []
# pos of currently selected piece
var selected_piece : Vector2
# Move history... index is turn number, element is dict with move data
var history : Array[Dictionary] = []
# holds the pos of the captured piece during en passant, for special handling
var en_passant := Vector2()

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# bottom-left is [0,0]: see key above for piece values
	board.append([4, 2, 3, 6, 5, 3, 2, 4])	# white pieces, [0,0] -> [0,7]
	board.append([1, 1, 1, 1, 1, 1, 1, 1])	# [1,0] -> [1,7]
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([-1, -1, -1, -1, -1, -1, -1, -1])
	board.append([-4, -2, -3, -6, -5, -3, -2, -4])	# [7,0] -> [7,7]
	
	# only calls display_board() once on _ready - make sure to call it below in the game loop
	display_board()


func _input(event) -> void:
	if event is InputEventMouseButton && event.pressed:
		if event.button_index == MOUSE_BUTTON_LEFT:
			var mouse_pos : Vector2 = get_global_mouse_position()
			# don't register interaction if mouse is outside area of the board
			if is_mouse_out(mouse_pos): 
				return
			# nearest whole number / cell width = row/col index
			# Coords are relative to the CanvasItem, not main display screen
			# hence why we have to abs() the y-part - we'll use up = +y for rows
			var col : int = snapped(mouse_pos.x, 0) / CELL_WIDTH
			var row : int = abs(snapped(mouse_pos.y, 0)) / CELL_WIDTH
			
			# Route the click depending on the state
			if state == "selecting":
				# make sure the selected position is eligible before showing options
				if (white and board[row][col] > 0) or (!white and board[row][col] < 0):
					selected_piece = Vector2(row, col)
					show_options()
					state = "confirming"
			# if options are shown we check if option is taken and then move if so
			elif state == "confirming":
				# if another piece is selected before moving, remove dots, change state
				set_move(row, col)
				state = "selecting"


func is_mouse_out(mouse_pos: Vector2) -> bool:
	if (
		mouse_pos.x < 0 or mouse_pos.x > BOARD_LENGTH 
		or mouse_pos.y > 0 or mouse_pos.y < -BOARD_LENGTH
	):
		return true
	return false


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


func set_move(row: int, col: int) -> void:
	for move in moves:
		# if input coords == a legal move, update the board and record history
		if move.x == row && move.y == col:
			# value of square at selected move pos
			var capture_pos := Vector2()
			var captured_val : int = 0
			
			# SPECIAL MOVE HANDLING
			# en passant
			var is_passant : bool = en_passant.length() != 0
			
			if is_passant:
				capture_pos = en_passant
				captured_val =  board[en_passant.x][en_passant.y]
				# update board to reflect pawn captured
				board[en_passant.x][en_passant.y] = 0
				en_passant = Vector2()
			else:
				capture_pos = Vector2(row,col)
				captured_val = board[row][col]
				
			# value of the selected piece to update board
			var selected_value : int = board[selected_piece.x][selected_piece.y]
			# update the board to reflect value of the moved piece
			board[row][col] = selected_value
			# update the exiting square in board to show empty
			board[selected_piece.x][selected_piece.y] = 0
			
			# add a dictionary of data to move history array
			record_history(
				selected_piece,
				Vector2(row,col),
				selected_value,
				captured_val
			)
			
			# change the color / turn
			white = !white
			
			# The pieces are instantiated children of TextureHolder so they 
			# will persist unless killed - this is handled by display_board()
			display_board()
			break
	# hide possible moves - await next click
	show_dots(false)
	# HERE THE PROGRAM "WAITS" FOR ANOTHER INPUT INSTEAD OF REGISTERING LAST 
	# LEFT CLICK AS DESIRING A NEW SET OF OPTIONS. UNTIL FIXED THE PLAYER MUST
	# MAKE TWO LEFT-CLICKS TO RESELECT PIECE FOR NEW OPTIONS. FUCK THIS PROBLEM.


func record_history(start_pos: Vector2, end_pos: Vector2, selected_value: int, captured_value: int) -> void:
	history.append({
	"start_pos" : start_pos, 
	"end_pos" : end_pos,
	"piece" : selected_value,
	"captured" : captured_value
	})


func show_options() -> void:
	moves = get_moves(selected_piece)
	# If there are no legal moves, revert to previous state
	if moves == []:
		state = "selecting"
		return
	show_dots()


func show_dots(show: bool = true) -> void:
	# show the dots
	if show:
		for move in moves:
			# we just change the image of a single sprite to draw all the dots
			var holder := TEXTURE_HOLDER.instantiate()
			dots.add_child(holder)
			holder.texture = PIECE_MOVE
			holder.global_position = Vector2(move.y * CELL_WIDTH + HALF_CELL, -move.x * CELL_WIDTH - HALF_CELL)
	# delete the dots
	else:
		for child in dots.get_children():
			child.queue_free()


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


func get_pawn_moves(pawn: Vector2) -> Array[Vector2]:
	# Pawn can move forward or diagonally if capturing, or 1 or 2 spaces first move
	# or en passante if 1 square into opponents half AND opp moves 2 forward prev move
	var _moves : Array[Vector2] = []
	var direction : Vector2
	var is_first_move : bool = false
	var pos : Vector2 = pawn
	
	# get direction of movement
	if white: direction = Vector2(1,0)
	else: direction = Vector2(-1,0)
	
	# if pawn hasn't moved, can move 1 or 2 spaces
	if (white && pos.x == 1) or (!white && pos.x == 6):
		is_first_move = true
	
	# check vertical
	pos += direction
	if is_in_bounds(pos) && is_empty(pos):
		_moves.append(pos)
		if is_first_move:
			pos += direction
			# it can't be out of bounds if it's the first move
			if is_empty(pos):
				_moves.append(pos)
	
	# check diagonals
	pos = pawn
	# look left
	for vec in [Vector2(0,-1), Vector2(0,1)]:
		pos += direction + vec
		if is_in_bounds(pos) and is_opponent(pos):
			_moves.append(pos)
		pos = pawn

	# check en passant
	# must be one square past center
	if (white && pos.x == 4) or (!white && pos.x == 3):
		for vec in [Vector2(0,-1), Vector2(0,1)]:
			pos += vec
			if is_in_bounds(pos) && is_opponent(pos):
				# get last move data to test eligibility
				var last_start : Vector2 = history[-1]["start_pos"]
				var last_end : Vector2 = history[-1]["end_pos"]
				# Pawn must have opened for 2 spaces last turn
				# We're in an eligible en passant row so we know we can look 
				# two rows back to get the prev opp pawn pos. 'direction'
				# comes from bool 'white' coded above. Column is ignored.
				var prev_posx : int = pos.x + direction.x * 2
				
				# see if these positions match
				if last_start.x == prev_posx && last_start.y == pos.y:
					if last_end.x == pos.x && last_end.y == pos.y:
						# get the diagonal direction
						var dir = Vector2(direction.x,vec.y)
						_moves.append(pawn + dir)
						# record the pos of capture for special handling
						en_passant = pos
			pos = pawn
	return _moves


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


func get_bishop_moves(bishop: Vector2) -> Array[Vector2]:
	# Similar logic to ROOK and QUEEN below (see ROOK for comments)
	var _moves : Array[Vector2] = []
	var directions = [Vector2(1,-1), Vector2(-1,-1), Vector2(1,1), Vector2(-1,1)]
	
	for dir in directions:
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


func get_king_moves(king: Vector2) -> Array[Vector2]:
	var _moves : Array[Vector2] = []
	var directions : Array[Vector2] = [
		Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(-1,1),
		Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1)
	]

	for dir in directions:
		var pos : Vector2 = king
		pos += dir
		if is_in_bounds(pos) and is_empty(pos) and !is_in_check(pos):
			_moves.append(pos)
	return _moves


func is_in_check(check_pos: Vector2) -> bool:
	# temporarily change color to get proper movesets
	white = !white
	var opp_moves : Array[Vector2] = []
	return false


func is_in_check2(check_pos: Vector2, directions: Array[Vector2]) -> bool:
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
				break
			# if own color in the way, safe
			if (white && opp > 0) or (!white && opp < 0):
				break
			if white && (opp == -3 || opp == -4 || opp == -5):
				return false
			if !white and (opp == 3 || opp == 4 || opp == 5):
				return false
			pos += dir
		pos = check_pos
		
	# check knight positions
	for dir in directions_knight:
		var pos = check_pos
		pos += dir
		if (white && board[pos.x][pos.y] == -2) || (!white && board[pos.x][pos.y] == 2):
			return false
		pos = check_pos
		
	# check pawn positions
	for dir in directions_pawn:
		var pos = check_pos
		pos += dir
		var piece : int = board[pos.x][pos.y]
		if (white && piece < 0 && pos.x > 0) || (!white && piece > 0 && pos.x < 0):
			return false
		pos = check_pos
		
	return true


func display_board() -> void:
	# The pieces are instantiated children of TextureHolder so they 
	# will persist across turns unless killed
	for child in pieces.get_children():
		child.queue_free()
	
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
	# display turn marker
	if white: turn.texture = TURN_WHITE
	else: turn.texture = TURN_BLACK
