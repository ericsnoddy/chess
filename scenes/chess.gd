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
var moves : Array[Vector2] = []
# pos of currently selected piece
var selected_piece : Vector2
# Move history... index is turn number, element is dict with move data
var history : Array[Dictionary] = []
# special handling - en passant, castling etc
# holds the pos of the captured piece during special moves
var en_passant : Array[Vector2] = []
# start and end pos of a rook after a castle
var castled_rook : Array[Vector2] = []
# once king moves it is ineligible for castling -> (white moved, black moved)
var king_moved := {"white" : false, "black" : true }
# Same for the castling rook, we'll track (white left, white right, black left, black right)
var rook_moved := {"white left" : false, "black left" : false, "white right" : false, "black right" : false}
# square getting promoted; dynamically cast so we can take advantage of null
var promotion_square = null

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
			# OK FUCK let's try a match statement and handle individual pieces
			match board[selected_piece.x][selected_piece.y]:
				1:
					if move.x == 7: promote(move)
				-1:
					if move.x == 0: promote(move)
			# value of square at selected move pos
			var end_pos := Vector2()
			var end_val : int = 0
			# value of the selected piece
			var selected_value : int = board[selected_piece.x][selected_piece.y]
			
			# SPECIAL MOVE HANDLING
			# en passant
			# castling
			
			# update the board to reflect value of the moved piece
			board[row][col] = selected_value
			# update the exiting square in board to show empty
			board[selected_piece.x][selected_piece.y] = 0
			
			# add a dictionary of data to move history array
			record_history(
				selected_piece,
				Vector2(row,col),
				selected_value,
				end_val
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


func record_history(start_pos: Vector2, end_pos: Vector2, selected_value: int, end_value: int) -> void:
	history.append({
	"start_pos" : start_pos, 
	"end_pos" : end_pos,
	"piece" : selected_value,
	"captured" : end_value
	})
	
	# track "has moved" for special rules handling
	# We don't have to worry about irrelevant pieces triggering this match
	# because the relevant pieces necessarily have to move first
	match start_pos:
		Vector2(0,3) : king_moved["white"] = true
		Vector2(7,3) : king_moved["black"] = true
		Vector2(0,0) : rook_moved["white left"] = true
		Vector2(0,7) : rook_moved["white right"] = true
		Vector2(7,0) : rook_moved["black left"] = true
		Vector2(7,7) : rook_moved["black right"] = true


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


func is_empty(coords: Vector2) -> bool:
	return board[coords.x][coords.y] == 0


func is_in_bounds(coords: Vector2) -> bool:
	# First check that the coords exist (on board)
	if coords.x >= 0 and coords.x < BOARD_SIZE and coords.y >= 0 and coords.y < BOARD_SIZE:
		return true
	return false


func is_in_check(check_pos: Vector2) -> bool:
	return false


func is_mouse_out(mouse_pos: Vector2) -> bool:
	if (
		mouse_pos.x < 0 or mouse_pos.x > BOARD_LENGTH 
		or mouse_pos.y > 0 or mouse_pos.y < -BOARD_LENGTH
	):
		return true
	return false


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
						en_passant.append(pawn + dir)
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
	
	# check castle eligibility and return moves
	if !is_in_check(king):
		print("king is not in check")
		# king can't have already moved
		if (white && !king_moved["white"]) or (!white && !king_moved["black"]):
			print("king has not moved")
			# directions_left[1] and _right[1] have the correct move if castle eligible
			var directions_left := [Vector2(0,-1), Vector2(0,-2)]
			var directions_right := [Vector2(0,1), Vector2(0,2), Vector2(0,3)]

			for dir in directions_left:
				var pos : Vector2 = king
				pos += dir

				while pos.y >= 0:
					# rook can't have already moved
					if (white && rook_moved["white left"]) or (!white && rook_moved["black left"]):
						print("rook has moved :(")
						break
					# spaces between must be empty
					if !is_empty(pos) && pos.y != 0:
						print("the spaces are not empty :(")
						break
					# cannot castle through check (but don't test the rook)
					if is_in_check(pos) && pos.y != 0:
						print("cannot castle through check :(")
						break
					# if we arrive to the 0 column and the rook there has not moved
					# we are golden!
					if pos.y == 0:
						print("can castle!")
						_moves.append(king + directions_left[1])
						var row = 0 if white else 7
						castled_rook.append(Vector2(row, 0))
						break
					pos += dir
			
			for dir in directions_right:
				var pos : Vector2 = king
				pos += dir

				while pos.y <= 7:
					if (white && rook_moved["white right"]) or (!white && rook_moved["black right"]):
						break
					if is_in_check(pos) && pos.y != 7: 
						break
					if !is_empty(pos) && pos.y != 7:
						print("the spaces are not empty :(")
						break
					if pos.y == 7:
						_moves.append(king + directions_right[1])
						var row = 0 if white else 7
						castled_rook.append(Vector2(row, 7))
						break
					pos += dir
	return _moves


func promote(move: Vector2) -> void:
	pass
