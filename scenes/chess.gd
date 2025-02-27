extends Sprite2D

## TODO
# blocking out of check
# Stalemates (50 move, same position, etc)
# check - can only move the king
# checkmate
# 50 move rule
# displaying proper move history

const BOARD_SIZE = 8
const CELL_WIDTH = 18
const HALF_CELL = CELL_WIDTH / 2
const BOARD_LENGTH = CELL_WIDTH * 8

# empty Sprite2D to display the pieces
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
@onready var white_pieces: Control = $"../CanvasLayer/white_pieces"
@onready var black_pieces: Control = $"../CanvasLayer/black_pieces"

# Positive numbers are white, negative numbers are black; values are:
# 6 King 5 Queen 4 Rook 3 Bishop 2 Knight 1 Pawn 0 (empty square)
# variables
# hold the position of a piece: board[0][0] is index of piece at [0,0]
var board : Array
# white's turn = true, black's turn = false
var white : bool = true
# Two states for the player: false == "selecting" and true == "confirming"
var state : String = "selecting"
# hold possible moves for currently selected piece
var moves : Array[Vector2] = []
# move number
var move_number : int = 0
# pos of currently selected piece
var selected_piece : Vector2
# Move history management... see record_history(...) for keys/parameters
var history : Array[Dictionary] = []
# had to make this move history datum global because I'm not clever enough
var captured_val : int = 0

# SPECIAL HANDLING
# kings' up-to-date position
var white_king_pos := Vector2(0,4)
var black_king_pos := Vector2(7,4)
# once king moves it is ineligible for castling
var king_moved := {"white" : false, "black" : false}
# Same for the castling rook
var rook_moved := {"white left" : false, "black left" : false, "white right" : false, "black right" : false}
# track data for long/short castling
var castle_type = null
# holds the position of a pawn eligible to be captured by en passant
var en_passant = null
# for recording move history, want to know if we passant that turn
var is_passant : bool = false
# square getting promoted; dynamically cast so we can take advantage of null
var promotion_square = null

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# bottom-left is [0,0]: see key above for piece values
	board.append([4, 2, 3, 5, 6, 3, 2, 4])	# white pieces, [0,0] -> [0,7]
	board.append([1, 1, 1, 1, 1, 1, 1, 1])	# [1,0] -> [1,7]
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([-1, -1, -1, -1, -1, -1, -1, -1])
	board.append([-4, -2, -3, -5, -6, -3, -2, -4])	# [7,0] -> [7,7]
	
	# only calls display_board() once on _ready - make sure to call it below in the game loop
	display_board()
	
	# init buttons for corresponding promotion options
	var white_buttons : Array[Node] = get_tree().get_nodes_in_group("white_pieces")
	var black_buttons : Array[Node] = get_tree().get_nodes_in_group("black_pieces")
	
	# this is cleaner and faster than making a signal for each node
	for button in white_buttons:
		button.pressed.connect(self._on_button_pressed.bind(button))
	for button in black_buttons:
		button.pressed.connect(self._on_button_pressed.bind(button))


func _input(event) -> void:
	# (if there's a promotion we don't want to register the selection click here)
	if event is InputEventMouseButton && event.pressed && promotion_square == null:
		if event.button_index == MOUSE_BUTTON_LEFT:
			# don't register interaction if mouse is outside area of the board
			if is_mouse_out(): 
				return
			# nearest whole number / cell width = row/col index
			# Coords are relative to the CanvasItem, not main display screen
			# hence why we have to abs() the y-part - we'll use up = +y for rows
			var mouse_pos : Vector2 = get_global_mouse_position()
			var col : int = snapped(mouse_pos.x, 0) / CELL_WIDTH
			var row : int = abs(snapped(mouse_pos.y, 0)) / CELL_WIDTH
			
			# Route the click depending on the state
			# make sure the selected position is eligible before showing options
			if state == "selecting" && (white && board[row][col] > 0 || !white && board[row][col] < 0):
				selected_piece = Vector2(row, col)
				show_options()
				state = "confirming"

			# if options are shown we check if option is taken and then move if so
			elif state == "confirming":
				# if another piece is selected before moving, remove dots, change state
				set_move(row, col)


func _on_button_pressed(button: Node) -> void:
	# get the piece value from the name and ensure it's 1 char
	var val : int = int(button.name.substr(0,1))
	
	# record history before updating board
	record_history( selected_piece, 
					promotion_square, 
					board[promotion_square.x][promotion_square.y], 
					captured_val, 
					false, 
					val 
	)
	print(history.back())
	# update board. 'white' switched after we landed on promo square, so we 
	# have to take into account that white == !white when assigning value
	board[promotion_square.x][promotion_square.y] = -val if white else val
	# hide the promotion buttons
	white_pieces.visible = false
	black_pieces.visible = false
	# reset the promotion square - this is how we hi-jacked LEFT_CLICK
	promotion_square = null
	display_board()


func display_board() -> void:
	# The pieces are instantiated children of TextureHolder so they 
	# will persist across turns unless killed
	for child in pieces.get_children():
		child.queue_free()
	
	for row in BOARD_SIZE:
		for col in BOARD_SIZE:
			# make a temporary sprite; we'll give it a position and a texture
			var holder : Sprite2D = TEXTURE_HOLDER.instantiate()
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


func get_moves(selected: Vector2) -> Array:
	var valid_moves : Array[Vector2] = []
	var target : int = board[selected.x][selected.y]
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
	# en passant eligibility
	var pawn_just_moved := false
	
	# if input coords == a legal move: update board, record history, reset
	for move in moves:
		if move.x == row && move.y == col:
			# val of ending square before move (captured = 0 if empty)
			captured_val = board[move.x][move.y]
			# OK FUCK let's try a match statement and just handle individual pieces
			# see if this works for christsakes
			match board[selected_piece.x][selected_piece.y]:
				1:
					# pawn promotion
					if move.x == 7:
						promote(move)
					# en passant
					# mark our pawn as eligible to be captured by en passant
					if move.x == 3 && selected_piece.x == 1:
						en_passant = move
						pawn_just_moved = true
					# if we're a different pawn & one is eligible to capture by passant...
					# let's see if we can capture it
					elif en_passant != null:
						# check if col of eligible pawn matches col of move +
						# check that we're not moving vertically +
						# check that row of eligible pawn == starting row of move
						# There, did I catch all the damn edge cases???
						if en_passant.y == move.y && selected_piece.y != move.y \
							&& en_passant.x == selected_piece.x:
							board[en_passant.x][en_passant.y] = 0
							# data for move history
							is_passant = true
							captured_val = -1
				-1:
					if move.x == 0:
						promote(move)
					if move.x == 4 && selected_piece.x == 6:
						en_passant = move
						pawn_just_moved = true
					elif en_passant != null:
						if en_passant.y == move.y && selected_piece.y != move.y \
							&& en_passant.x == selected_piece.x:
							board[en_passant.x][en_passant.y] = 0
							is_passant = true
							captured_val = 1
				4:  # we need to know if rooks moved for castling eligibility
					if selected_piece.x == 0 && selected_piece.y == 0:
						rook_moved["white left"] = true
					elif selected_piece.x == 0 && selected_piece.y == 7:
						rook_moved["white right"] = true
				-4: 
					if selected_piece.x == 7 && selected_piece.y == 0:
						rook_moved["black left"] = true
					elif selected_piece.x == 7 && selected_piece.y == 7:
						rook_moved["black right"] = true
				6:
					# castling
					if selected_piece.x == 0 && selected_piece.y == 4:
						king_moved["white"] = true						
						# if the king moved 2 units he must have castled
						if move.y == selected_piece.y - 2:
							castle_type = "long"
							# saves on computation elsewhere to set both rooks to moved
							# we don't care about their movement anymore after castling
							rook_moved["white left"] = true
							rook_moved["white right"] = true
							board[0][0] = 0
							board[0][3] = 4
						elif move.y == selected_piece.y + 2:
							rook_moved["white left"] = true
							rook_moved["white right"] = true
							castle_type = "short"
							board[0][7] = 0
							board[0][5] = 4
					# track the white king
					white_king_pos = Vector2(move.x, move.y)
				-6:
					if selected_piece.x == 7 && selected_piece.y == 4:
						king_moved["black"] = true
						if move.y == selected_piece.y - 2:
							castle_type = "long"
							rook_moved["black left"] = true
							rook_moved["black right"] = true
							board[7][0] = 0
							board[7][3] = -4
						elif move.y == selected_piece.y + 2:
							castle_type = "short"
							rook_moved["black left"] = true
							rook_moved["black right"] = true
							board[7][7] = 0
							board[7][5] = -4
					# track the black king
					black_king_pos = Vector2(move.x, move.y)
	
			# value of the selected piece
			var selected_value : int = board[selected_piece.x][selected_piece.y]
			# update the board to reflect value of the moved piece
			board[row][col] = selected_value
			# update the exiting square in board to show empty
			board[selected_piece.x][selected_piece.y] = 0
			
			# add a dictionary of data to history array
			# but not if promoting -- record is called in that loop
			if (white && move.x == 7) or (!white && move.x == 0):
				pass
			else:
				record_history(
					selected_piece,
					move,
					selected_value,
					captured_val,
					is_passant,
					null,
				)
				print(history.back())
				print(king_moved)
				print(rook_moved)
				
			# reset/update game variables
			if !pawn_just_moved: en_passant = null
			is_passant = false
			castle_type = null
			white = !white
			# The piece sprites are instantiated children of TextureHolder so they 
			# will persist unless killed - this is handled by display_board()
			display_board()
			break
	show_dots(false)
	state = "selecting"
	
	# one-click reselect functionality
	if (selected_piece.x != row || selected_piece.y != col) && (white && board[row][col] > 0 || !white && board[row][col] < 0):
		selected_piece = Vector2(row, col)
		show_options()
		state = "confirming"


func record_history(start_pos: Vector2, end_pos: Vector2, piece_val: int, capture_val: int, passant: bool, promo) -> void:
	# increment move
	move_number += 1
	
	history.append({
	"move" : move_number,
	"start_pos" : start_pos, 
	"end_pos" : end_pos,
	"piece" : piece_val,
	"captured" : capture_val,
	"is_passant" : passant,
	"promo" : promo, 
	"castle" : castle_type
	})


func show_options() -> void:
	moves = get_moves(selected_piece)
	# If there are no legal moves, revert to previous state
	if moves == []:
		state = "selecting"
		return
	show_dots()


func show_dots(to_show: bool = true) -> void:
	# show the dots
	if to_show:
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
	var directions : Array[Vector2] = [
		Vector2(1,0), Vector2(1,1), Vector2(0,1), Vector2(-1,1),
		Vector2(-1,0), Vector2(-1,-1), Vector2(0,-1), Vector2(1,-1)
	]
	
	# Test Pawns -- when they are pos + (direction, +/- 1)
	var pawn_dir = 1 if white else -1
	var pawn_attacks : Array[Vector2] = [
		check_pos + Vector2(pawn_dir, -1),
		check_pos + Vector2(pawn_dir, 1)
	]
	# simple diagonal
	for p in pawn_attacks:
		if is_in_bounds(p):
			if (white && board[p.x][p.y] == -1) or (!white && board[p.x][p.y] == 1):
				return true
				
	# simple king check
	for dir in directions:
		var pos = check_pos + dir
		if is_in_bounds(pos):
			if white && board[pos.x][pos.y] == -6 || !white && board[pos.x][pos.y] == 6: return true
			
	# checking long range opponents in all directions
	for dir in directions:
		var pos = check_pos + dir
		while is_in_bounds(pos):
			if !is_empty(pos):
				var piece = board[pos.x][pos.y]
				# vertical/horizontal - if we encounter a rook or queen it's a check
				if (dir.x == 0 || dir.y == 0):
					if (white && piece in [-4, -5] || !white && piece in [4, 5]):
						return true
				# diagonal - if we encounter a bishop or queen
				elif (dir.x != 0 && dir.y != 0):
					if (white && piece in [-3, -5] || !white && piece in [3, 5]):
						return true
				break
			pos += dir
	
	# KNIGHT
	directions = [Vector2(2, 1), Vector2(2, -1), Vector2(1, 2), Vector2(1, -2),
	Vector2(-2, 1), Vector2(-2, -1), Vector2(-1, 2), Vector2(-1, -2)]
	
	for dir in directions:
		var pos = check_pos + dir
		if is_in_bounds(pos):
			if (white && board[pos.x][pos.y] == -2) or (!white && board[pos.x][pos.y] == 2):
				return true
	
	# Not in check - return false
	return false


func is_mouse_out() -> bool:
	if get_rect().has_point(to_local(get_global_mouse_position())):
		return false
	return true


func is_opponent(coords: Vector2) -> bool:
	var piece : int = board[coords.x][coords.y]
	# if white and piece is black (or vice versa) - valid
	if (white and piece < 0) or (!white and piece > 0):
		return true
	return false


func promote(sq: Vector2) -> void:
	promotion_square = sq
	white_pieces.visible = white
	black_pieces.visible = !white


func get_pawn_moves(pawn: Vector2) -> Array[Vector2]:
	# Pawn can move forward or diagonally if capturing, or 1 or 2 spaces first move
	# or en passante if 1 square into opponents half AND opp moves 2 forward prev move
	var _moves : Array[Vector2] = []
	var direction : Vector2
	var is_first_move : bool = false
	
	# get direction of movement
	if white: direction = Vector2(1,0)
	else: direction = Vector2(-1,0)
	
	# if pawn hasn't moved, can move 1 or 2 spaces
	if (white && pawn.x == 1) or (!white && pawn.x == 6):
		is_first_move = true
		
	# en passant
	# if there are eligible captures and the pawn is on an eligible row
	# and the opponent is exactly 1 col away, we can add the move
	if en_passant != null && (white && pawn.x == 4 || !white && pawn.x == 3) && abs(en_passant.y - pawn.y) == 1:
		var pos := pawn + direction
		# # We temporarily move the pawns around the board in order to
		# check if moving them will put our king in check. If not: OK
		board[pos.x][pos.y] == 1 if white else -1
		board[pawn.x][pawn.y] == 0
		board[en_passant.x][en_passant.y] = 0
		if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
			_moves.append(pos)
		# reverse
		board[pos.x][pos.y] == 0
		board[pawn.x][pawn.y] == 1 if white else -1
		board[en_passant.x][en_passant.y] = -1 if white else 1
		# the move will be the capture space + vertical direction determined by color
		_moves.append(en_passant + direction)
	
	# check verticals
	var pos := pawn + direction
	if is_empty(pos): 
		# We temporarily move the pawn around the board in order to
		# check if moving it will put our king in check. If not: OK
		board[pos.x][pos.y] == 1 if white else -1
		board[pawn.x][pawn.y] == 0
		if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
			_moves.append(pos)
		# reverse
		board[pos.x][pos.y] == 0
		board[pawn.x][pawn.y] == 1 if white else -1
	
	if is_first_move:
		pos = pawn + direction * 2
		if is_empty(pawn + direction) && is_empty(pos):
			# We temporarily move the pawn around the board in order to
			# check if moving it will put our king in check. If not: OK
			board[pos.x][pos.y] == 1 if white else -1
			board[pawn.x][pawn.y] == 0
			if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
				_moves.append(pos)
			# reverse
			board[pos.x][pos.y] == 0
			board[pawn.x][pawn.y] == 1 if white else -1
	
	# check diagonals
	for dir in [-1, 1]:
		pos = pawn + Vector2(direction.x, dir)
		if is_in_bounds(pos):
			if is_opponent(pos):
				# Make sure doesn't put our king in check
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] == 1 if white else -1
				board[pawn.x][pawn.y] == 0
				if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
					_moves.append(pos)
				board[pos.x][pos.y] = temp
				board[pawn.x][pawn.y] = 1 if white else -1
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
		if is_in_bounds(pos):
			if is_empty(pos):
				# We temporarily move the knight around the board in order to
				# check if moving it will put our king in check. If not: OK
				board[pos.x][pos.y] == 2 if white else -2
				board[knight.x][knight.y] == 0
				if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] == 0
				board[knight.x][knight.y] == 2 if white else -2
			elif is_opponent(pos): 
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
				# We temporarily move the bishop around the board in order to
				# check if moving it will put our king in check. If not: OK
				board[pos.x][pos.y] == 3 if white else -3
				board[bishop.x][bishop.y] == 0
				if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] == 0
				board[bishop.x][bishop.y] == 3 if white else -3
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
				# We temporarily move the rook around the board in order to
				# check if moving it will put our king in check. If not: OK
				board[pos.x][pos.y] == 4 if white else -4
				board[rook.x][rook.y] == 0
				if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] == 0
				board[rook.x][rook.y] == 4 if white else -4
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
				# We temporarily move the queen around the board in order to
				# check if moving it will put our king in check. If not: OK
				board[pos.x][pos.y] == 5 if white else -5
				board[queen.x][queen.y] == 0
				if (white && !is_in_check(white_king_pos)) or (!white && !is_in_check(black_king_pos)):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] == 0
				board[queen.x][queen.y] == 5 if white else -5
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
	
	# Temporarily hide moving king from analysis - so he can't "block" himself
	if white:
		board[white_king_pos.x][white_king_pos.y] = 0
	else:
		board[black_king_pos.x][black_king_pos.y] = 0
	
	# analyze every direction for valid move
	for dir in directions:
		var pos : Vector2 = king + dir
		if is_in_bounds(pos):
			if !is_in_check(pos):
				if is_empty(pos) || is_opponent(pos): 
					_moves.append(pos)
			
	# check castle eligibility and return moves
	if white && !king_moved["white"]:
		if !rook_moved["white left"]:
			if is_empty(Vector2(0,3)) && !is_in_check(Vector2(0,3)) &&\
				is_empty(Vector2(0,2)) && !is_in_check(Vector2(0,2)) &&\
				is_empty(Vector2(0,1)) && !is_in_check(Vector2(0,1)):
				_moves.append(Vector2(0,2))
		if !rook_moved["white right"]:
			if is_empty(Vector2(0,5)) && !is_in_check(Vector2(0,5)) &&\
				is_empty(Vector2(0,6)) && !is_in_check(Vector2(0,6)):
				_moves.append(Vector2(0,6))
	elif !white && !king_moved["black"]:
		if !rook_moved["black left"]:
			if is_empty(Vector2(7,3)) && !is_in_check(Vector2(7,3)) &&\
				is_empty(Vector2(7,2)) && !is_in_check(Vector2(7,2)) &&\
				is_empty(Vector2(7,1)) && !is_in_check(Vector2(7,1)):
				_moves.append(Vector2(7,2))
		if !rook_moved["black right"]:
			print("7,5 empty: %s 7,5 clean: %s, 7,6 empty: %s, 7,6 clean: %s" % [is_empty(Vector2(7,5)), !is_in_check(Vector2(7,5)), is_empty(Vector2(7,6)), !is_in_check(Vector2(7,6))])
			if is_empty(Vector2(7,5)) && !is_in_check(Vector2(7,5)) &&\
				is_empty(Vector2(7,6)) && !is_in_check(Vector2(7,6)):
				_moves.append(Vector2(7,6))
				
	# Unhide the king
	if white:
		board[white_king_pos.x][white_king_pos.y] = 6
	else:
		board[black_king_pos.x][black_king_pos.y] = -6
	
	return _moves
