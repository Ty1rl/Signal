"""
Signal puzzle authoring tool — enclosure builder.

Takes explicit (tower_pos, shape) solve sequences and builds minimal wall/forest
terrain to FORCE that exact sequence as the only cheapest solution under flood.

Pipeline per level:
  1. Place towers at every position in the solve sequence.
  2. Simulate intended solve step-by-step. At each step, identify tiles
     the player would reach if they activated a different shape (Wide / Pulse / Skip)
     at the current tower.
  3. Paint walls at boundary tiles that, if blocked, would prevent those unintended
     expansions from reaching any downstream intended tower or target.
  4. Re-validate: intended solve still reaches target.
  5. Brute-force cheapest solver — must match intended cost.

If a sequence can't be enclosed (some step is fundamentally Wide-substitutable),
report which step and bail.
"""

import json
import os
from dataclasses import dataclass, field
from collections import deque


# ============================================================
# Rules (must match game)
# ============================================================

class Terrain:
    PLAIN = "plain"
    FOREST = "forest"
    WALL = "wall"


@dataclass(frozen=True)
class Shape:
    name: str
    max_range: int
    cost: int
    passes: frozenset


SHAPES = {
    "Wide":  Shape("Wide",  3, 15, frozenset({Terrain.PLAIN})),
    "Pulse": Shape("Pulse", 5, 10, frozenset({Terrain.PLAIN, Terrain.FOREST})),
    "Skip":  Shape("Skip",  2, 25, frozenset({Terrain.PLAIN, Terrain.FOREST, Terrain.WALL})),
}


# ============================================================
# Helpers
# ============================================================

def chebyshev(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def in_bounds(p, w, h):
    return 0 <= p[0] < w and 0 <= p[1] < h


def neighbors_8(pos):
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            yield (pos[0] + dx, pos[1] + dy)


# ============================================================
# Flood simulation (game-accurate)
# ============================================================

def pulse_reach_from(tiles, origin, tower_positions, grid_w, grid_h):
    """Return set of tiles reached by Pulse from origin."""
    shape = SHAPES["Pulse"]
    reached = {origin}
    for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
        for step in range(1, shape.max_range + 1):
            pos = (origin[0] + dx * step, origin[1] + dy * step)
            if not in_bounds(pos, grid_w, grid_h):
                break
            terr = tiles.get(pos, Terrain.PLAIN)
            if terr not in shape.passes:
                break
            reached.add(pos)
            if pos in tower_positions:
                break
    return reached


def radial_reach_from(tiles, origin, shape_name, grid_w, grid_h):
    """Return set of tiles reached by a radial shape from origin."""
    shape = SHAPES[shape_name]
    queue = deque([origin])
    visited = {origin: 0}
    reached = {origin}
    while queue:
        tile = queue.popleft()
        d = visited[tile]
        if d >= shape.max_range:
            continue
        for nb in neighbors_8(tile):
            if nb in visited:
                continue
            if not in_bounds(nb, grid_w, grid_h):
                continue
            terr = tiles.get(nb, Terrain.PLAIN)
            if terr not in shape.passes:
                continue
            visited[nb] = d + 1
            queue.append(nb)
            reached.add(nb)
    return reached


def shape_reach(tiles, origin, shape_name, tower_positions, grid_w, grid_h):
    if shape_name == "Pulse":
        return pulse_reach_from(tiles, origin, tower_positions, grid_w, grid_h)
    return radial_reach_from(tiles, origin, shape_name, grid_w, grid_h)


def simulate_solve(tiles, source, sequence, grid_w, grid_h, tower_positions):
    """Run the intended solve. Returns (controlled_set, succeeded_bool).
    sequence: list of (tower_pos, shape_name) in order.
    """
    controlled = {source}
    for pos, shape_name in sequence:
        if pos not in controlled:
            return controlled, False
        reached = shape_reach(tiles, pos, shape_name, tower_positions, grid_w, grid_h)
        controlled |= reached
    return controlled, True


# ============================================================
# Enclosure builder
# ============================================================

def build_enclosure(level):
    """Paint minimal terrain around intended solve to force that exact sequence.
    
    Strategy: iterate. At each step, check what OTHER shapes would reach.
    If they reach a downstream intended tower (shortcut), try to wall the
    midpoint tile between them — but only keep the wall if the intended solve
    still succeeds afterward.
    """
    grid_w = level.grid_w
    grid_h = level.grid_h
    tower_positions = set(pos for pos, _ in level.sequence) | {level.source, level.target}
    
    max_iterations = 40
    for iteration in range(max_iterations):
        leaks_patched = 0
        controlled = {level.source}
        for step_idx, (pos, shape_name) in enumerate(level.sequence):
            if pos not in controlled:
                break
            
            future_towers = set()
            for j in range(step_idx + 1, len(level.sequence)):
                future_towers.add(level.sequence[j][0])
            future_towers.add(level.target)
            
            for other_shape in ["Wide", "Pulse", "Skip"]:
                # Other shapes: any leak to future tower is a shortcut
                # Intended shape: only the IMMEDIATELY next tower is an allowed leak; reaching
                # further is a skip-ahead shortcut.
                is_intended = (other_shape == shape_name)
                reached = shape_reach(level.tiles, pos, other_shape, tower_positions, grid_w, grid_h)
                if is_intended:
                    # Allowed: reach the next intended tower only. Anything further is a shortcut.
                    next_pos = level.sequence[step_idx + 1][0] if step_idx + 1 < len(level.sequence) else level.target
                    illegal_towers = (reached & future_towers) - {next_pos}
                else:
                    illegal_towers = reached & future_towers
                if not illegal_towers:
                    continue
                for leak in illegal_towers:
                    if _try_wall_safely(level, pos, leak, other_shape, tower_positions, grid_w, grid_h):
                        leaks_patched += 1
            
            reached = shape_reach(level.tiles, pos, shape_name, tower_positions, grid_w, grid_h)
            controlled |= reached
        
        if leaks_patched == 0:
            break


def _try_wall_safely(level, src, leak, shape_name, tower_positions, grid_w, grid_h):
    """Wall tiles between src and leak under shape_name's flood rules until
    leak is no longer reachable. Keep only walls that don't break the intended solve.
    Returns True if at least one wall was placed.
    """
    any_placed = False
    max_walls = 12  # safety cap per call
    
    for _attempt in range(max_walls):
        # Recompute reach — has leak been cut off?
        reached = shape_reach(level.tiles, src, shape_name, tower_positions, grid_w, grid_h)
        if leak not in reached:
            return any_placed
        
        # Find a path of tiles from src to leak under the shape's rules.
        # For Pulse: the cardinal beam line (single path)
        # For Wide/Skip: BFS shortest path
        path = _shape_path(level.tiles, src, leak, shape_name, tower_positions, grid_w, grid_h)
        if not path or len(path) < 3:
            return any_placed
        # Candidates: interior tiles of the path (not src or leak), not towers
        interior = [t for t in path[1:-1] if t not in tower_positions]
        if not interior:
            return any_placed
        
        # Prefer walling the tile roughly in the middle
        mid = interior[len(interior) // 2]
        candidates = [mid] + [t for t in interior if t != mid]
        
        placed_this_iter = False
        for cand in candidates:
            if level.tiles.get(cand) == Terrain.WALL:
                continue
            old = level.tiles.get(cand, Terrain.PLAIN)
            level.tiles[cand] = Terrain.WALL
            controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                             grid_w, grid_h, tower_positions)
            if ok and level.target in controlled:
                any_placed = True
                placed_this_iter = True
                break
            level.tiles[cand] = old
        
        if not placed_this_iter:
            return any_placed
    
    return any_placed


def _shape_path(tiles, src, leak, shape_name, tower_positions, grid_w, grid_h):
    """Return a shortest path (list of tiles) from src to leak under the given shape's
    flood rules. None if unreachable.
    """
    if shape_name == "Pulse":
        dx = leak[0] - src[0]
        dy = leak[1] - src[1]
        if dx != 0 and dy != 0:
            return None
        step_x = 0 if dx == 0 else (1 if dx > 0 else -1)
        step_y = 0 if dy == 0 else (1 if dy > 0 else -1)
        dist = max(abs(dx), abs(dy))
        path = [src]
        for s in range(1, dist + 1):
            path.append((src[0] + step_x * s, src[1] + step_y * s))
        return path
    
    # Radial shapes — BFS
    shape = SHAPES[shape_name]
    queue = deque([src])
    visited = {src: None}
    while queue:
        tile = queue.popleft()
        if tile == leak:
            # Reconstruct
            path = [tile]
            while visited[path[-1]] is not None:
                path.append(visited[path[-1]])
            return list(reversed(path))
        # Check within range? Chebyshev from src
        if chebyshev(tile, src) >= shape.max_range:
            continue
        for nb in neighbors_8(tile):
            if nb in visited:
                continue
            if not in_bounds(nb, grid_w, grid_h):
                continue
            if chebyshev(nb, src) > shape.max_range:
                continue
            terr = tiles.get(nb, Terrain.PLAIN)
            if terr not in shape.passes:
                continue
            visited[nb] = tile
            queue.append(nb)
    return None


# ============================================================
# Exhaustive cheapest-path solver (verification)
# ============================================================

def find_cheapest(level, max_depth=8):
    source = level.source
    target = level.target
    tower_positions = _all_tower_positions(level)
    grid_w = level.grid_w
    grid_h = level.grid_h
    budget = level.budget
    
    best = [None]
    best_seq = [None]
    
    def dfs(transmitters, depth):
        cost = sum(SHAPES[s].cost for s in transmitters.values())
        if best[0] is not None and cost >= best[0]:
            return
        if cost > budget:
            return
        # Simulate
        controlled = {source}
        changed = True
        while changed:
            changed = False
            for origin, shape_name in transmitters.items():
                if origin not in controlled:
                    continue
                before = len(controlled)
                reach = shape_reach(level.tiles, origin, shape_name, tower_positions, grid_w, grid_h)
                controlled |= reach
                if len(controlled) > before:
                    changed = True
        if target in controlled:
            best[0] = cost
            best_seq[0] = dict(transmitters)
            return
        if depth >= max_depth:
            return
        controllable = controlled & tower_positions
        for tower in controllable:
            if tower in transmitters or tower == target:
                continue
            for sh in ["Wide", "Pulse", "Skip"]:
                transmitters[tower] = sh
                dfs(transmitters, depth + 1)
                del transmitters[tower]
    
    dfs({}, 0)
    return best[0], best_seq[0]


# ============================================================
# Level dataclass
# ============================================================

@dataclass
class Level:
    name: str
    grid_w: int = 15
    grid_h: int = 15
    budget: int = 100
    source: tuple = (1, 13)
    target: tuple = (13, 1)
    sequence: list = field(default_factory=list)  # [(pos, shape), ...]
    tiles: dict = field(default_factory=dict)     # (x,y) -> terrain
    decoy_branches: list = field(default_factory=list)  # list of [(pos, shape), ...]
    decoration_density: float = 0.0   # 0.0 = none, ~0.15 = sparse, ~0.35 = dense
    decoy_tower_ids: set = field(default_factory=set)   # populated by builder
    forest_sea_count: int = 0 
    hint_text: str = ""
    is_tutorial: bool = False


def build_level(level):
    """Place towers, run enclosure builder, validate."""
    # Ensure source is the first activation in sequence
    if not level.sequence or level.sequence[0][0] != level.source:
        raise ValueError(f"[{level.name}] first sequence entry must be source at {level.source}")
    
    build_enclosure(level)
    if not level.is_tutorial:
        # Add decoy branches (broken pseudo-paths) if specified
        for branch_idx, branch in enumerate(level.decoy_branches):
            add_decoy_branch(level, branch, branch_idx)
        
        # Decorative terrain if requested
        if level.decoration_density > 0:
            add_decoration(level, level.decoration_density)
        
        # Sprinkle extra decoy towers in empty regions — fill as many as will fit
        add_scattered_decoys(level)
    
    # Validate: intended solve reaches target
    tower_positions = _all_tower_positions(level)
    controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                     level.grid_w, level.grid_h, tower_positions)
    if not ok or level.target not in controlled:
        return {"status": "BROKEN_INTENDED", "controlled_size": len(controlled)}
    
    intended_cost = sum(SHAPES[s].cost for _, s in level.sequence)
    
    # Find cheapest actual solution
    cheapest, cheapest_seq = find_cheapest(level)
    
    status = "GOOD"
    if cheapest is None:
        status = "UNSOLVABLE_AFTER_ENCLOSE"
    elif cheapest < intended_cost:
        status = "SHORTCUT_EXISTS"
    
    return {
        "status": status,
        "intended_cost": intended_cost,
        "cheapest_cost": cheapest,
        "cheapest_seq": cheapest_seq,
    }


def _all_tower_positions(level):
    """All tower positions currently in the map: solve sequence + source + target + committed decoys.
    Does NOT include uncommitted decoy_branches positions — those are only candidates.
    """
    positions = set(pos for pos, _ in level.sequence) | {level.source, level.target}
    positions |= level.decoy_tower_ids
    return positions


# ============================================================
# Decoy branches
# ============================================================

def add_decoy_branch(level, branch, branch_idx):
    """A decoy branch is a pseudo-solve sequence that LOOKS like a shortcut.
    We place its towers, then break exactly one hop with a single wall tile
    so the branch is mechanically impossible.
    
    branch: list of (pos, shape) — pseudo-activations. First entry's pos should be
            a tower already in the intended solve (so the branch looks like it
            extends from legitimate infrastructure).
    """
    if len(branch) < 2:
        return
    
    # Step 1: tentatively add decoy tower positions. If any break the intended
    # solve (sitting on a Pulse beam line, etc.), skip this decoy branch entirely.
    existing_towers = _all_tower_positions(level)
    candidate_new_towers = [pos for pos, _ in branch if pos not in existing_towers]
    for pos in candidate_new_towers:
        level.decoy_tower_ids.add(pos)
    
    tower_positions = _all_tower_positions(level)
    controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                     level.grid_w, level.grid_h, tower_positions)
    if not ok or level.target not in controlled:
        for pos in candidate_new_towers:
            level.decoy_tower_ids.discard(pos)
        return
    
    # Also confirm decoy towers don't create a cheaper cheapest
    intended_cost = sum(SHAPES[s].cost for _, s in level.sequence)
    cheapest, _ = find_cheapest(level)
    if cheapest is None or cheapest < intended_cost:
        for pos in candidate_new_towers:
            level.decoy_tower_ids.discard(pos)
        return
    
    # Step 2: break the middle hop with a wall
    mid_hop_idx = len(branch) // 2
    if mid_hop_idx == 0:
        mid_hop_idx = 1
    src_pos = branch[mid_hop_idx - 1][0]
    dst_pos = branch[mid_hop_idx][0]
    shape_name = branch[mid_hop_idx - 1][1]
    
    tower_positions = _all_tower_positions(level)
    
    path = _shape_path(level.tiles, src_pos, dst_pos, shape_name, tower_positions,
                       level.grid_w, level.grid_h)
    if not path or len(path) < 3:
        return
    
    interior = [t for t in path[1:-1] if t not in tower_positions]
    interior.sort(key=lambda t: abs(chebyshev(t, src_pos) - chebyshev(t, dst_pos)))
    
    for cand in interior:
        if level.tiles.get(cand) == Terrain.WALL:
            continue
        old = level.tiles.get(cand, Terrain.PLAIN)
        level.tiles[cand] = Terrain.WALL
        controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                         level.grid_w, level.grid_h, tower_positions)
        if not ok or level.target not in controlled:
            level.tiles[cand] = old
            continue
        reached = shape_reach(level.tiles, src_pos, shape_name, tower_positions,
                              level.grid_w, level.grid_h)
        if dst_pos in reached:
            level.tiles[cand] = old
            continue
        cheapest, _ = find_cheapest(level)
        if cheapest is None or cheapest != intended_cost:
            level.tiles[cand] = old
            continue
        return


# ============================================================
# Decorative terrain
# ============================================================

def add_decoration(level, density):
    """Three-pass decoration:
      1. Continuous back-row wall border with 1-2 gaps, sparse wall inlets below
      2. Tetromino rocks (3-4 tiles each, L/S/T/I shapes), 5-6 per level, scattered
      3. Amorphous forest growth with stochastic neighbors
    No tight scatter fill. Plain regions are allowed to breathe.
    """
    import random
    rng = random.Random(hash(level.name) & 0xFFFFFFFF)
    
    intended_cost = sum(SHAPES[s].cost for _, s in level.sequence)
    tower_positions = _all_tower_positions(level)
    controlled, _ = simulate_solve(level.tiles, level.source, level.sequence,
                                    level.grid_w, level.grid_h, tower_positions)
    path_tiles = set(controlled)
    
    _paint_back_wall(level, rng, tower_positions, intended_cost)
    _place_tetromino_rocks(level, rng, path_tiles, tower_positions, intended_cost,
                           count=rng.randint(5, 6))
    _grow_forest_seas(level, rng, path_tiles, tower_positions, intended_cost,
                      n_seas=rng.randint(3, 4))


def _paint_back_wall(level, rng, tower_positions, intended_cost):
    """Paint an L-shaped back wall: top row (y=0) AND left column (x=0),
    each continuous with 1-2 gaps. Add sparse wall inlets from the wall.
    Then paint an inner tree ring (forest at y=1 and x=1) wherever it fits.
    """
    grid_w = level.grid_w
    grid_h = level.grid_h
    
    # --- Top row wall (y=0) ---
    n_top_gaps = rng.choice([1, 2])
    top_gaps = set()
    while len(top_gaps) < n_top_gaps:
        top_gaps.add(rng.randint(2, grid_w - 3))
    for x in range(grid_w):
        pos = (x, 0)
        if pos in tower_positions:
            continue
        if x in top_gaps:
            # Occasionally leave as forest instead of plain
            if rng.random() < 0.4:
                _try_place(level, pos, Terrain.FOREST, tower_positions, intended_cost)
            continue
        _try_place(level, pos, Terrain.WALL, tower_positions, intended_cost)
    
    # --- Left column wall (x=0) ---
    n_left_gaps = rng.choice([1, 2])
    left_gaps = set()
    while len(left_gaps) < n_left_gaps:
        left_gaps.add(rng.randint(2, grid_h - 3))
    for y in range(grid_h):
        pos = (0, y)
        if pos in tower_positions:
            continue
        if y in left_gaps:
            if rng.random() < 0.4:
                _try_place(level, pos, Terrain.FOREST, tower_positions, intended_cost)
            continue
        _try_place(level, pos, Terrain.WALL, tower_positions, intended_cost)
    
    # --- Wall inlets ---
    # 1-2 downward inlets from top wall
    for _ in range(rng.randint(1, 2)):
        start_x = rng.randint(2, grid_w - 2)
        if start_x in top_gaps:
            continue
        for y in range(1, 1 + rng.randint(1, 3)):
            pos = (start_x, y)
            if pos in tower_positions:
                break
            if not _try_place(level, pos, Terrain.WALL, tower_positions, intended_cost):
                break
    # 1-2 rightward inlets from left wall
    for _ in range(rng.randint(1, 2)):
        start_y = rng.randint(2, grid_h - 2)
        if start_y in left_gaps:
            continue
        for x in range(1, 1 + rng.randint(1, 3)):
            pos = (x, start_y)
            if pos in tower_positions:
                break
            if not _try_place(level, pos, Terrain.WALL, tower_positions, intended_cost):
                break
    
    # --- Inner tree ring (softens the wall transition) ---
    # Row y=1 trees
    for x in range(1, grid_w):
        pos = (x, 1)
        if pos in tower_positions:
            continue
        # Probabilistic — about 60% of non-tower tiles become forest if they fit
        if rng.random() < 0.6:
            _try_place(level, pos, Terrain.FOREST, tower_positions, intended_cost)
    # Column x=1 trees
    for y in range(2, grid_h):  # skip y=1 (already handled) and y=0 (wall)
        pos = (1, y)
        if pos in tower_positions:
            continue
        if rng.random() < 0.6:
            _try_place(level, pos, Terrain.FOREST, tower_positions, intended_cost)

def _place_tetromino_rocks(level, rng, path_tiles, tower_positions, intended_cost, count):
    """Place `count` small rock clumps shaped like Tetris pieces (3-4 tiles).
    Never adjacent to another rock. Never on the intended path."""
    # Tromino and tetromino shapes (relative offsets from origin tile)
    SHAPES_ROCK = [
        [(0, 0), (1, 0), (0, 1)],              # L-tromino
        [(0, 0), (1, 0), (1, 1)],              # another L
        [(0, 0), (0, 1), (1, 1)],              # S-tromino
        [(0, 0), (1, 0), (2, 0)],              # I-tromino (horizontal)
        [(0, 0), (0, 1), (0, 2)],              # I-tromino (vertical)
        [(0, 0), (1, 0), (2, 0), (1, 1)],      # T-tetromino
        [(0, 0), (1, 0), (1, 1), (2, 1)],      # S-tetromino
        [(0, 0), (0, 1), (1, 1), (1, 2)],      # Z-tetromino
        [(0, 0), (1, 0), (2, 0), (2, 1)],      # L-tetromino
    ]
    
    placed_rocks = []  # list of tile sets, to enforce spacing
    attempts = 0
    max_attempts = 80
    
    while len(placed_rocks) < count and attempts < max_attempts:
        attempts += 1
        shape = rng.choice(SHAPES_ROCK)
        # Pick random origin, skip row 0-1 (back wall area) and row grid_h-1 (avoid front edge)
        ox = rng.randint(0, level.grid_w - 4)
        oy = rng.randint(3, level.grid_h - 4)
        tiles_for_shape = [(ox + dx, oy + dy) for dx, dy in shape]
        
        # All tiles must be: in bounds, plain, not tower, not on path, not adjacent to existing rock
        valid = True
        for t in tiles_for_shape:
            if not in_bounds(t, level.grid_w, level.grid_h):
                valid = False; break
            if t in tower_positions:
                valid = False; break
            if level.tiles.get(t, Terrain.PLAIN) != Terrain.PLAIN:
                valid = False; break
            if t in path_tiles:
                valid = False; break
            # Check no adjacent existing rock
            for other in placed_rocks:
                for ot in other:
                    if chebyshev(t, ot) <= 1:
                        valid = False; break
                if not valid: break
            if not valid: break
        if not valid:
            continue
        
        # Tentatively place entire shape
        olds = {t: level.tiles.get(t, Terrain.PLAIN) for t in tiles_for_shape}
        for t in tiles_for_shape:
            level.tiles[t] = Terrain.WALL
        
        controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                         level.grid_w, level.grid_h, tower_positions)
        if not ok or level.target not in controlled:
            for t, old in olds.items():
                level.tiles[t] = old
            continue
        # Terrain is monotonic — no need for find_cheapest check
        
        placed_rocks.append(set(tiles_for_shape))


def _grow_forest_seas(level, rng, path_tiles, tower_positions, intended_cost, n_seas):
    """Grow a few large amorphous forest regions. Each sea targets 20-40 tiles,
    grown with 50% neighbor acceptance to avoid rectangular shapes. Sprinkle a
    few single-tile forest scatters at the end for texture."""
    # Pick sea centers distributed around the grid
    if n_seas is None:
        n_seas = level.forest_sea_count if level.forest_sea_count > 0 else rng.randint(3, 4)

    centers = []
    for _ in range(n_seas * 3):
        cx = rng.randint(1, level.grid_w - 2)
        cy = rng.randint(1, level.grid_h - 2)
        # Don't start a sea on the intended path
        if (cx, cy) in path_tiles:
            continue
        if level.tiles.get((cx, cy), Terrain.PLAIN) != Terrain.PLAIN:
            continue
        # Spread centers apart
        too_close = any(chebyshev((cx, cy), c) < 4 for c in centers)
        if too_close:
            continue
        centers.append((cx, cy))
        if len(centers) >= n_seas:
            break
    
    for center in centers:
        target_size = rng.randint(20, 40)
        placed = set()
        frontier = [center]
        visited = {center}
        # Give each sea a random directional "lean" so it's not round
        lean_dx = rng.choice([-1, 0, 1])
        lean_dy = rng.choice([-1, 0, 1])
        
        while frontier and len(placed) < target_size:
            # Pick a random frontier tile (not sorted — randomness creates organic shape)
            idx = rng.randrange(len(frontier))
            cand = frontier.pop(idx)
            
            if cand in tower_positions:
                continue
            if level.tiles.get(cand, Terrain.PLAIN) != Terrain.PLAIN:
                continue
            
            old = level.tiles.get(cand, Terrain.PLAIN)
            level.tiles[cand] = Terrain.FOREST
            controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                             level.grid_w, level.grid_h, tower_positions)
            if not ok or level.target not in controlled:
                level.tiles[cand] = old
                continue
            # Terrain is monotonic — skip find_cheapest
            placed.add(cand)
            
            # Add neighbors stochastically — 4-connected, with directional lean
            for dx, dy in [(1, 0), (-1, 0), (0, 1), (0, -1)]:
                nb = (cand[0] + dx, cand[1] + dy)
                if nb in visited:
                    continue
                if not in_bounds(nb, level.grid_w, level.grid_h):
                    continue
                visited.add(nb)
                # Base 50% acceptance, +20% if matches lean direction
                accept = 0.5
                if (dx, dy) == (lean_dx, lean_dy) or (dx, dy) == (lean_dx // 2 or 0, lean_dy // 2 or 0):
                    accept = 0.7
                if rng.random() < accept:
                    frontier.append(nb)


def _try_place(level, pos, terrain, tower_positions, intended_cost):
    """Tentatively place terrain at pos. Terrain additions only need to verify
    intended solve still reaches target — terrain can't create cheaper shortcuts
    (walls and forest are monotonic: they only block, never enable). Reverts and
    returns False if breaks intended.
    """
    if pos in tower_positions:
        return False
    if level.tiles.get(pos, Terrain.PLAIN) != Terrain.PLAIN:
        return False
    old = level.tiles.get(pos, Terrain.PLAIN)
    level.tiles[pos] = terrain
    controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                     level.grid_w, level.grid_h, tower_positions)
    if not ok or level.target not in controlled:
        level.tiles[pos] = old
        return False
    return True


def add_scattered_decoys(level, count=None):
    """Densely place decoy towers in empty plain regions. Jittered spacing so
    they don't form a regular grid. Each validated."""
    import random
    rng = random.Random((hash(level.name) * 7) & 0xFFFFFFFF)
    
    intended_cost = sum(SHAPES[s].cost for _, s in level.sequence)
    
    def fresh_candidates():
        current_towers = _all_tower_positions(level)
        cands = []
        for x in range(level.grid_w):
            for y in range(level.grid_h):
                if (x, y) in current_towers:
                    continue
                if level.tiles.get((x, y), Terrain.PLAIN) != Terrain.PLAIN:
                    continue
                min_td = min(chebyshev((x, y), t) for t in current_towers)
                # Jittered spacing: 2-4 tiles minimum from existing towers
                min_required = rng.choice([2, 3, 3, 4])
                if min_td < min_required:
                    continue
                cands.append((x, y))
        return cands
    
    # Hard cap: too many decoys make find_cheapest explode
    max_attempts = count if count is not None else 12
    added = 0
    
    for _ in range(max_attempts):
        candidates = fresh_candidates()
        if not candidates:
            break
        rng.shuffle(candidates)
        placed_this_round = False
        for cand in candidates:
            level.decoy_tower_ids.add(cand)
            new_tp = _all_tower_positions(level)
            controlled, ok = simulate_solve(level.tiles, level.source, level.sequence,
                                             level.grid_w, level.grid_h, new_tp)
            if not ok or level.target not in controlled:
                level.decoy_tower_ids.discard(cand)
                continue
            cheapest, _ = find_cheapest(level)
            if cheapest is None or cheapest < intended_cost:
                level.decoy_tower_ids.discard(cand)
                continue
            added += 1
            placed_this_round = True
            break
        if not placed_this_round:
            break


# ============================================================
# ASCII IO — edit levels visually
# ============================================================

# Character legend for ASCII maps
#   .  plain
#   f  forest
#   #  wall
#   S  source (must appear exactly once)
#   T  target (must appear exactly once)
#   o  intermediate tower (part of solve sequence)
#   d  decoy tower (not part of solve)
#   *  any tower of unspecified type
#
# The ASCII map only encodes terrain + tower positions. Shape assignments for
# the intended solve sequence remain in Python code (they're mechanical, not visual).

_ASCII_TERRAIN = {
    ".": Terrain.PLAIN,
    "f": Terrain.FOREST,
    "#": Terrain.WALL,
}
_TERRAIN_ASCII = {v: k for k, v in _ASCII_TERRAIN.items()}


def to_ascii(level):
    """Render level as ASCII. Lines are rows (y increases downward),
    characters are columns (x increases rightward)."""
    tower_positions = _all_tower_positions(level)
    
    grid = [["." for _ in range(level.grid_w)] for _ in range(level.grid_h)]
    for (x, y), terr in level.tiles.items():
        if 0 <= x < level.grid_w and 0 <= y < level.grid_h:
            grid[y][x] = _TERRAIN_ASCII.get(terr, ".")
    # Overlay towers
    for pos in tower_positions:
        x, y = pos
        if not (0 <= x < level.grid_w and 0 <= y < level.grid_h):
            continue
        if pos == level.source:
            grid[y][x] = "S"
        elif pos == level.target:
            grid[y][x] = "T"
        elif pos in level.decoy_tower_ids:
            grid[y][x] = "d"
        else:
            grid[y][x] = "o"
    return "\n".join("".join(row) for row in grid)


def from_ascii(ascii_str, name, sequence, budget=100, decoy_branches=None,
               decoration_density=0.0):
    """Parse an ASCII map back into a Level.
    
    The ASCII map provides: grid size, source position, target position,
    terrain, and which tiles are towers. The `sequence` arg provides the shape
    assignments (since shapes aren't visible in ASCII).
    
    Intermediate towers in the ASCII ('o' chars) must match the positions in
    `sequence` (excluding source). Decoy towers ('d' chars) must match positions
    in `decoy_branches`.
    """
    lines = [l for l in ascii_str.strip("\n").splitlines() if l.strip()]
    grid_h = len(lines)
    grid_w = max(len(l) for l in lines)
    
    source = None
    target = None
    tiles = {}
    ascii_towers = set()
    ascii_decoys = set()
    
    for y, line in enumerate(lines):
        for x, ch in enumerate(line):
            if ch == "S":
                source = (x, y)
            elif ch == "T":
                target = (x, y)
            elif ch == "o":
                ascii_towers.add((x, y))
            elif ch == "d":
                ascii_decoys.add((x, y))
            elif ch == "*":
                ascii_towers.add((x, y))
            elif ch in _ASCII_TERRAIN:
                terr = _ASCII_TERRAIN[ch]
                if terr != Terrain.PLAIN:
                    tiles[(x, y)] = terr
            # else: treat as plain
    
    if source is None:
        raise ValueError("ASCII map missing 'S' (source)")
    if target is None:
        raise ValueError("ASCII map missing 'T' (target)")
    
    level = Level(
        name=name,
        grid_w=grid_w,
        grid_h=grid_h,
        budget=budget,
        source=source,
        target=target,
        sequence=sequence,
        tiles=tiles,
        decoy_branches=decoy_branches or [],
        decoration_density=decoration_density,
    )
    level.decoy_tower_ids = set(ascii_decoys)
    
    # Sanity check: every tower in sequence should be represented in ASCII
    seq_positions = set(pos for pos, _ in sequence)
    ascii_tower_set = ascii_towers | ascii_decoys | {source, target}
    missing = seq_positions - ascii_tower_set
    if missing:
        raise ValueError(
            f"ASCII map missing tower positions from sequence: {missing}. "
            f"Add 'o' at those coords in the ASCII."
        )
    
    return level


def print_level(level):
    """Convenience for debugging."""
    print(f"--- {level.name} ({level.grid_w}x{level.grid_h}, budget {level.budget}) ---")
    print(to_ascii(level))
    print(f"sequence: {[(p, s) for p, s in level.sequence]}")


# ============================================================
# JSON export
# ============================================================

def to_json(level, report):
    towers = []
    # Collect all towers: source, target, solve-sequence intermediates, decoys
    seen = set()
    ordered = []
    for p in [level.source] + [pos for pos, _ in level.sequence[1:]] + [level.target]:
        if p not in seen:
            ordered.append(p)
            seen.add(p)
    for p in level.decoy_tower_ids:
        if p not in seen:
            ordered.append(p)
            seen.add(p)
    
    for i, pos in enumerate(ordered):
        is_decoy = pos in level.decoy_tower_ids
        if pos == level.source:
            name = "Source"
        elif pos == level.target:
            name = "Target"
        elif is_decoy:
            name = f"D{i}"
        else:
            name = f"T{i}"
        towers.append({
            "id": name,
            "x": pos[0], "y": pos[1],
            "is_source": pos == level.source,
            "is_target": pos == level.target,
            "is_scenery": False,
            "is_trap": is_decoy,
        })
    
    tiles_out = [
        {"x": x, "y": y, "terrain": t}
        for (x, y), t in level.tiles.items()
        if t != Terrain.PLAIN
    ]
    shapes_out = {
        name: {"range": s.max_range, "cost": s.cost, "passes": list(s.passes)}
        for name, s in SHAPES.items()
    }
    return {
        "label": level.name,
        "grid_w": level.grid_w,
        "grid_h": level.grid_h,
        "budget": level.budget,
        "towers": towers,
        "tiles": tiles_out,
        "shapes": shapes_out,
        "status": report.get("status", "UNKNOWN"),
        "intended_cost": report.get("intended_cost"),
        "intended_sequence": [{"pos": list(pos), "shape": sh} for pos, sh in level.sequence],
        "hint_text": level.hint_text,
    }


# ============================================================
# Matplotlib preview
# ============================================================

_TERRAIN_COLOR = {
    Terrain.PLAIN: "#f0ead0",
    Terrain.FOREST: "#3f7a3f",
    Terrain.WALL: "#5a4030",
}


def plot_level(level, report, ax):
    import matplotlib.patches as mpatches
    
    for x in range(level.grid_w):
        for y in range(level.grid_h):
            terr = level.tiles.get((x, y), Terrain.PLAIN)
            ax.add_patch(mpatches.Rectangle(
                (x - 0.5, y - 0.5), 1, 1,
                facecolor=_TERRAIN_COLOR[terr],
                edgecolor="#bbb", linewidth=0.2, zorder=0))
    
    shape_colors = {"Wide": "#2da53c", "Pulse": "#2f7fd8", "Skip": "#e07020"}
    full_seq = list(level.sequence)
    # Draw the activation sequence as arrows from pos to next pos
    positions = [pos for pos, _ in full_seq] + [level.target]
    for i in range(len(full_seq)):
        src = full_seq[i][0]
        shape_name = full_seq[i][1]
        dst = positions[i + 1]
        ax.plot([src[0], dst[0]], [src[1], dst[1]],
                color=shape_colors[shape_name], linewidth=4, alpha=0.7, zorder=2)
    
    tower_set = set(pos for pos, _ in level.sequence) | {level.source, level.target} | level.decoy_tower_ids
    for pos in tower_set:
        if pos == level.source:
            c, s = "limegreen", 14
        elif pos == level.target:
            c, s = "magenta", 14
        elif pos in level.decoy_tower_ids:
            c, s = "#c85050", 8
        else:
            c, s = "#3090d0", 10
        ax.plot(pos[0], pos[1], marker="o", markersize=s, color=c, zorder=4,
                markeredgecolor="black", markeredgewidth=1.0)
    
    ax.set_xlim(-0.5, level.grid_w - 0.5)
    ax.set_ylim(-0.5, level.grid_h - 0.5)
    ax.set_aspect("equal")
    ax.invert_yaxis()
    ax.set_xticks([])
    ax.set_yticks([])
    
    shape_abbr = "".join(s[0] for _, s in level.sequence)
    ax.set_title(f"{level.name} {shape_abbr} "
                 f"int={report.get('intended_cost','?')} cheap={report.get('cheapest_cost','?')} {report.get('status','?')}",
                 fontsize=9)


def plot_all(levels_with_reports, path):
    import matplotlib.pyplot as plt
    n = len(levels_with_reports)
    cols = min(3, n)
    rows = (n + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 4.2, rows * 4.2))
    if n == 1:
        axes = [axes]
    elif rows == 1 or cols == 1:
        axes = list(axes) if hasattr(axes, '__len__') else [axes]
    else:
        axes = axes.flatten()
    for i, (lvl, rep) in enumerate(levels_with_reports):
        plot_level(lvl, rep, axes[i])
    for j in range(n, len(axes)):
        axes[j].axis("off")
    plt.tight_layout()
    fig.savefig(path, dpi=100)
    plt.close(fig)


# ============================================================
# Hand-authored levels
# ============================================================

def level_arc():
    """Level 1 — The Arc. A big C-curve that hugs three edges of the map,
    hinting at the direct diagonal but walling it off."""
    lvl = Level(name="arc", budget=100)
    lvl.sequence = [
        ((1, 13), "Pulse"),   # -> (1,9)
        ((1, 9),  "Pulse"),   # -> (1,5)
        ((1, 5),  "Wide"),    # -> (3,3)
        ((3, 3),  "Pulse"),   # -> (8,3)
        ((8, 3),  "Wide"),    # -> (11,1) cheb 3 off-cardinal
        ((11, 1), "Pulse"),   # -> (13,1) cheb 2 cardinal
    ]
    # Arc: a tempting-looking direct diagonal decoy
    lvl.decoy_branches = [
        [((1, 13), "Pulse"), ((5, 9), "Pulse"), ((9, 5), "Pulse")],   # fake "shortcut diagonal"
    ]
    lvl.decoration_density = 0.12
    return lvl


def level_zigzag():
    """Level 2 — The Zigzag. Oscillates up-right-down-right pattern."""
    lvl = Level(name="zigzag", budget=100)
    lvl.sequence = [
        ((1, 13), "Pulse"),   # up: -> (1,9)
        ((1, 9),  "Wide"),    # zig: -> (3,11)
        ((3, 11), "Pulse"),   # up: -> (3,7)
        ((3, 7),  "Wide"),    # zag: -> (5,9)
        ((5, 9),  "Pulse"),   # up: -> (5,5)
        ((5, 5),  "Wide"),    # zig: -> (8,3) cheb 3 off-card
        ((8, 3),  "Pulse"),   # right: -> (13,3) cheb 5 cardinal
        ((13, 3), "Pulse"),   # up: -> (13,1) cheb 2 cardinal
    ]
    # Zigzag: tempting branches that look like shortcuts skipping the oscillation
    lvl.decoy_branches = [
        [((3, 11), "Pulse"), ((7, 11), "Pulse"), ((11, 11), "Pulse")],  # low straight-line tempter
    ]
    lvl.decoration_density = 0.10
    return lvl


def level_gauntlet():
    """Level 3 — The Gauntlet. Tight budget (95/100). Forces Skip to cross a wall."""
    lvl = Level(name="gauntlet", budget=100)
    lvl.sequence = [
        ((1, 13), "Pulse"),   # -> (1,9) cheb 4 cardinal
        ((1, 9),  "Wide"),    # -> (3,7) cheb 2 off-card
        ((3, 7),  "Skip"),    # -> (5,7) cheb 2 cardinal, WALL between forces Skip
        ((5, 7),  "Pulse"),   # -> (5,3) cheb 4 cardinal
        ((5, 3),  "Pulse"),   # -> (10,3) cheb 5 cardinal
        ((10, 3), "Wide"),    # -> (12,1) cheb 2 off-card
        ((12, 1), "Pulse"),   # -> (13,1) cheb 1 cardinal
    ]
    # Gauntlet: multiple tempting branches that all fail
    lvl.decoy_branches = [
        [((3, 7), "Pulse"), ((7, 7), "Pulse"), ((11, 7), "Wide")],    # tempting "go around the wall"
        [((5, 3), "Wide"), ((7, 5), "Wide"), ((9, 3), "Wide")],       # Wide-spam decoy
    ]
    lvl.decoration_density = 0.2
    lvl.forest_sea_count = 5
    return lvl

HINT_PROLOGUE = (
    "Transmit the signal from the green tower to the purple tower. "
    "Click a tower to activate it with a waveform. "
    "Activated towers glow and re-propagate the signal. "
    "Each waveform loses integrity differently as it propagates."
)


def level_tutorial_wide():
    lvl = Level(
        name="tutorial_1_wide",
        grid_w=5, grid_h=5,
        budget=50,
        source=(0, 2),
        target=(2, 0),
        sequence=[((0, 2), "Wide")],
        is_tutorial=True,
        hint_text=(
            HINT_PROLOGUE + " "
            "Wide propagates outward in a radial pattern across plain tiles. "
            "Activate the source with Wide to reach the target."
        )
    )
    return lvl


def level_tutorial_pulse():
    lvl = Level(
        name="tutorial_2_pulse",
        grid_w=7, grid_h=7,
        budget=50,
        source=(0, 4),
        target=(0, 0),
        sequence=[((0, 4), "Pulse")],
        is_tutorial=True,
        hint_text=(
            "Pulse propagates in four straight directions and passes through small rocks. "
            "Activate the source with Pulse to cut through the rocks to the target."
        )
    )
    lvl.tiles = {(0, 2): Terrain.FOREST, (0, 3): Terrain.FOREST}
    return lvl


def level_tutorial_skip():
    lvl = Level(
        name="tutorial_3_skip",
        grid_w=5, grid_h=5,
        budget=50,
        source=(0, 2),
        target=(2, 2),
        sequence=[((0, 2), "Skip")],
        is_tutorial=True,
        hint_text=(
            HINT_PROLOGUE + " "
            "Skip is the only waveform that propagates through walls. "
            "Activate the source with Skip to break through to the target."
        )
    )
    lvl.tiles = {(1, 2): Terrain.WALL}
    return lvl


def level_tutorial_chain():
    lvl = Level(
        name="tutorial_4_chain",
        grid_w=5, grid_h=5,
        budget=50,
        source=(0, 2),
        target=(4, 2),
        sequence=[((0, 2), "Pulse"), ((2, 2), "Pulse")],
        is_tutorial=True,
        hint_text=(
            HINT_PROLOGUE + " "
            "A single waveform can only reach so far. Activate a relay tower "
            "to re-propagate the signal further toward the target."
        )
    )
    return lvl

# ============================================================
# Main
# ============================================================

def main(output_dir="levels_hand",
         preview_path="signal_hand_preview.png"):
    os.makedirs(output_dir, exist_ok=True)
    levels = [
        # level_arc(), level_zigzag(), level_gauntlet(), 
              level_tutorial_chain(),level_tutorial_pulse(), level_tutorial_skip(), level_tutorial_wide()]
    reports = []
    for lvl in levels:
        report = build_level(lvl)
        reports.append((lvl, report))
        print(f"{lvl.name}: {report['status']} "
              f"intended={report.get('intended_cost', '?')} "
              f"cheapest={report.get('cheapest_cost', '?')}")
        if report["status"] == "SHORTCUT_EXISTS" and report.get("cheapest_seq"):
            print(f"  shortcut: {report['cheapest_seq']}")
        # Export
        data = to_json(lvl, report)
        path = os.path.join(output_dir, f"level_{lvl.name}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
    plot_all(reports, preview_path)
    print(f"\nPreview: {preview_path}")


if __name__ == "__main__":
    main()