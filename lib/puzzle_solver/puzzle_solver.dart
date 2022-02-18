import 'dart:async';

import 'package:planets/models/position.dart';
import 'package:planets/puzzle/puzzle.dart';
import 'package:planets/puzzle_solver/solver_tile.dart';
import 'package:planets/utils/app_logger.dart';
import 'dart:math' as math;

import '../models/tile.dart';

enum Direction { left, right, up, down }

enum SpecialCaseGroup { topRight, bottomLeft, none }

const _stepDuration = Duration(milliseconds: 100);

class PuzzleSolver {
  final PuzzleBloc puzzleBloc;

  PuzzleSolver({
    required this.puzzleBloc,
  });

  List<Tile> get tiles => puzzleBloc.state.puzzle.tiles;

  StreamSubscription<SolverTile>? _streamSubscription;

  final List<SolverTile> _tiles = [];

  int get n => puzzleBloc.size;

  SolverTile get whitespaceTile =>
      _tiles.firstWhere((tile) => tile.isWhitespace);

  int abs(int x) {
    return x > 0 ? x : -x;
  }

  /// this method returns the list of tile in order they will be solved
  List<SolverTile> _determineSolveOrder() {
    final tiles = <SolverTile>[];

    for (int s = 0; s < n; s++) {
      int i = s;
      int j = s;

      while (j < n) {
        // (i, j) contains a tile
        final index = i * n + j;
        tiles.add(_tiles.firstWhere((tile) => tile.value == index));
        j += 1;
      }

      i = s + 1;
      j = s;

      while (i < n) {
        // (i, j) contains a tile
        final index = i * n + j;
        tiles.add(_tiles.firstWhere((tile) => tile.value == index));
        i += 1;
      }
    }

    return tiles;
  }

  bool _isValidPosition(Position pos) {
    return (0 <= pos.x && pos.x < n) && (0 <= pos.y && pos.y < n);
  }

  /// if `_currentSolvingTileIndex` is 3 meaning, 1 and 2 positions are already solved
  final List<int> _tilesPlacedAlready = [];

  bool _isCorrectTilePlacedAt(Position pos) {
    final tile = _tiles.firstWhere((tile) => tile.currentPosition == pos);

    if (_tilesPlacedAlready.contains(tile.value)) {
      return true;
    }

    return false;
  }

  /// using euclidean distance instead of manhattan distance
  /// kind of euclidean distance, as we don't do sqrt()
  /// just need the magnitudes to compare
  int _getDistanceBetween(Position a, Position b) {
    return (math.pow(a.x - b.x, 2) + math.pow(a.y - b.y, 2)).toInt();
  }

  // find the optimized neighbour (optimized -> nearest distance between pos and from)
  Position? _getNeighbourOf(
    Position pos,
    Position from, {
    List<Position>? excludingPos,
  }) {
    final top = Position(x: pos.x, y: pos.y - 1);
    final bottom = Position(x: pos.x, y: pos.y + 1);
    final left = Position(x: pos.x - 1, y: pos.y);
    final right = Position(x: pos.x + 1, y: pos.y);

    final List<Position> neighbours = [];

    void add(Position pos) {
      if (excludingPos == null || !excludingPos.contains(pos)) {
        neighbours.add(pos);
      }
    }

    if (_isValidPosition(top) && !_isCorrectTilePlacedAt(top)) {
      add(top);
    }

    if (_isValidPosition(bottom) && !_isCorrectTilePlacedAt(bottom)) {
      add(bottom);
    }

    if (_isValidPosition(left) && !_isCorrectTilePlacedAt(left)) {
      add(left);
    }

    if (_isValidPosition(right) && !_isCorrectTilePlacedAt(right)) {
      add(right);
    }

    if (neighbours.isEmpty) {
      return null;
    }

    int minDistance = n * n + 1;
    late Position optimizedNeighbour;

    for (final n in neighbours) {
      final distance = _getDistanceBetween(n, from);
      if (distance < minDistance) {
        minDistance = distance;
        optimizedNeighbour = n;
      }
    }

    return optimizedNeighbour;
  }

  // swaps the currentPosition of two tiles
  void _swap(SolverTile a, SolverTile b) {
    final tempPos = a.currentPosition;
    a.currentPosition = b.currentPosition;
    b.currentPosition = tempPos;
  }

  /// calling this function should make sure targetPos is a neighbour of whitespace
  SolverTile _moveWhitespaceToNeighbourPos(Position targetPos) {
    final tile = whitespaceTile;

    final wx = tile.currentPosition.x;
    final wy = tile.currentPosition.y;

    final tx = targetPos.x;
    final ty = targetPos.y;

    final x = tx - wx;

    final y = ty - wy;

    if (x > 0) {
      return _move(Direction.right);
    } else if (x < 0) {
      return _move(Direction.left);
    } else if (y > 0) {
      return _move(Direction.down);
    }

    return _move(Direction.up);
  }

  Position _posInDirection(Position start, Direction dir) {
    switch (dir) {
      case Direction.left:
        return start.left;

      case Direction.right:
        return start.right;

      case Direction.up:
        return start.top;

      case Direction.down:
        return start.bottom;
    }
  }

  List<Position> _moveInAB(int a, Direction aDir, int b, bDir) {
    final ws = whitespaceTile;
    Position currentPos = ws.currentPosition;

    final List<Position> path = [];

    // make movements in a first
    for (int _ = 0; _ < a; _++) {
      currentPos = _posInDirection(currentPos, aDir);
      path.add(currentPos);
    }

    // then, make movements in b
    for (int _ = 0; _ < b; _++) {
      currentPos = _posInDirection(currentPos, bDir);
      path.add(currentPos);
    }

    return path;
  }

  List<Position> _moveInY(int n, Direction direction) {
    final ws = whitespaceTile;
    Position currentPos = ws.currentPosition;

    final List<Position> path = [];

    for (int _ = 0; _ < n; _++) {
      currentPos =
          direction == Direction.up ? currentPos.top : currentPos.bottom;
      path.add(currentPos);
    }

    return path;
  }

  List<SolverTile> _moveWhitespaceToPos(Position targetPos) {
    final tile = whitespaceTile;

    final wx = tile.currentPosition.x;
    final wy = tile.currentPosition.y;

    final tx = targetPos.x;
    final ty = targetPos.y;

    final x = tx - wx;
    final xabs = abs(x);

    final y = ty - wy;
    final yabs = abs(y);

    final List<Position> pathA = [];
    final List<Position> pathB = [];
    final xDir = x > 0 ? Direction.right : Direction.left;
    final yDir = y > 0 ? Direction.down : Direction.up;

    // in path a, first x steps are taken then y
    pathA.addAll(_moveInAB(xabs, xDir, yabs, yDir));

    // in path b, first y steps are taken then x
    pathB.addAll(_moveInAB(yabs, yDir, xabs, xDir));

    final favourablePath = _getFavourablePath(pathA, pathB);

    final List<SolverTile> steps = [];

    // no valid path is found
    if (favourablePath.isEmpty) return steps;

    for (final pos in favourablePath) {
      steps.add(_moveWhitespaceToNeighbourPos(pos));
    }

    return steps;
  }

  // returns the tapped tile, to achieve a particular move
  // calling this method assumes that a particular move can be made
  // this method just makes the move, and does not validates a move
  SolverTile _move(Direction direction) {
    // make the move
    // update the tile's currentPos
    // update the _tiles array maintained in this class

    final SolverTile whitespace = whitespaceTile;

    final pos = whitespace.currentPosition;
    late Position targetPos;

    switch (direction) {
      case Direction.left:
        targetPos = pos.left;
        break;

      case Direction.right:
        targetPos = pos.right;
        break;

      case Direction.up:
        targetPos = pos.top;
        break;

      case Direction.down:
        targetPos = pos.bottom;
        break;
    }

    // get the target tile
    final targetTile =
        _tiles.firstWhere((tile) => tile.currentPosition == targetPos);

    _swap(whitespace, targetTile);

    return targetTile;
  }

  List<SolverTile> _moveWhitespaceNear(Position targetPos) {
    final ws = whitespaceTile;
    final neighbour = _getNeighbourOf(targetPos, ws.currentPosition);
    if (neighbour == null) return const [];
    return _moveWhitespaceToPos(neighbour);
  }

  bool _pathIsValid(List<Position> path) {
    for (final pos in path) {
      if (!_isValidPosition(pos) || _isCorrectTilePlacedAt(pos)) {
        return false;
      }
    }

    return true;
  }

  List<Position> _getFavourablePath(
    List<Position> a,
    List<Position> b,
  ) {
    if (a.length <= b.length && _pathIsValid(a)) {
      return a;
    }

    return _pathIsValid(b)
        ? b
        : _pathIsValid(a)
            ? a
            : const [];
  }

  List<SolverTile> _takeFavourableSteps({
    required Position from,
    required Position around,
    required Position to,
  }) {
    final List<Position> neighbours = [];
    // starting from centerLeft - moving clockwise for all 8 neighbours
    neighbours.add(around.left);
    neighbours.add(around.left.top);
    neighbours.add(around.top);
    neighbours.add(around.top.right);
    neighbours.add(around.right);
    neighbours.add(around.right.bottom);
    neighbours.add(around.bottom);
    neighbours.add(around.bottom.left);

    // it is sure that from and to are among these neighbours
    final fi = neighbours.indexWhere((pos) => pos == from);
    final ti = neighbours.indexWhere((pos) => pos == to);

    // there can be two paths available
    final List<Position> pathforward = [];
    final List<Position> pathbackward = [];

    // move forward
    int i = fi;
    while (i != ti) {
      i = (i + 1) % neighbours.length;
      pathforward.add(neighbours[i]);
    }

    // move backward
    i = fi;
    while (i != ti) {
      i = (i - 1) % neighbours.length;
      pathbackward.add(neighbours[i]);
    }

    // verify which path is favourable
    final favourablePath = _getFavourablePath(pathforward, pathbackward);

    final List<SolverTile> steps = [];

    for (final position in favourablePath) {
      steps.add(_moveWhitespaceToNeighbourPos(position));
    }

    return steps;
  }

  /// it is guranteed that `around` tile is a neighbour of whitespace
  List<SolverTile> _moveWhitespace({
    required Position around,
    required Position to,
  }) {
    final List<SolverTile> steps = [];

    final ws = whitespaceTile;

    if (ws.currentPosition == to) return steps;

    // the directions to take
    final favourableSteps = _takeFavourableSteps(
      from: ws.currentPosition,
      around: around,
      to: to,
    );

    steps.addAll(favourableSteps);

    return steps;
  }

  SolverTile _moveNeighbourTile(SolverTile tile) {
    return _moveWhitespaceToNeighbourPos(tile.currentPosition);
  }

  SpecialCaseGroup _getGroup(int v) {
    v += 1;

    // end of each row, except last two rows
    if (v % n == 0 && n * (n - 1) != v) {
      return SpecialCaseGroup.topRight;
    }

    // last row, except last 2 elements
    if (n * (n - 1) < v && v < n * n - 1) {
      return SpecialCaseGroup.bottomLeft;
    }

    return SpecialCaseGroup.none;
  }

  bool _isSpecialCase(int v) {
    return _getGroup(v) != SpecialCaseGroup.none;
  }

  Position _getTargetPos(SolverTile tile) {
    SpecialCaseGroup group = _getGroup(tile.value);

    assert(group != SpecialCaseGroup.none);

    if (group == SpecialCaseGroup.topRight) {
      return tile.correctPosition.bottom.left;
    }

    return tile.correctPosition.top.right;
  }

  List<SolverTile> _handleSpecialCaseFor(SolverTile tile) {
    final group = _getGroup(tile.value);
    assert(group != SpecialCaseGroup.none);

    final List<SolverTile> steps = [];

    if (tile.correctPosition == tile.currentPosition) return steps;

    final ws = whitespaceTile;

    if (group == SpecialCaseGroup.topRight) {
      // position the whitespace correctly
      if (ws.currentPosition != tile.currentPosition.right) {
        // move whitespace to left of tile
        steps.addAll(_moveWhitespaceToPos(tile.currentPosition.left));
      } else {
        // bottom, left, left, top
        steps.add(_move(Direction.down));
        steps.add(_move(Direction.left));
        steps.add(_move(Direction.left));
        steps.add(_move(Direction.up));
      }

      // run the positioning algorithm
      steps.add(_move(Direction.up));
      steps.add(_move(Direction.right));
      steps.add(_move(Direction.down));

      // place everyone correctly
      steps.add(_move(Direction.right));
      steps.add(_move(Direction.up));
      steps.add(_move(Direction.left));
      steps.add(_move(Direction.left));
      steps.add(_move(Direction.down));
    } else {
      // bottom left case

      // position the whitespace correctly
      steps.addAll(_moveWhitespaceToPos(tile.currentPosition.right));

      // run algorithm for bottom left case
      steps.add(_move(Direction.up));
      steps.add(_move(Direction.left));
      steps.add(_move(Direction.left));
      steps.add(_move(Direction.down));

      // placement
      steps.add(_move(Direction.right));

      // place everyone correctly
      steps.add(_move(Direction.down));
      steps.add(_move(Direction.left));
      steps.add(_move(Direction.up));
      steps.add(_move(Direction.up));
      steps.add(_move(Direction.right));
    }

    return steps;
  }

  /// moves a particular tile to 1 step neighbour of targetPos
  /// using whitespace, move tile to it's targetPos
  List<SolverTile> _moveTile(SolverTile tile) {
    final List<SolverTile> steps = [];

    final isSpecialCase = _isSpecialCase(tile.value);

    final targetPos =
        isSpecialCase ? _getTargetPos(tile) : tile.correctPosition;

    int count = 0;

    while (tile.currentPosition != targetPos) {
      if (count > 20) {
        break;
      }
      count += 1;

      // get the tile closest to the correct position of tile
      final neighbour = _getNeighbourOf(tile.currentPosition, targetPos);

      if (neighbour == null) {
        return steps;
      }

      // move whitespace to neighbour
      steps.addAll(_moveWhitespace(
        around: tile.currentPosition,
        to: neighbour,
      ));

      // swap
      steps.add(_moveNeighbourTile(tile));

      if (tile.correctPosition == tile.currentPosition) return steps;
    }

    if (isSpecialCase) {
      steps.addAll(_handleSpecialCaseFor(tile));
    }

    return steps;
  }

  /// this method works on `tile` to put it in it's correctPosition
  List<SolverTile> _determineStepsFor(SolverTile tile) {
    final List<SolverTile> steps = [];

    // move the whitespace near the target tile
    steps.addAll(_moveWhitespaceNear(tile.currentPosition));

    // now using the help of whitespace tile, move the tile to it's correct position
    steps.addAll(_moveTile(tile));

    return steps;
  }

  /// this method returns the list of steps to be followed to solve the puzzle
  List<SolverTile> _determineSteps() {
    final List<SolverTile> steps = [];

    final solvedOrderTiles = _determineSolveOrder().sublist(0, 13);

    for (final tile in solvedOrderTiles) {
      AppLogger.log('puzzle_solver: solving: ${tile.value}');

      if (tile.currentPosition != tile.correctPosition) {
        steps.addAll(_determineStepsFor(tile));
      }

      _tilesPlacedAlready.add(tile.value);
    }

    return steps;
  }

  /// first determine all the steps to solve the puzzle form current state
  void start() {
    // take a snapshot of the current tiles arrangement
    _tiles.clear();
    _tiles.addAll(tiles.map((tile) => SolverTile.fromTile(tile)));

    // clear
    _tilesPlacedAlready.clear();

    // determine steps to solve the puzzle
    final steps = _determineSteps();
    AppLogger.log('puzzle_solver: start: steps.length: ${steps.length}');

    // actually take steps to solve the puzzle
    _streamSubscription = Stream<SolverTile>.periodic(_stepDuration, (i) {
      if (i < steps.length) return steps[i];
      if (i == steps.length) {
        _onAutoSolvingDone();
      }
      return SolverTile.none();
    }).listen(
      (SolverTile tile) {
        AppLogger.log('AutoSolver: tap tile: ${tile.value}');
        if (tile.isNone) return;

        puzzleBloc.add(
          TileTapped(tiles.firstWhere((t) => tile.value == t.value)),
        );
      },
    );
  }

  void _onAutoSolvingDone() {
    puzzleBloc.add(const PuzzleAutoSolve(PuzzleAutoSolveState.stop));
  }

  void stop() {
    /// we will have a stream of steps to solve this puzzle
    /// and on stop called, we will cancel the stream, thus stopping the auto solver
    _streamSubscription?.cancel();
  }

  void dispose() {
    _streamSubscription?.cancel();
  }
}
