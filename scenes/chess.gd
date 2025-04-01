extends Sprite2D


## TODO
# 50 move rule needs added condition that no pawns moved
# Stop the game when it's over
# Stalemate: the player to move is not in check and has no legal move
# Indicate check
# checkmate - indicate checkmate
# displaying proper move history
# Resignation / offer draw
# if opponent resigns but game is dead position: actually a draw
# multiplayer support

const BOARD_SIZE := 8
const CELL_WIDTH := 18
@warning_ignore("integer_division")
const HALF_CELL : int = CELL_WIDTH / 2
const BOARD_LENGTH : int = CELL_WIDTH * 8
const TEXTURE_SCALE : float = 16 / 100.0

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
const PIECE_MOVE = preload("res://assets/dot.png")

# Hold the position of a piece: board[0][0] is value of piece at [0,0]
# Positive numbers are white, negative numbers are black; values are:
# 6 King 5 Queen 4 Rook 3 Bishop 2 Knight 1 Pawn 0 (empty square)
var board : Array[Array]
# white's turn = true, black's turn = false
var white := true
# Two states for routing click input: "selecting" and "confirming"
var state : String = "selecting"
# hold possible moves for currently selected piece
var moves : Array[Vector2] = []
# move number
var move_number := 0
# pos of currently selected piece board[0][0] -> Vector2(0, 0)
var selected_piece : Vector2
# Move history management... see record_history() for keys/parameters
var history : Array[Dictionary] = []
# had to make this move history datum global because I'm not clever enough
var captured_val := 0

# SPECIAL HANDLING
# kings' "up-to-date" position
var white_king_pos := Vector2(0,4)
var black_king_pos := Vector2(7,4)
# once king moves it is ineligible for castling
var king_moved : Dictionary[String, bool] = { 
	"white" : false, 
	"black" : false,
}
# Same for the castling rook
var rook_moved : Dictionary[String, bool] = { 
	"white left" : false, 
	"black left" : false, 
	"white right" : false, 
	"black right" : false,
}
# track data for long/short castling - used for displaying move history
var castle_type := ""
# holds the position of a pawn eligible to be captured by en passant
var en_passant := Vector2()
# for recording move history, want to know if we passant that turn
var is_passant := false
# square getting promoted; valid (non-negative) vector (ie, a move) triggers promotion buttons
var promotion_square := Vector2(-1, 0)
# 50 move rule - no captures >>and no pawn moves<< within 50 moves = offered draw
var fifty_moves := 0
# threefold rule - 3 non-unique boards = can offer draw on or after 3rd unique
# fivefold rule - automatic draw
# Positions are considered the same if
	#(1) the same player has the move,
	#(2) pieces of the same kind and color occupy the same squares, and
	#(3) the possible moves of all the pieces are the same.
# I'm going the lazy route and just checking (2)
var unique_board_moves: Array = []
var num_unique_moves: Array = []


@onready var pieces : Node2D = $Pieces
@onready var move_dots : Node2D = $Dots
@onready var turn_indicator : Sprite2D = $Turn
@onready var white_promo_pieces: Control = $"../CanvasLayer/white_pieces"
@onready var black_promo_pieces: Control = $"../CanvasLayer/black_pieces"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# bottom-left is [0,0]: see key above for piece values
	board.append([4, 2, 3, 5, 6, 3, 2, 4]) # white pieces, [0,0] -> [0,7]
	board.append([1, 1, 1, 1, 1, 1, 1, 1]) # [1,0] -> [1,7]
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([0, 0, 0, 0, 0, 0, 0, 0])
	board.append([-1, -1, -1, -1, -1, -1, -1, -1])
	board.append([-4, -2, -3, -5, -6, -3, -2, -4]) # [7,0] -> [7,7]
	
	
	# only calls display_board() once on _ready - make sure to call it below in the game loop
	display_board()
	
	# init buttons for corresponding promotion options
	var white_buttons : Array[Node] = get_tree().get_nodes_in_group("white_pieces")
	var black_buttons : Array[Node] = get_tree().get_nodes_in_group("black_pieces")
	
	# this is cleaner and faster than making a signal for each node
	for button in white_buttons:
		button.pressed.connect(_on_button_pressed.bind(button))
	for button in black_buttons:
		button.pressed.connect(_on_button_pressed.bind(button))


func _input(event) -> void:
	# (if there's a promotion we don't want to register the selection click here)
	if event is InputEventMouseButton and event.pressed and promotion_square.x < 0:
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
			if state == "selecting" and (white and board[row][col] > 0 or !white and board[row][col] < 0):
				selected_piece = Vector2(row, col)
				show_options()
				state = "confirming"

			# if options are shown we check if option is taken and then move if so
			elif state == "confirming":
				# if another piece is selected before moving, remove dots, change state
				set_move(row, col)


func _on_button_pressed(button: Node) -> void:
	# get the piece value from the name (ensure it's 1 char)
	var val : int = int(button.name.substr(0,1))
	
	# record history before updating board
	record_history( 
			selected_piece, 
			promotion_square, 
			board[promotion_square.x][promotion_square.y], 
			captured_val, 
			false, 
			val,
	)
	
	print(history.back())
	
	# incrememnt the fifty moves counter if appropriate
	incr_fifty_moves()
	check_unique_board(board)
	
	# update board. 'white' switched after we landed on promo square, so we 
	# have to take into account that white == !white when assigning value
	board[promotion_square.x][promotion_square.y] = -val if white else val
	# hide the promotion buttons - see promote() for showing the buttons
	white_promo_pieces.visible = false
	black_promo_pieces.visible = false
	# reset the promo square to default (invalid) value - this is how we hi-jacked LEFT_CLICK
	promotion_square = Vector2(-1, 0)
	display_board()


func incr_fifty_moves() -> void:
	if captured_val == 0:
		fifty_moves += 1
	else:
		fifty_moves = 0


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
			holder.scale *= TEXTURE_SCALE
	
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
	if white: 
		turn_indicator.texture = TURN_WHITE
	else: 
		turn_indicator.texture = TURN_BLACK


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
		if move.x == row and move.y == col:
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
					if move.x == 3 and selected_piece.x == 1:
						en_passant = move
						pawn_just_moved = true
					# if we're a different pawn & one is eligible to capture by passant...
					# let's see if we can capture it
					elif en_passant.length() > 0:
						# check if col of eligible pawn matches col of move +
						# check that we're not moving vertically +
						# check that row of eligible pawn == starting row of move
						# There, did I catch all the damn edge cases???
						if (
								en_passant.y == move.y and selected_piece.y != move.y
								and en_passant.x == selected_piece.x
						):
							board[en_passant.x][en_passant.y] = 0
							# data for move history
							is_passant = true
							captured_val = -1
					
				-1:
					if move.x == 0:
						promote(move)
					if move.x == 4 and selected_piece.x == 6:
						en_passant = move
						pawn_just_moved = true
					elif en_passant.length() > 0:
						if (
								en_passant.y == move.y and selected_piece.y != move.y
								and en_passant.x == selected_piece.x
						):
							board[en_passant.x][en_passant.y] = 0
							is_passant = true
							captured_val = 1
					
				4:  # we need to know if rooks moved for castling eligibility
					if selected_piece.x == 0 and selected_piece.y == 0:
						rook_moved["white left"] = true
					elif selected_piece.x == 0 and selected_piece.y == 7:
						rook_moved["white right"] = true
					
				-4: 
					if selected_piece.x == 7 and selected_piece.y == 0:
						rook_moved["black left"] = true
					elif selected_piece.x == 7 and selected_piece.y == 7:
						rook_moved["black right"] = true
						
				6:
					# castling
					if selected_piece.x == 0 and selected_piece.y == 4:
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
					if selected_piece.x == 7 and selected_piece.y == 4:
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
			if white and move.x == 7 or not white and move.x == 0:
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
				# DEBUG PRINT
				print(history.back())
			# increment 50 moves counter if appropriate
			incr_fifty_moves()
			# three/fivefold rule
			check_unique_board(board)
				
			# reset/update game variables
			if not pawn_just_moved: 
				en_passant = Vector2.ZERO
			is_passant = false
			castle_type = ""
			white = not white
			# The piece sprites are instantiated children of TextureHolder so they 
			# will persist unless killed - this is handled by display_board()
			display_board()
			break
		
	show_dots(false)
	state = "selecting"
	
	# one-click reselect functionality
	if (
			# if another piece is selected and it is the player's turn...
			(selected_piece.x != row or selected_piece.y != col) 
			and (white and board[row][col] > 0 or not white and board[row][col] < 0)
	):
		selected_piece = Vector2(row, col)
		show_options()
		state = "confirming"
	
	if is_fifty_moves(): 
		# TODO
		print("DRAW: 50 moves rule")
	elif is_dead_position(): 
		# TODO
		print("DRAW: Insufficient material")


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
	if moves.is_empty():
		state = "selecting"
		return
	show_dots()


func show_dots(to_show: bool = true) -> void:
	# show the dots
	if to_show:
		for move in moves:
			# we just change the image of a single sprite to draw all the dots
			var holder : Node = TEXTURE_HOLDER.instantiate()
			move_dots.add_child(holder)
			holder.texture = PIECE_MOVE
			holder.global_position = Vector2(move.y * CELL_WIDTH + HALF_CELL, -move.x * CELL_WIDTH - HALF_CELL)
	# else delete the dots
	else:
		for child in move_dots.get_children():
			child.queue_free()


func check_unique_board(board_to_check: Array) -> void:
	for b in unique_board_moves.size():
		if board_to_check == unique_board_moves[b]:
			num_unique_moves[b] += 1
			if num_unique_moves[b] == 5:
				# TODO
				print("DRAW: Fivefold repetition rule")
			elif num_unique_moves[b] >= 3:
				# TODO
				print("DRAW? Threefold repetition rule")
			return
	unique_board_moves.append(board_to_check.duplicate(true))
	num_unique_moves.append(1)


func is_dead_position() -> bool:
	# If both sides have 1) A lone king, 2) King and Knight only 3) King and bishop only
	# OR 4) one side has a lone King and the other side has a King and two Knights
	# King vs. King
	# King and Bishop vs. King
	# King and Knight vs. King
	# King and two knights vs. King (Per USCF not FIDE)
	var white_knights = 0
	var black_knights = 0
	var white_bishops = 0
	var black_bishops = 0
	
	for i in BOARD_SIZE:
		for j in BOARD_SIZE:
			match board[i][j]:
				2:
					# count knights
					white_knights += 1					
				-2:
					black_knights += 1
				3:
					if white_bishops == 0: 
						white_bishops += 1
					else:
						# if bishop count > 1, not insufficient
						return false
				-3:
					if black_bishops == 0: 
						black_bishops += 1
					else:
						# if knight and/or bishop count > 1, not insufficient
						return false
				6, -6, 0: 
					pass
				_: # Any num pawns, rooks or queens are sufficient
					return false
	if (
			# At this point we know there are no pawns, rooks, queens, or bishops > 1
			# (Probably a more elegant way of doing this)
			# King + Bishops <= 1 (also captures King vs King)
			white_knights == 0 and white_bishops == 0 and black_knights == 0 and black_bishops <= 1
			# King + Knights <= 2
			or white_knights == 0 and white_bishops == 0 and black_knights <= 2 and black_bishops == 0
			# King + Bishops < 2 (also captures King vs King)
			or black_knights == 0 and black_bishops == 0 and white_knights == 0 and white_bishops < 2
			# King + Knights <= 2
			or black_knights == 0 and black_bishops == 0 and white_knights <= 2 and white_bishops == 0
	):
		# insufficient material confirmed
		return true
	else:
		return false


func is_fifty_moves() -> bool:
	return fifty_moves >= 50


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
			if (
					white and board[p.x][p.y] == -1
					or !white and board[p.x][p.y] == 1
			):
				return true
				
	# simple king check
	for dir in directions:
		var pos = check_pos + dir
		if is_in_bounds(pos):
			if (
					white and board[pos.x][pos.y] == -6
					or !white and board[pos.x][pos.y] == 6
			): 
				return true
			
	# checking long range opponents in all directions
	for dir in directions:
		var pos = check_pos + dir
		while is_in_bounds(pos):
			if not is_empty(pos):
				var piece = board[pos.x][pos.y]
				# vertical/horizontal - if we encounter a rook or queen it's a check
				if dir.x == 0 or dir.y == 0:
					if (
							white and piece in [-4, -5]
							or !white and piece in [4, 5]
					):
						return true
				# diagonal - if we encounter a bishop or queen it's a check
				elif dir.x != 0 and dir.y != 0:
					if (
							white and piece in [-3, -5]
							or !white and piece in [3, 5]
					):
						return true
				break
			pos += dir
	
	# KNIGHT
	directions = [
		Vector2(2, 1), Vector2(2, -1), Vector2(1, 2), Vector2(1, -2),
		Vector2(-2, 1), Vector2(-2, -1), Vector2(-1, 2), Vector2(-1, -2)
	]
	
	for dir in directions:
		var pos = check_pos + dir
		if is_in_bounds(pos):
			if (
					white and board[pos.x][pos.y] == -2
					or !white and board[pos.x][pos.y] == 2
			):
				return true
	
	# Not in check
	return false


func is_mouse_out() -> bool:
	# Godot functionality
	if get_rect().has_point(to_local(get_global_mouse_position())):
		return false
	return true


func is_opponent(coords: Vector2) -> bool:
	var piece : int = board[coords.x][coords.y]
	# if white and piece is black (or vice versa) - valid
	if (
		white and piece < 0
		or !white and piece > 0
	):
		return true
	return false


func promote(_promotion_square: Vector2) -> void:
	promotion_square = _promotion_square
	# See _ready() for initializing this button display
	white_promo_pieces.visible = white
	black_promo_pieces.visible = not white


func get_pawn_moves(pawn: Vector2) -> Array[Vector2]:
	# Pawn can move forward or diagonally if capturing, or 1 or 2 spaces first move
	# or en passante if 1 square into opponents half AND opp moves 2 forward prev move
	var _moves : Array[Vector2] = []
	var direction : Vector2
	var is_first_move := false
	
	# get direction of movement
	if white: 
		direction = Vector2(1,0)
	else: 
		direction = Vector2(-1,0)
	
	# if pawn hasn't moved, can move 1 or 2 spaces
	if (
			white and pawn.x == 1
			or !white and pawn.x == 6
	):
		is_first_move = true
		
	# en passant
	# if there are eligible captures and the pawn is on an eligible row
	# and the opponent is exactly 1 col away, we can add the move
	if (
			en_passant.length() > 0 
			and (white and pawn.x == 4 or !white and pawn.x == 3)
			and abs(en_passant.y - pawn.y) == 1
	):
		var passant_pos : Vector2 = pawn + direction
		# Temporarily move the pawns in order to test if moving them will put 
		# the king in check. If not: OK
		board[passant_pos.x][passant_pos.y] = 1 if white else -1
		board[pawn.x][pawn.y] = 0
		board[en_passant.x][en_passant.y] = 0
		if (
				white and not is_in_check(white_king_pos)
				or !white and not is_in_check(black_king_pos)
		):
			_moves.append(passant_pos)
		# reverse the temporary pawn moves
		board[passant_pos.x][passant_pos.y] = 0
		board[pawn.x][pawn.y] = 1 if white else -1
		board[en_passant.x][en_passant.y] = -1 if white else 1
		# the move will be the capture space + vertical direction determined by color
		_moves.append(en_passant + direction)
	
	# check verticals
	var pos : Vector2 = pawn + direction
	if is_empty(pos): 
		# Same as above: Temporarily move piece and test
		board[pos.x][pos.y] = 1 if white else -1
		board[pawn.x][pawn.y] = 0
		if (
				white and not is_in_check(white_king_pos)
				or !white and not is_in_check(black_king_pos)
		):
			_moves.append(pos)
		# reverse
		board[pos.x][pos.y] = 0
		board[pawn.x][pawn.y] = 1 if white else -1
	
	# Handle pawns opening 2 spaces
	if is_first_move:
		pos = pawn + direction * 2
		if is_empty(pawn + direction) and is_empty(pos):
			# Temporarily move piece and test
			board[pos.x][pos.y] = 1 if white else -1
			board[pawn.x][pawn.y] = 0
			if (
					white and not is_in_check(white_king_pos)
					or !white and not is_in_check(black_king_pos)
			):
				_moves.append(pos)
			# reverse
			board[pos.x][pos.y] = 0
			board[pawn.x][pawn.y] = 1 if white else -1
	
	# check diagonals
	for dir in [-1, 1]:
		pos = pawn + Vector2(direction.x, dir)
		if is_in_bounds(pos):
			if is_opponent(pos):
				# Make sure doesn't put the king in check by testing temp position
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] = 1 if white else -1
				board[pawn.x][pawn.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
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
			# Different cases for is_empty and is_opponent
			if is_empty(pos):
				# Temporarily move the knight around the board in order to
				# test if moving it will put the king in check. If not: OK
				board[pos.x][pos.y] = 2 if white else -2
				board[knight.x][knight.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = 0
				board[knight.x][knight.y] = 2 if white else -2
				
			elif is_opponent(pos):
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] = 2 if white else -2
				board[knight.x][knight.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = temp
				board[knight.x][knight.y] = 2 if white else -2
		pos = knight
	return _moves


func get_bishop_moves(bishop: Vector2) -> Array[Vector2]:
	# Similar logic to ROOK and QUEEN below (see ROOK for comments)
	var _moves : Array[Vector2] = []
	var directions = [Vector2(1,-1), Vector2(-1,-1), Vector2(1,1), Vector2(-1,1)]
	
	for dir in directions:
		var pos : Vector2 = bishop
		pos += dir
		while is_in_bounds(pos):
			if is_empty(pos):
				# Temporarily move piece and test
				board[pos.x][pos.y] = 3 if white else -3
				board[bishop.x][bishop.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and !is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = 0
				board[bishop.x][bishop.y] = 3 if white else -3
				
			elif is_opponent(pos):
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] = 3 if white else -3
				board[bishop.x][bishop.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = temp
				board[bishop.x][bishop.y] = 3 if white else -3
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
		var pos : Vector2 = rook
		pos += dir
		# keep checking until end of board
		while is_in_bounds(pos):
			# if empty or opponent, the move is valid: add pos to list
			if is_empty(pos):
				# We temporarily move the rook around the board in order to
				# check if moving it will put our king in check. If not: OK
				board[pos.x][pos.y] = 4 if white else -4
				board[rook.x][rook.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = 0
				board[rook.x][rook.y] = 4 if white else -4
				
			elif is_opponent(pos):
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] = 4 if white else -4
				board[rook.x][rook.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = temp
				board[rook.x][rook.y] = 4 if white else -4
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
		var pos : Vector2 = queen
		pos += dir
		while is_in_bounds(pos):
			if is_empty(pos):
				# See above methods for comment
				board[pos.x][pos.y] = 5 if white else -5
				board[queen.x][queen.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = 0
				board[queen.x][queen.y] = 5 if white else -5
				
			elif is_opponent(pos):
				var temp = board[pos.x][pos.y]
				board[pos.x][pos.y] = 5 if white else -5
				board[queen.x][queen.y] = 0
				if (
						white and not is_in_check(white_king_pos)
						or !white and not is_in_check(black_king_pos)
				):
					_moves.append(pos)
				# reverse
				board[pos.x][pos.y] = temp
				board[queen.x][queen.y] = 5 if white else -5
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
			if not is_in_check(pos):
				if is_empty(pos) or is_opponent(pos): 
					_moves.append(pos)
			
	# check castle eligibility and return moves
	if white and not king_moved["white"]:
		if not rook_moved["white left"]:
			if (
					is_empty(Vector2(0,3)) and not is_in_check(Vector2(0,3))
					and is_empty(Vector2(0,2)) and not is_in_check(Vector2(0,2))
					and is_empty(Vector2(0,1)) and not is_in_check(Vector2(0,1))
			):
				_moves.append(Vector2(0,2))
				
		if not rook_moved["white right"]:
			if (
					is_empty(Vector2(0,5)) and not is_in_check(Vector2(0,5))
					and is_empty(Vector2(0,6)) and not is_in_check(Vector2(0,6))
			):
				_moves.append(Vector2(0,6))
		
	elif !white and not king_moved["black"]:
		if not rook_moved["black left"]:
			if (
					is_empty(Vector2(7,3)) and not is_in_check(Vector2(7,3))
					and is_empty(Vector2(7,2)) and not is_in_check(Vector2(7,2))
					and is_empty(Vector2(7,1)) and not is_in_check(Vector2(7,1))
			):
				_moves.append(Vector2(7,2))
				
		if not rook_moved["black right"]:
			if (
					is_empty(Vector2(7,5)) and not is_in_check(Vector2(7,5))
					and is_empty(Vector2(7,6)) and not is_in_check(Vector2(7,6))
			):
				_moves.append(Vector2(7,6))
				
	# Unhide the king
	if white:
		board[white_king_pos.x][white_king_pos.y] = 6
	else:
		board[black_king_pos.x][black_king_pos.y] = -6
	
	return _moves
