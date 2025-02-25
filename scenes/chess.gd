## TODO
# Stalemates (50 move, same position, etc)
# is_in_check(pos)
# checkmate
# 50 move rule
# displaying proper move history

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
# special handling 
# once king moves it is ineligible for castling
var king_moved := {"white" : false, "black" : true}
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

# debug overlay
var debug: Debug

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
	record_history(	selected_piece, 
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
	var just_moved := false
	for move in moves:
		# if input coords == a legal move, update the board and record history
		#
		if move.x == row && move.y == col:
			# val of ending square before move (captured = 0 if empty)
			captured_val = board[move.x][move.y]
			# OK FUCK let's try a match statement and just handle individual pieces
			# see if this works for christsakes
			match board[selected_piece.x][selected_piece.y]:
				1:
					# must be a promotion
					if move.x == 7:
						promote(move)
					# en passant
					# mark our pawn as eligible to be captured by en passant
					if move.x == 3 && selected_piece.x == 1:
						en_passant = move
						just_moved = true
					# if we're not the pawn that opened & there is an eligible pawn
					elif en_passant != null:
						# check if col of eligible pawn matches col of move +
						# check that we're not moving vertically +
						# check that row of eligible pawn == starting row of move
						# There, did I catch all the damn edge cases???
						if en_passant.y == move.y && selected_piece.y != move.y &&\
							en_passant.x == selected_piece.x:
							board[en_passant.x][en_passant.y] = 0
							is_passant = true
							captured_val = -1
				-1:
					if move.x == 0:
						promote(move)
					if move.x == 4 && selected_piece.x == 6:
						en_passant = move
						just_moved = true
					elif en_passant != null:
						if en_passant.y == move.y && selected_piece.y != move.y &&\
							en_passant.x == selected_piece.x:
							board[en_passant.x][en_passant.y] = 0
							is_passant = true
							captured_val = 1
				4: 
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
				-6:
					if selected_piece.x == 7 && selected_piece.y == 4:
						king_moved["black"] = true
						if move.y == selected_piece.y - 2:
							castle_type = "long"
							rook_moved["black left"] = true
							rook_moved["black right"] = true
							board[7][0] = 0
							board[7][3] = 4
						elif move.y == selected_piece.y + 2:
							castle_type = "short"
							rook_moved["black left"] = true
							rook_moved["black right"] = true
							board[7][7] = 0
							board[7][5] = 4

			# value of the selected piece
			var selected_value : int = board[selected_piece.x][selected_piece.y]
			# update the board to reflect value of the moved piece
			board[row][col] = selected_value
			# update the exiting square in board to show empty
			board[selected_piece.x][selected_piece.y] = 0
			
			# add a dictionary of data to history array
			# but not if promoting -- record is called elsewhere
			if white && move.x == 7:
				pass
			elif !white && move.x == 0:
				pass
			else:
				record_history(
					selected_piece,
					Vector2(row,col),
					selected_value,
					captured_val,
					is_passant,
					null,
				)
				print(history.back())
				
			# reset/update game variables
			if !just_moved: en_passant = null
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

func record_history(start_pos: Vector2, 
					end_pos: Vector2, 
					selected_value: int, 
					end_value: int,
					passant: bool,
					promo) -> void:
	# increment move
	move_number += 1
	
	history.append({
	"move" : move_number,
	"start_pos" : start_pos, 
	"end_pos" : end_pos,
	"piece" : selected_value,
	"captured" : end_value,
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


func is_in_check(_check_pos: Vector2) -> bool:
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
	var pos : Vector2 = pawn
	
	# get direction of movement
	if white: direction = Vector2(1,0)
	else: direction = Vector2(-1,0)
	
	# if pawn hasn't moved, can move 1 or 2 spaces
	if (white && pos.x == 1) or (!white && pos.x == 6):
		is_first_move = true
		
	# en passant
	# if there are eligible captures and the pawn is on an eligible row
	# and the opponent is exactly 1 col away, we can add the move
	if en_passant != null && (white && selected_piece.x == 4 || !white && selected_piece.x == 3) &&\
		abs(en_passant.y - selected_piece.y) == 1:
		# the move will be the capture space + vertical direction determined by color
		_moves.append(en_passant + direction)
	
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
	for vec in [Vector2(0,-1), Vector2(0,1)]:
		pos += direction + vec
		if is_in_bounds(pos) and is_opponent(pos):
			_moves.append(pos)
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
	
	# still need to confirm not in check
	for dir in directions:
		var pos : Vector2 = king + dir
		if is_in_bounds(pos):
			if is_in_check(pos): break
			elif is_empty(pos): _moves.append(pos)
			elif is_opponent(pos): _moves.append(pos)
	
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
			if is_empty(Vector2(7,5)) && !is_in_check(Vector2(7,5)) &&\
				is_empty(Vector2(7,6)) && !is_in_check(Vector2(7,6)):
				_moves.append(Vector2(7,6))	
	return _moves
