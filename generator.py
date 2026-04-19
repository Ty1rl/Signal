"""
Signal puzzle generator v4 - layered approach.

Three layers:
  1. Puzzle layer: 6-10 towers, 1-2 viable paths from source to target,
     damage loop creates compelling-looking trap branches
  2. Shortcut-blocking terrain: paint walls/forest along the straight-line
     path from source to target, forcing the solution to meander
  3. Scenery layer: extra decorative towers scattered around the map,
     obviously dead-end, just for visual life

Then parameter sweep across seeds to produce a grid of candidate puzzles.
"""

import random
from dataclasses import dataclass, field
from typing import Optional
from collections import Counter

import matplotlib.pyplot as plt
import matplotlib.patches as mpatches


# ============================================================
# Rules & Data Model
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


@dataclass
class Edge:
    a: str
    b: str
    distance: int
    terrain: str
    original_terrain: str = ""
    damaged: bool = False
    original_distance: int = 0
    is_scenery: bool = False


@dataclass
class Puzzle:
    nodes: dict = field(default_factory=dict)
    edges: dict = field(default_factory=dict)
    budget: int = 0
    source: str = "Source"
    target: str = "Target"
    grid_w: int = 15
    grid_h: int = 15
    tiles: dict = field(default_factory=dict)
    shapes: dict = field(default_factory=dict)
    scenery_nodes: set = field(default_factory=set)

    def add_node(self, node_id, x, y):
        self.nodes[node_id] = (x, y)

    def add_edge(self, a, b, distance, terrain, is_scenery=False):
        key = tuple(sorted([a, b]))
        self.edges[key] = Edge(
            a=key[0], b=key[1],
            distance=distance,
            terrain=terrain,
            original_terrain=terrain,
            original_distance=distance,
            is_scenery=is_scenery,
        )

    def neighbors(self, node_id):
        for (a, b), e in self.edges.items():
            if a == node_id:
                yield b, e
            elif b == node_id:
                yield a, e


def make_shapes():
    return {
        "Wide":  Shape("Wide",  3, 10, frozenset({Terrain.PLAIN, Terrain.FOREST})),
        "Pulse": Shape("Pulse", 5, 15, frozenset({Terrain.PLAIN})),
        "Skip":  Shape("Skip",  2, 25, frozenset({Terrain.PLAIN, Terrain.FOREST, Terrain.WALL})),
    }


# ============================================================
# Solver
# ============================================================

def _edge_shapes(edge, shapes):
    valid = []
    for shape in shapes.values():
        if edge.distance <= shape.max_range and edge.terrain in shape.passes:
            valid.append((shape.name, shape.cost))
    return valid


def solve(puzzle):
    results = []

    def dfs(current, path, visited, cost):
        if current == puzzle.target:
            results.append((list(path), cost))
            return
        for neighbor, edge in puzzle.neighbors(current):
            if neighbor in visited:
                continue
            for shape_name, shape_cost in _edge_shapes(edge, puzzle.shapes):
                new_cost = cost + shape_cost
                if new_cost > puzzle.budget:
                    continue
                visited.add(neighbor)
                path.append((neighbor, shape_name))
                dfs(neighbor, path, visited, new_cost)
                path.pop()
                visited.remove(neighbor)

    dfs(puzzle.source, [(puzzle.source, None)], {puzzle.source}, 0)
    return sorted(results, key=lambda x: x[1])


# ============================================================
# Geometry helpers
# ============================================================

def _chebyshev(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def _line_tiles(a, b):
    """All tiles on the straight line from a to b (Bresenham-ish)."""
    x1, y1 = a
    x2, y2 = b
    steps = max(abs(x2 - x1), abs(y2 - y1))
    tiles = []
    for t in range(steps + 1):
        frac = t / max(1, steps)
        tx = round(x1 + (x2 - x1) * frac)
        ty = round(y1 + (y2 - y1) * frac)
        tiles.append((tx, ty))
    return tiles


# ============================================================
# Layer 1: Puzzle graph (core mechanic)
# ============================================================

def _random_waypoint(source, target, grid_w, grid_h, rng):
    """Pick a waypoint that's off the straight line from source to target,
    to force meandering."""
    sx, sy = source
    tx, ty = target
    # midpoint
    mx, my = (sx + tx) // 2, (sy + ty) // 2
    # offset perpendicular to source-target direction
    dx = tx - sx
    dy = ty - sy
    # perpendicular: (-dy, dx) normalized-ish
    push = rng.choice([3, 4, 5])
    side = rng.choice([-1, 1])
    # simple perpendicular offset
    if abs(dx) > abs(dy):
        ox, oy = 0, side * push
    else:
        ox, oy = side * push, 0
    wx = max(1, min(grid_w - 2, mx + ox))
    wy = max(1, min(grid_h - 2, my + oy))
    return (wx, wy)


def generate_puzzle_path(puzzle, rng, target_hops=5):
    """Create a single meandering path from source to target via a waypoint."""
    source_pos = puzzle.nodes[puzzle.source]
    target_pos = puzzle.nodes[puzzle.target]

    # pick a waypoint that forces detour
    waypoint = _random_waypoint(source_pos, target_pos, puzzle.grid_w, puzzle.grid_h, rng)

    # build path: source -> waypoint (meandering) -> target
    path_positions = [source_pos]
    current = source_pos

    # hops to waypoint
    first_hops = target_hops // 2
    for _ in range(first_hops):
        # pick a hop that moves roughly toward waypoint
        shape_name = rng.choice(list(puzzle.shapes.keys()))
        shape = puzzle.shapes[shape_name]
        distance = rng.randint(2, shape.max_range)

        dx_needed = waypoint[0] - current[0]
        dy_needed = waypoint[1] - current[1]
        sx = 1 if dx_needed > 0 else -1 if dx_needed < 0 else rng.choice([-1, 1])
        sy = 1 if dy_needed > 0 else -1 if dy_needed < 0 else rng.choice([-1, 1])

        new_pos = None
        for _ in range(15):
            dx = rng.randint(0, distance) * sx
            dy = (distance - abs(dx)) * sy if rng.random() < 0.6 else rng.randint(-distance, distance)
            dx = max(-distance, min(distance, dx))
            dy = max(-distance, min(distance, dy))
            if max(abs(dx), abs(dy)) != distance:
                continue
            candidate = (current[0] + dx, current[1] + dy)
            if not (0 <= candidate[0] < puzzle.grid_w and 0 <= candidate[1] < puzzle.grid_h):
                continue
            if candidate in path_positions or candidate == target_pos:
                continue
            new_pos = candidate
            break

        if new_pos is None:
            break
        path_positions.append(new_pos)
        current = new_pos

    # hops from here to target
    remaining_hops = target_hops - len(path_positions) + 1
    for _ in range(remaining_hops):
        if current == target_pos:
            break
        d_to_target = _chebyshev(current, target_pos)

        # Try a mid-range hop first, fall back to final jump
        shape_names = list(puzzle.shapes.keys())
        rng.shuffle(shape_names)
        hopped = False
        for shape_name in shape_names:
            shape = puzzle.shapes[shape_name]
            if d_to_target <= shape.max_range:
                # can jump to target with this shape
                path_positions.append(target_pos)
                current = target_pos
                hopped = True
                break
            # otherwise take a hop in the target direction
            distance = min(shape.max_range, d_to_target)
            if distance < 2:
                continue
            dx_needed = target_pos[0] - current[0]
            dy_needed = target_pos[1] - current[1]
            sx = 1 if dx_needed > 0 else -1 if dx_needed < 0 else rng.choice([-1, 1])
            sy = 1 if dy_needed > 0 else -1 if dy_needed < 0 else rng.choice([-1, 1])
            for _ in range(10):
                dx = rng.randint(0, distance) * sx
                dy = (distance - abs(dx)) * sy
                if max(abs(dx), abs(dy)) != distance:
                    continue
                candidate = (current[0] + dx, current[1] + dy)
                if not (0 <= candidate[0] < puzzle.grid_w and 0 <= candidate[1] < puzzle.grid_h):
                    continue
                if candidate in path_positions or candidate == target_pos:
                    continue
                path_positions.append(candidate)
                current = candidate
                hopped = True
                break
            if hopped:
                break
        if not hopped:
            break

    if current != target_pos and path_positions[-1] != target_pos:
        # force the last leg
        path_positions.append(target_pos)

    return path_positions


def _add_nodes_for_path(puzzle, path_positions, prefix):
    """Create nodes for each position in path (except source/target which exist).
    Returns list of node ids in order."""
    node_ids = []
    pos_to_name = {v: k for k, v in puzzle.nodes.items()}
    for i, pos in enumerate(path_positions):
        if pos in pos_to_name:
            node_ids.append(pos_to_name[pos])
        else:
            name = f"{prefix}_{i}"
            puzzle.add_node(name, pos[0], pos[1])
            pos_to_name[pos] = name
            node_ids.append(name)
    return node_ids


def _add_edges_for_path(puzzle, node_ids, rng):
    """For each consecutive pair, add an edge with distance = chebyshev.
    Pick a terrain that AT LEAST ONE shape can cross."""
    for i in range(len(node_ids) - 1):
        a, b = node_ids[i], node_ids[i+1]
        pa = puzzle.nodes[a]
        pb = puzzle.nodes[b]
        distance = _chebyshev(pa, pb)
        # find terrain options that a shape can cross at this distance
        terrain_options = []
        for terrain in [Terrain.PLAIN, Terrain.FOREST, Terrain.WALL]:
            if any(distance <= s.max_range and terrain in s.passes for s in puzzle.shapes.values()):
                terrain_options.append(terrain)
        if not terrain_options:
            # fallback plain
            terrain = Terrain.PLAIN
        else:
            terrain = rng.choice(terrain_options)
        puzzle.add_edge(a, b, distance, terrain)


def build_puzzle_layer(puzzle, rng, target_hops=5):
    """Build a single meandering viable path, then add 2-3 trap branches off
    of intermediate nodes that look plausible but get damaged."""
    # Main path
    main_path = generate_puzzle_path(puzzle, rng, target_hops)
    main_ids = _add_nodes_for_path(puzzle, main_path, "Main")
    _add_edges_for_path(puzzle, main_ids, rng)

    # Trap branches: pick 2-3 intermediate nodes on main path, branch off
    intermediates = main_ids[1:-1]
    n_traps = min(len(intermediates), rng.randint(2, 3))
    trap_origins = rng.sample(intermediates, n_traps) if intermediates else []

    for trap_idx, origin in enumerate(trap_origins):
        # build a 2-hop branch
        current = puzzle.nodes[origin]
        branch_ids = [origin]
        for hop in range(2):
            shape_name = rng.choice(list(puzzle.shapes.keys()))
            shape = puzzle.shapes[shape_name]
            distance = rng.randint(2, shape.max_range)
            # random direction
            sx = rng.choice([-1, 1])
            sy = rng.choice([-1, 1])
            placed = False
            for _ in range(10):
                dx = rng.randint(0, distance) * sx
                dy = (distance - abs(dx)) * sy
                if max(abs(dx), abs(dy)) != distance:
                    continue
                candidate = (current[0] + dx, current[1] + dy)
                if not (1 <= candidate[0] < puzzle.grid_w - 1 and 1 <= candidate[1] < puzzle.grid_h - 1):
                    continue
                if candidate in [pos for pos in puzzle.nodes.values()]:
                    continue
                # Add node
                trap_name = f"Trap{trap_idx}_{hop}"
                puzzle.add_node(trap_name, candidate[0], candidate[1])
                # Edge with matching shape-terrain at first, will be damaged later
                terrain = rng.choice(list(shape.passes))
                puzzle.add_edge(branch_ids[-1], trap_name, distance, terrain)
                branch_ids.append(trap_name)
                current = candidate
                placed = True
                break
            if not placed:
                break

    return main_ids


def damage_traps(puzzle, main_ids, rng):
    """Damage edges in trap branches so they look viable but aren't.
    Strategy: bump distance beyond any shape, or swap terrain to wall-only."""
    for (a, b), edge in puzzle.edges.items():
        if a in main_ids and b in main_ids:
            continue  # don't touch main path
        # This is a trap edge. Make it just barely unusable.
        kind = rng.choice(["distance_overrun", "terrain_hostile", "keep_alive"])
        if kind == "distance_overrun":
            edge.distance = 7  # beyond Wide(3) and Skip(2), beyond Pulse(5)
            edge.damaged = True
        elif kind == "terrain_hostile":
            # wall makes it Skip-only, and bump distance beyond Skip range
            edge.terrain = Terrain.WALL
            edge.distance = 4  # Skip max is 2, so Skip fails too
            edge.damaged = True
        # keep_alive: some traps remain traversable but don't lead anywhere useful


# ============================================================
# Layer 2: Terrain painting (shortcut-blocking)
# ============================================================

def paint_shortcut_blocker(puzzle, rng):
    """Paint a wall/forest barrier along the straight-line from source to target,
    to force meandering."""
    source = puzzle.nodes[puzzle.source]
    target = puzzle.nodes[puzzle.target]
    line = _line_tiles(source, target)

    # skip the endpoints
    middle_tiles = line[2:-2]
    # paint walls/forest across a band
    for cx, cy in middle_tiles:
        # paint a small perpendicular band
        for offset in range(-2, 3):
            for axis in ['x', 'y']:
                tx = cx + (offset if axis == 'x' else 0)
                ty = cy + (offset if axis == 'y' else 0)
                if 0 <= tx < puzzle.grid_w and 0 <= ty < puzzle.grid_h:
                    # Don't overwrite near source or target
                    if _chebyshev((tx, ty), source) < 3 or _chebyshev((tx, ty), target) < 3:
                        continue
                    # Don't overwrite tiles where path-layer towers exist
                    if (tx, ty) in puzzle.nodes.values():
                        continue
                    # Paint with some randomness
                    r = rng.random()
                    if r < 0.3:
                        puzzle.tiles[(tx, ty)] = Terrain.WALL


# ============================================================
# Layer 3: Scenery (decorative dead-end towers)
# ============================================================

def add_scenery_towers(puzzle, rng, n_scenery=6):
    """Place N scenery towers at random empty-ish positions with short
    dead-end edges. These aren't meant to be solution-relevant."""
    occupied = set(puzzle.nodes.values())

    for i in range(n_scenery):
        # pick random position
        placed = False
        for _ in range(20):
            x = rng.randint(1, puzzle.grid_w - 2)
            y = rng.randint(1, puzzle.grid_h - 2)
            # not overlapping existing nodes
            if (x, y) in occupied:
                continue
            # not too close to source or target
            if _chebyshev((x, y), puzzle.nodes[puzzle.source]) < 2:
                continue
            if _chebyshev((x, y), puzzle.nodes[puzzle.target]) < 2:
                continue
            # not adjacent to existing nodes (we want isolated decoration)
            too_close = any(_chebyshev((x, y), pos) < 2 for pos in occupied)
            if too_close:
                continue
            node_name = f"Scene_{i}"
            puzzle.add_node(node_name, x, y)
            puzzle.scenery_nodes.add(node_name)
            occupied.add((x, y))

            # maybe add a short dead-end edge to a nearby scenery tower or nothing
            # We want these to obviously not lead anywhere, so limit edges
            if rng.random() < 0.5 and i > 0:
                # try connecting to another scenery tower if close
                scenery_list = [n for n in puzzle.scenery_nodes if n != node_name]
                if scenery_list:
                    other = rng.choice(scenery_list)
                    other_pos = puzzle.nodes[other]
                    d = _chebyshev((x, y), other_pos)
                    if 2 <= d <= 6:
                        # make it an obviously hard edge
                        puzzle.add_edge(node_name, other, d, Terrain.WALL, is_scenery=True)

            placed = True
            break
        if not placed:
            continue


# ============================================================
# Background noise (fills remaining tiles)
# ============================================================

def paint_background_noise(puzzle, rng):
    # Fill tiles NOT already painted (by edges or shortcut-blocker)
    # Also paint critical edge tiles with their edge's terrain first
    critical = set()
    for (a, b), e in puzzle.edges.items():
        if e.is_scenery:
            continue
        x1, y1 = puzzle.nodes[a]
        x2, y2 = puzzle.nodes[b]
        for tx, ty in _line_tiles((x1, y1), (x2, y2)):
            critical.add((tx, ty))
            if (tx, ty) not in puzzle.tiles:
                puzzle.tiles[(tx, ty)] = e.terrain

    for x in range(puzzle.grid_w):
        for y in range(puzzle.grid_h):
            if (x, y) in puzzle.tiles:
                continue
            roll = rng.random()
            if roll < 0.6:
                puzzle.tiles[(x, y)] = Terrain.PLAIN
            elif roll < 0.85:
                puzzle.tiles[(x, y)] = Terrain.FOREST
            else:
                puzzle.tiles[(x, y)] = Terrain.WALL


# ============================================================
# Top-level generator
# ============================================================

def generate_level(seed=1, budget=70, grid_size=15, target_hops=5, n_scenery=6):
    rng = random.Random(seed)
    shapes = make_shapes()

    puzzle = Puzzle(shapes=shapes, budget=budget, grid_w=grid_size, grid_h=grid_size)
    puzzle.add_node("Source", 1, grid_size - 2)
    puzzle.add_node("Target", grid_size - 2, 1)

    # Layer 1: puzzle graph
    main_ids = build_puzzle_layer(puzzle, rng, target_hops=target_hops)
    damage_traps(puzzle, main_ids, rng)

    # Layer 2: shortcut-blocking terrain
    paint_shortcut_blocker(puzzle, rng)

    # Layer 3: scenery
    add_scenery_towers(puzzle, rng, n_scenery=n_scenery)

    # Background noise (fills in rest)
    paint_background_noise(puzzle, rng)

    # Verify
    solutions = solve(puzzle)
    report = {
        "solutions": solutions,
        "solution_count": len(solutions),
        "budget": puzzle.budget,
        "status": (
            "UNSOLVABLE" if not solutions else
            f"GOOD({len(solutions)})" if 1 <= len(solutions) <= 3 else
            f"TOO_MANY({len(solutions)})"
        ),
        "n_nodes": len(puzzle.nodes),
        "n_scenery": len(puzzle.scenery_nodes),
        "n_edges": len(puzzle.edges),
    }
    return puzzle, report


# ============================================================
# Visualization
# ============================================================

_TERRAIN_COLOR = {
    Terrain.PLAIN: "#f0e6d0",
    Terrain.FOREST: "#3f7a3f",
    Terrain.WALL: "#5a4030",
}
_SOLUTION_COLORS = ["#FFD700", "#00FFFF", "#FF00FF"]


def plot_puzzle_on_axis(puzzle, report, ax, label=""):
    # tiles
    for (x, y), terr in puzzle.tiles.items():
        ax.add_patch(mpatches.Rectangle(
            (x - 0.5, y - 0.5), 1, 1,
            facecolor=_TERRAIN_COLOR.get(terr, "#888"),
            edgecolor="#ccc", linewidth=0.2, zorder=0))

    # highlight solutions
    for i, (path, cost) in enumerate(report["solutions"][:3]):
        path_nodes = [step[0] for step in path]
        color = _SOLUTION_COLORS[i]
        for j in range(len(path_nodes) - 1):
            n1, n2 = path_nodes[j], path_nodes[j+1]
            if n1 not in puzzle.nodes or n2 not in puzzle.nodes:
                continue
            x1, y1 = puzzle.nodes[n1]
            x2, y2 = puzzle.nodes[n2]
            ax.plot([x1, x2], [y1, y2], color=color, linewidth=9 - i * 2, alpha=0.45, zorder=1)

    # all edges
    for (a, b), e in puzzle.edges.items():
        x1, y1 = puzzle.nodes[a]
        x2, y2 = puzzle.nodes[b]
        if e.is_scenery:
            color = "#777"
            alpha = 0.4
        elif e.damaged:
            color = "#222"
            alpha = 0.6
        else:
            color = "#222"
            alpha = 0.8
        ax.plot([x1, x2], [y1, y2], color=color, linewidth=1.2, zorder=2, alpha=alpha)

    # nodes
    for nid, (x, y) in puzzle.nodes.items():
        if nid == puzzle.source:
            color, size = "limegreen", 14
        elif nid == puzzle.target:
            color, size = "magenta", 14
        elif nid in puzzle.scenery_nodes:
            color, size = "#888", 6
        elif nid.startswith("Trap"):
            color, size = "#c85050", 8
        else:
            color, size = "#3090d0", 10
        ax.plot(x, y, marker="o", markersize=size, color=color, zorder=4,
                markeredgecolor="black", markeredgewidth=1.0)

    ax.set_xlim(-0.5, puzzle.grid_w - 0.5)
    ax.set_ylim(-0.5, puzzle.grid_h - 0.5)
    ax.set_aspect("equal")
    ax.invert_yaxis()
    ax.set_xticks([])
    ax.set_yticks([])

    title = f"{label}\nB={report['budget']} {report['status']} n={report['n_nodes']}t"
    ax.set_title(title, fontsize=9)


def plot_grid(results, cols, path):
    n = len(results)
    rows = (n + cols - 1) // cols
    fig, axes = plt.subplots(rows, cols, figsize=(cols * 3.5, rows * 3.5))
    if rows == 1 and cols == 1:
        axes = [axes]
    elif rows == 1 or cols == 1:
        axes = list(axes) if hasattr(axes, '__len__') else [axes]
    else:
        axes = axes.flatten()

    for i, (puzzle, report, label) in enumerate(results):
        plot_puzzle_on_axis(puzzle, report, axes[i], label)

    for j in range(n, len(axes)):
        axes[j].axis("off")

    plt.tight_layout()
    fig.savefig(path, dpi=100)
    plt.close(fig)
    return path


# ============================================================
# JSON export for Godot
# ============================================================

import json

def to_godot_json(puzzle, report, label):
    """Serialize puzzle for Godot consumption.

    Schema matches what level_loader.gd will expect:
      - grid_w, grid_h
      - source: [x, y] tile coord
      - target: [x, y] tile coord
      - budget: int
      - towers: list of {id, x, y, is_scenery, is_trap}
      - edges: list of {a_id, b_id, distance, terrain, is_scenery, damaged}
      - tiles: list of {x, y, terrain} -- only non-plain tiles (plain is default)
      - shapes: dict of shape name -> {range, cost, passes (list)}
      - solutions: list (informational; for win condition & debug)
      - label: string
    """
    tower_list = []
    for nid, (x, y) in puzzle.nodes.items():
        tower_list.append({
            "id": nid,
            "x": x, "y": y,
            "is_scenery": nid in puzzle.scenery_nodes,
            "is_trap": nid.startswith("Trap"),
            "is_source": nid == puzzle.source,
            "is_target": nid == puzzle.target,
        })

    edge_list = []
    for (a, b), e in puzzle.edges.items():
        edge_list.append({
            "a_id": a, "b_id": b,
            "distance": e.distance,
            "terrain": e.terrain,
            "is_scenery": e.is_scenery,
            "damaged": e.damaged,
        })

    # Only ship non-plain tiles to keep file size down
    tile_list = [
        {"x": x, "y": y, "terrain": t}
        for (x, y), t in puzzle.tiles.items()
        if t != Terrain.PLAIN
    ]

    shapes_out = {
        name: {"range": s.max_range, "cost": s.cost, "passes": list(s.passes)}
        for name, s in puzzle.shapes.items()
    }

    # Solutions (paths + costs, informational)
    solution_list = []
    for path, cost in report["solutions"]:
        solution_list.append({
            "cost": cost,
            "steps": [{"node": step[0], "shape": step[1]} for step in path],
        })

    return {
        "label": label,
        "grid_w": puzzle.grid_w,
        "grid_h": puzzle.grid_h,
        "source": list(puzzle.nodes[puzzle.source]),
        "target": list(puzzle.nodes[puzzle.target]),
        "budget": puzzle.budget,
        "towers": tower_list,
        "edges": edge_list,
        "tiles": tile_list,
        "shapes": shapes_out,
        "solutions": solution_list,
        "status": report["status"],
    }


def export_godot_levels(good_results, out_dir="/home/claude/levels"):
    """Write one JSON per GOOD puzzle."""
    import os
    os.makedirs(out_dir, exist_ok=True)
    written = []
    for i, (puzzle, report, label) in enumerate(good_results):
        data = to_godot_json(puzzle, report, label)
        path = os.path.join(out_dir, f"level_{i+1:02d}_{label.replace('=', '_')}.json")
        with open(path, "w") as f:
            json.dump(data, f, indent=2)
        written.append(path)
    return written


# ============================================================
# Main: parameter sweep
# ============================================================

def main():
    results = []
    for seed in range(1, 501):  # sweep many seeds, filter for GOOD
        puzzle, report = generate_level(seed=seed, budget=100, grid_size=15, target_hops=5, n_scenery=6)
        results.append((puzzle, report, f"seed={seed}"))

    statuses = Counter(r["status"].split("(")[0] for _, r, _ in results)
    print("Status breakdown (500 seeds):")
    for s, c in statuses.most_common():
        print(f"  {s}: {c}")

    good = [r for r in results if r[1]["status"].startswith("GOOD")]
    print(f"\n{len(good)} GOOD puzzles found.")

    # Visualize first 24 good ones
    good_preview = good[:24]
    if good_preview:
        good_path = plot_grid(good_preview, cols=6, path="/home/claude/signal_v4_good.png")
        print(f"Saved grid of {len(good_preview)} good puzzles to {good_path}")

    # Export first 10 to JSON for Godot
    to_export = good[:10]
    written = export_godot_levels(to_export, out_dir="/home/claude/levels")
    print(f"\nExported {len(written)} levels to JSON:")
    for p in written:
        print(f"  {p}")


if __name__ == "__main__":
    main()