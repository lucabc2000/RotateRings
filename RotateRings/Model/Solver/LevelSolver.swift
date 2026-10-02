//
//  LevelSolver.swift
//  RotateRings
//
//  Searches a level's move graph. Turning pieces move on a 45° grid; sliding bars move the way the
//  game moves them: pushed in one direction until they are blocked or free.
//
//  One player drag is one move. `Board.move` sweeps the whole delta and resolves releases only at
//  the end, so a move is `(piece, ±k steps)` with k up to 7 for turning pieces, not a chain of single
//  steps. A state is the quantized movement of every piece plus the set of currently active
//  connections (one bit per connection the level can ever form). Connections follow the geometry:
//  a ring turned back under a clip is gripped again, so a state can regain a bit.
//
//  Rules are never re-implemented here: every move goes through `Board.obstruction` and
//  `Board.applyFreeMove`, so the solver agrees with the game by construction.
//

import Foundation

final class LevelSolver {

    struct State: Hashable {
        /// Per start piece: rotation step 0..<8 (0 for sliding bars), or `removed`.
        var values: [UInt8]
        /// Per start piece: slide offset in half units (0 for turning pieces).
        var slides: [Int16]
        /// Bit i set when connection i is active.
        var connections: UInt64
    }

    static let removed: UInt8 = 0xFF
    private static let rotationSteps = 8

    let config: SolverConfig
    /// Start pieces in board order, after the load-time removal of unconnected pieces.
    let pieces: [Piece]
    let start: State
    /// The board the search starts from.
    private let initialBoard: Board

    private let indexOf: [Piece.ID: Int]
    private let connections: [Connection]
    private let bitOf: [Connection: Int]
    /// Grid step per piece (radians or distance).
    private let steps: [Double]
    /// Largest useful step count per piece in one move.
    private let maxSteps: [Int]
    /// Indices of pieces that can ever move.
    private let movers: [Int]
    /// Per piece: the other pieces whose geometry can touch its sweep.
    private let neighbors: [[Int]]
    /// Per piece: bits of the clip connections it owns (any active one pins it).
    private let ownerBits: [UInt64]
    /// Per piece: bits of every connection involving it (these change its sweep).
    private let relevantBits: [UInt64]

    private struct SweepKey: Hashable {
        let piece: Int
        let value: UInt8
        let neighborhood: [UInt8]
        let neighborSlides: [Int16]
        let bits: UInt64
    }
    private var sweepCache: [SweepKey: (plus: Int, minus: Int)] = [:]

    /// `board` should be a freshly built level board (every piece at its base rotation / zero offset).
    init(board initial: Board, config: SolverConfig = SolverConfig()) {
        var board = initial
        board.removeUnconnectedPieces()
        self.config = config
        initialBoard = board
        pieces = board.pieces
        indexOf = Dictionary(uniqueKeysWithValues: pieces.enumerated().map { ($1.id, $0) })
        connections = Board.potentialConnections(of: pieces)
        precondition(connections.count <= 64, "LevelSolver supports at most 64 connections")
        bitOf = Dictionary(uniqueKeysWithValues: connections.enumerated().map { ($1, $0) })

        var steps: [Double] = []
        var maxSteps: [Int] = []
        var movers: [Int] = []
        var travel: [Double] = []
        for (i, piece) in pieces.enumerated() {
            if piece.motion == .slide {
                steps.append(0)
                maxSteps.append(0)
                travel.append(Self.travel(of: piece))
                movers.append(i)
            } else {
                steps.append(GameRules.rotationStep)
                maxSteps.append(Self.rotationSteps - 1)
                travel.append(0)
                if !Self.isRotationInvariant(piece) { movers.append(i) }
            }
        }
        self.steps = steps
        self.maxSteps = maxSteps
        self.movers = movers

        var ownerBits = [UInt64](repeating: 0, count: pieces.count)
        var relevantBits = [UInt64](repeating: 0, count: pieces.count)
        for (bit, connection) in connections.enumerated() {
            let mask: UInt64 = 1 << UInt64(bit)
            if let owner = indexOf[connection.owner] {
                relevantBits[owner] |= mask
                if !connection.isHolder { ownerBits[owner] |= mask }
            }
            if let ring = indexOf[connection.ring] { relevantBits[ring] |= mask }
        }
        self.ownerBits = ownerBits
        self.relevantBits = relevantBits

        var neighbors: [[Int]] = []
        for (i, piece) in pieces.enumerated() {
            var list: [Int] = []
            for (j, other) in pieces.enumerated() where j != i {
                if Self.canTouch(piece, travel[i], other, travel[j]) { list.append(j) }
            }
            neighbors.append(list)
        }
        self.neighbors = neighbors

        var startBits: UInt64 = 0
        for connection in board.connections {
            if let bit = bitOf[connection] { startBits |= 1 << UInt64(bit) }
        }
        start = State(values: [UInt8](repeating: 0, count: pieces.count),
                      slides: pieces.map { Int16(($0.offset * 2).rounded()) },
                      connections: startBits)
    }

    // MARK: Piece classification

    /// A clip-less closed ring centred on its pivot looks the same at every angle; turning it changes
    /// nothing, so it is never a mover.
    static func isRotationInvariant(_ piece: Piece) -> Bool {
        guard piece.motion == .rotation, piece.clips.isEmpty, piece.shapes.count == 1,
              case .arc(let arc) = piece.shapes[0] else { return false }
        return arc.isClosed && arc.center.length < 1e-6
    }

    /// Largest distance from a sliding piece's origin to a body point along its axis.
    private static func slideExtent(of piece: Piece) -> Double {
        var extent = 0.0
        for shape in piece.shapes {
            let circle = shape.boundingCircle
            extent = max(extent, abs(circle.center.x) + circle.radius)
        }
        return extent
    }

    /// How far a piece's origin can move: zero for turning pieces; for a sliding bar, far enough that
    /// its arm has left the hub in either direction.
    private static func travel(of piece: Piece) -> Double {
        piece.motion == .slide ? slideExtent(of: piece) + GameRules.holderLength / 2 + 2 : 0
    }

    /// Conservative test for whether two pieces could ever come within a stroke of each other.
    private static func canTouch(_ a: Piece, _ travelA: Double, _ b: Piece, _ travelB: Double) -> Bool {
        let limit = a.collisionReach + travelA + b.collisionReach + travelB + GameRules.strokeThickness
        return a.position.distance(to: b.position) <= limit
    }

    // MARK: Independent components

    /// Groups of pieces that can never influence each other: no connection between the groups and no
    /// possible contact. Each group is a puzzle of its own, and the whole level's move graph is their
    /// product, so solving them separately is exact and exponentially cheaper.
    static func components(of board: Board) -> [[Piece.ID]] {
        let pieces = board.pieces
        var parent = Array(pieces.indices)
        func find(_ i: Int) -> Int {
            var i = i
            while parent[i] != i {
                parent[i] = parent[parent[i]]
                i = parent[i]
            }
            return i
        }
        func union(_ a: Int, _ b: Int) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        let indexOf = Dictionary(uniqueKeysWithValues: pieces.enumerated().map { ($1.id, $0) })
        for connection in board.connections {
            if let a = indexOf[connection.owner], let b = indexOf[connection.ring] { union(a, b) }
        }
        let travel = pieces.map { Self.travel(of: $0) }
        for i in pieces.indices {
            for j in pieces.indices where j > i && canTouch(pieces[i], travel[i], pieces[j], travel[j]) {
                union(i, j)
            }
        }
        var groups: [Int: [Piece.ID]] = [:]
        var order: [Int] = []
        for (i, piece) in pieces.enumerated() {
            let root = find(i)
            if groups[root] == nil { order.append(root) }
            groups[root, default: []].append(piece.id)
        }
        return order.compactMap { groups[$0] }
    }

    // MARK: State ⇄ board

    func isGoal(_ state: State) -> Bool {
        state.values.allSatisfy { $0 == Self.removed }
    }

    func encode(_ board: Board) -> State {
        var values = [UInt8](repeating: Self.removed, count: pieces.count)
        var slides = [Int16](repeating: 0, count: pieces.count)
        for piece in board.pieces {
            guard let i = indexOf[piece.id] else { continue }
            if piece.motion == .slide {
                values[i] = 0
                slides[i] = Int16(clamping: Int((piece.offset * 2).rounded()))
            } else {
                let k = Int(((piece.rotation - piece.baseRotation) / GameRules.rotationStep).rounded())
                values[i] = UInt8(((k % Self.rotationSteps) + Self.rotationSteps) % Self.rotationSteps)
            }
        }
        var bits: UInt64 = 0
        for connection in board.connections {
            if let bit = bitOf[connection] { bits |= 1 << UInt64(bit) }
        }
        return State(values: values, slides: slides, connections: bits)
    }

    func board(for state: State) -> Board {
        var present: [Piece] = []
        present.reserveCapacity(pieces.count)
        for (i, piece) in pieces.enumerated() where state.values[i] != Self.removed {
            var copy = piece
            if copy.motion == .slide {
                copy.offset = Double(state.slides[i]) / 2
            } else {
                copy.rotation = copy.baseRotation + Double(state.values[i]) * GameRules.rotationStep
            }
            present.append(copy)
        }
        var active: [Connection] = []
        for (bit, connection) in connections.enumerated() where state.connections & (1 << UInt64(bit)) != 0 {
            active.append(connection)
        }
        return Board(restoring: present, connections: active)
    }

    // MARK: Moves

    /// Every distinct state one drag away, with the shortest move that reaches it.
    func successors(of state: State) -> [(state: State, move: SolverMove)] {
        let board = board(for: state)
        var result: [(state: State, move: SolverMove)] = []
        var seen = Set<State>()
        for i in movers where state.values[i] != Self.removed && state.connections & ownerBits[i] == 0 {
            let piece = pieces[i]
            if piece.motion == .slide {
                // A push in either direction, as far as it goes.
                for direction in [1.0, -1.0] {
                    var child = board
                    guard case .moved(let moved) = child.slideToStop(piece.id, direction: direction) else { continue }
                    let next = encode(child)
                    guard next != state, seen.insert(next).inserted else { continue }
                    result.append((next, SolverMove(piece: piece.id, steps: Int(direction), delta: moved.to - moved.from, removed: moved.removedPieceIDs)))
                }
                continue
            }
            let free = freeSteps(of: i, in: board, state: state)
            let most = max(free.plus, free.minus)
            guard most > 0 else { continue }
            // Smallest step counts first, so a 7-step turn never stands in for a 1-step turn the other way.
            for k in 1...most {
                for direction in [1, -1] where (direction > 0 ? free.plus : free.minus) >= k {
                    var child = board
                    let delta = Double(direction * k) * steps[i]
                    guard let moved = child.applyFreeMove(piece.id, by: delta) else { continue }
                    let next = encode(child)
                    guard next != state, seen.insert(next).inserted else { continue }
                    result.append((next, SolverMove(piece: piece.id, steps: direction * k, delta: delta, removed: moved.removedPieceIDs)))
                }
            }
        }
        return result
    }

    /// How many grid steps the piece can move in each direction in one drag. One sweep per direction
    /// covers every step count: the sample points of the long sweep are exactly the union of the
    /// per-step sweeps, so the last free sample tells which step counts `Board.move` would accept.
    private func freeSteps(of i: Int, in board: Board, state: State) -> (plus: Int, minus: Int) {
        let key = SweepKey(piece: i, value: state.values[i],
                           neighborhood: neighbors[i].map { state.values[$0] },
                           neighborSlides: neighbors[i].map { state.slides[$0] },
                           bits: state.connections & relevantBits[i])
        if let cached = sweepCache[key] { return cached }
        let id = pieces[i].id
        let from = board.piece(id)?.movement ?? 0
        func free(_ direction: Int) -> Int {
            let delta = Double(direction * maxSteps[i]) * steps[i]
            guard let obstruction = board.obstruction(for: id, movingBy: delta) else { return maxSteps[i] }
            return Int((obstruction.stop - from) / (Double(direction) * steps[i]) + 1e-6)
        }
        let result = (plus: free(1), minus: free(-1))
        sweepCache[key] = result
        return result
    }

    /// How open the level is along `solution`: at every step, the pieces that have a move which
    /// releases a connection or takes a piece off the board, against the pieces still on the board;
    /// both summed over the steps, so the last few pieces (where everything is free) weigh little.
    /// A chain where only one piece is ever free scores low, a board where everything can go at
    /// once scores 1.
    func freedom(along solution: [SolverMove]) -> Double {
        var state = start
        var free = 0
        var present = 0
        for move in solution {
            let remaining = state.values.filter { $0 != Self.removed }.count
            guard remaining > 0 else { break }
            var productive = Set<Piece.ID>()
            for (child, candidate) in successors(of: state)
            where !candidate.removed.isEmpty || child.connections.nonzeroBitCount < state.connections.nonzeroBitCount {
                productive.insert(candidate.piece)
            }
            free += productive.count
            present += remaining
            var board = board(for: state)
            guard case .moved = board.move(move.piece, by: move.delta) else { break }
            state = encode(board)
        }
        return present == 0 ? 1 : Double(free) / Double(present)
    }

    private func heuristic(_ state: State) -> Int {
        var remaining = 0
        for value in state.values where value != Self.removed { remaining += 1 }
        return 10 * remaining + state.connections.nonzeroBitCount
    }

    // MARK: Search

    /// Solves the level. Independent components are solved one by one and combined; a single
    /// component is explored exhaustively when it fits the caps, otherwise estimated.
    func solve() -> SolverResult {
        let groups = Self.components(of: initialBoard)
        guard groups.count > 1 else { return solveComponent() }
        var parts: [SolverResult] = []
        for group in groups {
            let members = Set(group)
            let sub = Board(restoring: initialBoard.pieces.filter { members.contains($0.id) },
                            connections: initialBoard.connections.filter { members.contains($0.owner) })
            parts.append(LevelSolver(board: sub, config: config).solveComponent())
        }
        return Self.combine(parts)
    }

    /// Metrics of a product of independent puzzles. A product state is solvable when every part is;
    /// a move is a dead end when it is one in its own part. Counts multiply accordingly.
    static func combine(_ parts: [SolverResult]) -> SolverResult {
        func clamp(_ value: Double) -> Int { Int(min(value, 9e15)) }
        func productExcept(_ skip: Int, _ values: [Int]) -> Double {
            values.enumerated().reduce(1.0) { $0 * ($1.offset == skip ? 1 : Double($1.element)) }
        }
        let reach = parts.map { $0.metrics.reachableStates }
        let solvable = parts.map { $0.metrics.solvableStates }
        var deadEndMoves = 0.0, totalMoves = 0.0, edges = 0.0
        for (i, part) in parts.enumerated() {
            let m = part.metrics
            let solvableOthers = productExcept(i, solvable)
            deadEndMoves += Double(m.deadEndMoves) * solvableOthers
            totalMoves += Double(m.totalMoves) * solvableOthers
            let nonGoal = Double(m.reachableStates - (part.isSolvable ? 1 : 0))
            edges += m.branching * nonGoal * productExcept(i, reach)
        }
        let allReach = productExcept(-1, reach)
        let allSolvable = productExcept(-1, solvable)
        let exact = parts.allSatisfy { !$0.metrics.isEstimate }
        let deadEndRate = exact
            ? (totalMoves > 0 ? deadEndMoves / totalMoves : 0)
            : parts.map(\.metrics.deadEndRate).max() ?? 0
        let isSolvable = parts.allSatisfy(\.isSolvable)
        let metrics = SolverMetrics(
            minMoves: parts.reduce(0) { $0 + $1.metrics.minMoves },
            reachableStates: clamp(allReach),
            solvableStates: clamp(allSolvable),
            deadEndStates: clamp(allReach - allSolvable),
            deadEndMoves: clamp(deadEndMoves),
            totalMoves: clamp(totalMoves),
            deadEndRate: deadEndRate,
            branching: allReach > 1 ? edges / (allReach - 1) : 0,
            fullyExplored: parts.allSatisfy(\.metrics.fullyExplored),
            isEstimate: !exact,
            playouts: parts.compactMap(\.metrics.playouts).max(),
            elapsed: parts.reduce(0) { $0 + $1.metrics.elapsed }
        )
        return SolverResult(isSolvable: isSolvable, metrics: metrics, solution: isSolvable ? parts.flatMap { $0.solution ?? [] } : nil)
    }

    /// Explores the whole move graph when it fits the caps, otherwise falls back to a bounded search.
    func solveComponent() -> SolverResult {
        let clock = Date()
        var states: [State] = [start]
        var index: [State: Int32] = [start: 0]
        var parent: [Int32] = [-1]
        var parentMove: [SolverMove?] = [nil]
        var depth: [Int] = [0]
        var successorLists: [[Int32]] = []
        var goal: Int32? = isGoal(start) ? 0 : nil
        var complete = true
        var head = 0

        while head < states.count {
            if states.count >= config.stateCap || (head & 127 == 0 && Date().timeIntervalSince(clock) > config.timeCap) {
                complete = false
                break
            }
            let state = states[head]
            if isGoal(state) {
                successorLists.append([])
                head += 1
                continue
            }
            var list: [Int32] = []
            for (child, move) in successors(of: state) {
                if let existing = index[child] {
                    list.append(existing)
                } else {
                    let next = Int32(states.count)
                    states.append(child)
                    index[child] = next
                    parent.append(Int32(head))
                    parentMove.append(move)
                    depth.append(depth[head] + 1)
                    if goal == nil, isGoal(child) { goal = next }
                    list.append(next)
                }
            }
            successorLists.append(list)
            head += 1
        }

        func chain(to target: Int32) -> [SolverMove] {
            var moves: [SolverMove] = []
            var current = target
            while current > 0, let move = parentMove[Int(current)] {
                moves.append(move)
                current = parent[Int(current)]
            }
            return moves.reversed()
        }

        if complete {
            return exactResult(states: states, successorLists: successorLists, goal: goal, depth: depth, solution: goal.map(chain), started: clock)
        }

        // Bounded mode. BFS still finds the goal at minimum depth if it found it at all.
        var solution = goal.map(chain)
        if solution == nil {
            solution = bestFirstSolution(from: start, budget: config.boundedExpansions)
        }

        // Dead ends within the explored prefix. Unexpanded frontier states are treated as solvable,
        // so a state only counts as a dead end when every explored path from it is known to fail.
        // That makes the rate a lower bound rather than a guess.
        let expanded = successorLists.count
        var predecessors = [[Int32]](repeating: [], count: states.count)
        for (s, list) in successorLists.enumerated() {
            for t in list { predecessors[Int(t)].append(Int32(s)) }
        }
        var solvable = [Bool](repeating: false, count: states.count)
        var queue: [Int32] = []
        for i in expanded..<states.count {
            solvable[i] = true
            queue.append(Int32(i))
        }
        if let goal, !solvable[Int(goal)] {
            solvable[Int(goal)] = true
            queue.append(goal)
        }
        var backHead = 0
        while backHead < queue.count {
            let t = queue[backHead]
            backHead += 1
            for p in predecessors[Int(t)] where !solvable[Int(p)] {
                solvable[Int(p)] = true
                queue.append(p)
            }
        }
        var deadEndMoves = 0
        var totalMoves = 0
        var edges = 0
        var nonGoal = 0
        var deadEndStates = 0
        for (s, list) in successorLists.enumerated() where !isGoal(states[s]) {
            nonGoal += 1
            edges += list.count
            if solvable[s] {
                totalMoves += list.count
                deadEndMoves += list.reduce(0) { $0 + (solvable[Int($1)] ? 0 : 1) }
            } else {
                deadEndStates += 1
            }
        }
        let metrics = SolverMetrics(
            minMoves: solution?.count ?? 0,
            reachableStates: states.count,
            solvableStates: expanded - deadEndStates,
            deadEndStates: deadEndStates,
            deadEndMoves: deadEndMoves,
            totalMoves: totalMoves,
            deadEndRate: solution == nil ? 1 : (totalMoves > 0 ? Double(deadEndMoves) / Double(totalMoves) : 0),
            branching: nonGoal > 0 ? Double(edges) / Double(nonGoal) : 0,
            fullyExplored: false,
            isEstimate: true,
            playouts: nil,
            elapsed: Date().timeIntervalSince(clock)
        )
        return SolverResult(isSolvable: solution != nil, metrics: metrics, solution: solution)
    }

    private func exactResult(states: [State], successorLists: [[Int32]], goal: Int32?, depth: [Int], solution: [SolverMove]?, started: Date) -> SolverResult {
        var predecessors = [[Int32]](repeating: [], count: states.count)
        for (s, list) in successorLists.enumerated() {
            for t in list { predecessors[Int(t)].append(Int32(s)) }
        }
        var solvable = [Bool](repeating: false, count: states.count)
        if let goal {
            solvable[Int(goal)] = true
            var queue: [Int32] = [goal]
            var head = 0
            while head < queue.count {
                let t = queue[head]
                head += 1
                for p in predecessors[Int(t)] where !solvable[Int(p)] {
                    solvable[Int(p)] = true
                    queue.append(p)
                }
            }
        }

        var deadEndMoves = 0
        var totalMoves = 0
        var edges = 0
        var nonGoal = 0
        for (s, list) in successorLists.enumerated() where !isGoal(states[s]) {
            nonGoal += 1
            edges += list.count
            if solvable[s] {
                totalMoves += list.count
                deadEndMoves += list.reduce(0) { $0 + (solvable[Int($1)] ? 0 : 1) }
            }
        }
        let solvableCount = solvable.reduce(0) { $0 + ($1 ? 1 : 0) }
        let metrics = SolverMetrics(
            minMoves: goal.map { depth[Int($0)] } ?? 0,
            reachableStates: states.count,
            solvableStates: solvableCount,
            deadEndStates: states.count - solvableCount,
            deadEndMoves: deadEndMoves,
            totalMoves: totalMoves,
            deadEndRate: totalMoves > 0 ? Double(deadEndMoves) / Double(totalMoves) : 0,
            branching: nonGoal > 0 ? Double(edges) / Double(nonGoal) : 0,
            fullyExplored: true,
            isEstimate: false,
            playouts: nil,
            elapsed: Date().timeIntervalSince(started)
        )
        return SolverResult(isSolvable: goal != nil, metrics: metrics, solution: solution)
    }

    /// Greedy best-first search for any solution within an expansion budget.
    func bestFirstSolution(from origin: State, budget: Int) -> [SolverMove]? {
        struct Entry { let h: Int; let depth: Int; let index: Int }
        var open = PriorityQueue<Entry> { a, b in a.h != b.h ? a.h < b.h : a.depth < b.depth }
        var nodes: [State] = [origin]
        var parent: [Int] = [-1]
        var moves: [SolverMove?] = [nil]
        var seen: Set<State> = [origin]
        open.push(Entry(h: heuristic(origin), depth: 0, index: 0))
        var expansions = 0

        while let entry = open.pop() {
            if isGoal(nodes[entry.index]) {
                var path: [SolverMove] = []
                var current = entry.index
                while current > 0, let move = moves[current] {
                    path.append(move)
                    current = parent[current]
                }
                return path.reversed()
            }
            expansions += 1
            if expansions > budget { return nil }
            for (child, move) in successors(of: nodes[entry.index]) where seen.insert(child).inserted {
                nodes.append(child)
                parent.append(entry.index)
                moves.append(move)
                open.push(Entry(h: heuristic(child), depth: entry.depth + 1, index: nodes.count - 1))
            }
        }
        return nil
    }

}
