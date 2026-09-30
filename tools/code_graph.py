#!/usr/bin/env python3
"""Print the file and cluster dependency graph of the game's packages.

File A has an edge to file B when A's code names a top level definition
of B (the parser of check_dead_code.py: comments and strings stripped).
The weight of an edge is the number of such references. A name resolves
in the file's own package, or in an imported package when it follows the
import's name and a dot (platform.log_printf); every other dotted name
still resolves in the own package, so a field named like a top level
procedure counts as graph noise. The files of the game package (src/*.odin)
are grouped into clusters by the name prefix before the first underscore,
through the tables below (a file override first); a file whose prefix
the tables do not know joins the cluster it references most, and the
script prints that choice. Each package under src/ (work item 0145) is
a cluster named after its directory, and its files are named with the
directory (platform/logging.odin). A package never reaches the game
package (Odin forbids the import cycle), which the check shows as the
package clusters' edges into game clusters.

Prints the cluster edge table, the pairs of clusters that reference each
other, the strongly connected components of the file graph (the size of
the largest and the files outside it) and the ten files of the largest
component with the fewest edges into it.

Options: --files adds each file's edges, --json dumps the graph instead,
--tests includes the *_test.odin files. --check MAP compares the cluster
edges that the map's allowed dependency table (the Markdown table whose
second header cell is "May reference") does not allow with the map's
record of them (the "Reaches into:" line of each "## <cluster>" section,
"target count (notes)" parts separated by commas): it exits 1 when an
edge is new or above its recorded count, 2 when the map cannot be read,
0 otherwise. Run from anywhere:
python3 tools/code_graph.py --check doc/code_map.md
"""

import argparse
import json
import pathlib
import re
import sys

# The import would otherwise leave a __pycache__ directory in tools/.
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from check_dead_code import (  # noqa: E402
    IDENTIFIER,
    SOURCE_DIRECTORY,
    all_odin_files,
    code_lines,
    is_test_file,
    parse_definitions,
)

GAME_PACKAGE = "game"

# The clusters of the game package in the order of doc/code_map.md; the
# package clusters follow, one per directory under src/.
GAME_CLUSTERS = ("loop", "ui", "world", "simulation", "presentation", "content", "tools")
PACKAGE_CLUSTERS = tuple(sorted(path.name for path in SOURCE_DIRECTORY.iterdir() if path.is_dir()))
CLUSTERS = GAME_CLUSTERS + PACKAGE_CLUSTERS

IMPORT_LINE = re.compile(r'^\s*(?:@\([^)]*\)\s*)?import\s+(?:([A-Za-z_]\w*)\s+)?"([^"]+)"')

PREFIX_CLUSTERS = {
    "loop": ("loop", "main", "session", "simulation", "hot"),
    "ui": ("hud", "touch", "input", "bindings", "text", "quick", "biome", "haptics", "system"),
    "world": ("generation", "save", "block", "landing"),
    "simulation": (
        "entity", "belt", "splitter", "inserter", "fluid", "power", "machine", "assembler",
        "furnace", "drill", "lab", "launch", "crafting", "inventory", "item", "player",
        "loose", "statistics", "production", "developer", "venture", "recycler", "schematic",
        "prospecting", "tree", "tick",
    ),
    "presentation": (
        "render", "model", "texture", "particles", "ambient", "audio", "sound", "display", "weather",
        "raylib",
    ),
    "content": (
        "data", "recipe", "technology", "quest", "contract", "notes", "configuration",
        "settings", "deck", "discovery",
    ),
    "tools": ("command", "diagnostics", "benchmark"),
}

# Files whose prefix names the wrong cluster; the prefix rule keeps the
# other files of the prefix (item_transfer.odin stays in simulation).
FILE_CLUSTERS = {
    "item.odin": "content",
    "quest_runtime.odin": "simulation",
    "recipe_unlocks.odin": "simulation",
    "player_animation.odin": "presentation",
    "data_browser.odin": "tools",
    "data_export.odin": "tools",
}

LARGEST_COMPONENT_REPORT_COUNT = 10


def file_prefix(name):
    return name.removesuffix(".odin").split("_")[0]


def known_cluster(prefix):
    for cluster, prefixes in PREFIX_CLUSTERS.items():
        if prefix in prefixes:
            return cluster
    return prefix if prefix in GAME_CLUSTERS else None


def file_package(name):
    """The package of a file name: its directory, or the game package."""
    return name.split("/")[0] if "/" in name else GAME_PACKAGE


def file_name(path):
    """src/loop.odin is loop.odin, src/platform/logging.odin is
    platform/logging.odin."""
    return path.relative_to(SOURCE_DIRECTORY).as_posix()


def source_files(include_tests):
    return [path for path in all_odin_files() if include_tests or not is_test_file(path)]


def package_imports(path):
    """Returns {import name: package} for the imports of packages under
    src/ (a path without a collection, such as "platform" or
    "../platform")."""
    imports = {}
    for line in path.read_text(encoding="utf-8").splitlines():
        match = IMPORT_LINE.match(line)
        if match and ":" not in match.group(2):
            package = match.group(2).rstrip("/").split("/")[-1]
            imports[match.group(1) or package] = package
    return imports


def resolved_occurrences(path, lines):
    """Returns (package or None, name, line) for every identifier: the
    package an import qualifies it with, None when unqualified. The
    import's own name before the dot is no occurrence."""
    imports = package_imports(path)
    occurrences = []
    for index, line in enumerate(lines):
        qualifier = None
        for match in IDENTIFIER.finditer(line):
            name, after = match.group(0), line[match.end():].lstrip()
            before = line[:match.start()].rstrip()
            if name in imports and after.startswith(".") and not before.endswith("."):
                qualifier = imports[name]
                continue
            occurrences.append((qualifier if before.endswith(".") else None, name, index + 1))
            qualifier = None
    return occurrences


def file_edges(paths):
    """Returns {from name: {to name: reference count}} over the files."""
    names = {path: file_name(path) for path in paths}
    lines_by_file = {path: code_lines(path) for path in paths}
    owners, sites = {}, set()
    for path in paths:
        package = file_package(names[path])
        for definition in parse_definitions(path, lines_by_file[path]):
            owners.setdefault((package, definition["name"]), set()).add(names[path])
            sites.add((definition["name"], names[path], definition["line"]))
    edges = {names[path]: {} for path in paths}
    for path in paths:
        source = names[path]
        targets = edges[source]
        for qualifier, name, line in resolved_occurrences(path, lines_by_file[path]):
            # A definition line of the name (a platform variant's) is no
            # reference to it.
            if (name, source, line) in sites:
                continue
            for owner in owners.get((qualifier or file_package(source), name), ()):
                if owner != source:
                    targets[owner] = targets.get(owner, 0) + 1
    return edges


def file_cluster(name):
    package = file_package(name)
    if package != GAME_PACKAGE:
        return package
    return FILE_CLUSTERS.get(name) or known_cluster(file_prefix(name))


def assign_clusters(edges):
    """Returns ({file: cluster}, {file: cluster chosen by its edges})."""
    clusters = {name: file_cluster(name) for name in edges}
    chosen = {}
    for name, cluster in clusters.items():
        if cluster is None:
            chosen[name] = busiest_cluster(edges[name], clusters)
    clusters.update(chosen)
    return clusters, chosen


def busiest_cluster(targets, clusters):
    totals = {}
    for target, count in targets.items():
        cluster = clusters.get(target)
        if cluster is not None:
            totals[cluster] = totals.get(cluster, 0) + count
    if not totals:
        return "unassigned"
    return max(sorted(totals), key=lambda cluster: totals[cluster])


def cluster_edges(edges, clusters):
    """Returns {(from cluster, to cluster): reference count}."""
    totals = {}
    for source, targets in edges.items():
        for target, count in targets.items():
            pair = (clusters[source], clusters[target])
            if pair[0] != pair[1]:
                totals[pair] = totals.get(pair, 0) + count
    return totals


def mutual_pairs(totals):
    pairs = []
    for (first, second), count in sorted(totals.items()):
        back = totals.get((second, first))
        if back is not None and first < second:
            pairs.append((first, second, count, back))
    return pairs


def strongly_connected_components(edges):
    """Tarjan's algorithm, iterative. Returns lists of file names."""
    index_of, low_of, on_stack = {}, {}, set()
    stack, components, counter = [], [], [0]
    for root in sorted(edges):
        if root not in index_of:
            visit_component(root, edges, index_of, low_of, on_stack, stack, components, counter)
    return components


def visit_component(root, edges, index_of, low_of, on_stack, stack, components, counter):
    work = [(root, iter(sorted(edges[root])))]
    enter_node(root, index_of, low_of, on_stack, stack, counter)
    while work:
        node, children = work[-1]
        child = next(children, None)
        if child is None:
            work.pop()
            if work:
                parent = work[-1][0]
                low_of[parent] = min(low_of[parent], low_of[node])
            if low_of[node] == index_of[node]:
                components.append(pop_component(node, on_stack, stack))
        elif child not in index_of:
            enter_node(child, index_of, low_of, on_stack, stack, counter)
            work.append((child, iter(sorted(edges[child]))))
        elif child in on_stack:
            low_of[node] = min(low_of[node], index_of[child])


def enter_node(node, index_of, low_of, on_stack, stack, counter):
    index_of[node] = low_of[node] = counter[0]
    counter[0] += 1
    stack.append(node)
    on_stack.add(node)


def pop_component(node, on_stack, stack):
    component = []
    while True:
        member = stack.pop()
        on_stack.discard(member)
        component.append(member)
        if member == node:
            return sorted(component)


def edges_into(name, members, edges):
    return sum(1 for target in edges[name] if target in members)


def print_cluster_assignment(chosen):
    print("Files outside the tables, joined to the cluster they reference most:")
    for name in sorted(chosen):
        print(f"  {name} -> {chosen[name]}")
    print()


def print_cluster_edges(totals):
    print("Cluster edges (references):")
    for (source, target), count in sorted(totals.items(), key=lambda item: (-item[1], item[0])):
        print(f"  {source:>12} -> {target:<12} {count}")
    print()


def print_mutual_pairs(pairs):
    print("Mutual cluster pairs (references each way):")
    for first, second, forward, back in pairs:
        print(f"  {first} <-> {second}: {forward} / {back}")
    print()


def print_components(components, edges):
    largest = max(components, key=len)
    members = set(largest)
    outside = sorted(name for name in edges if name not in members)
    print(f"Strongly connected components: {len(components)}")
    print(f"Largest component: {len(largest)} of {len(edges)} files")
    print(f"Files outside it ({len(outside)}): {' '.join(outside)}")
    print()
    print(f"The {LARGEST_COMPONENT_REPORT_COUNT} files of the largest component with the fewest edges into it:")
    ranked = sorted(largest, key=lambda name: (edges_into(name, members, edges), name))
    for name in ranked[:LARGEST_COMPONENT_REPORT_COUNT]:
        print(f"  {name}: {edges_into(name, members, edges)}")
    print()


def print_file_edges(edges, clusters):
    incoming = {name: {} for name in edges}
    for source, targets in edges.items():
        for target, count in targets.items():
            incoming[target][source] = count
    print("File edges:")
    for name in sorted(edges):
        print(f"  {name} [{clusters[name]}]")
        print(f"    out: {format_targets(edges[name])}")
        print(f"    in:  {format_targets(incoming[name])}")


def format_targets(targets):
    return " ".join(f"{name}:{count}" for name, count in sorted(targets.items())) or "-"


def dump_json(edges, clusters, totals, components):
    graph = {
        "files": {name: {"cluster": clusters[name], "edges": edges[name]} for name in sorted(edges)},
        "clusters": [{"from": source, "to": target, "references": count} for (source, target), count in sorted(totals.items())],
        "components": sorted(components, key=len, reverse=True),
    }
    json.dump(graph, sys.stdout, indent=1)
    print()


class Map_Error(Exception):
    """A map whose allowed table or reach records the check cannot read."""


def markdown_tables(text):
    """Returns the tables of a Markdown text as lists of rows of cells."""
    tables, current = [], []
    for line in text.split("\n"):
        if line.strip().startswith("|"):
            current.append([cell.strip() for cell in line.strip().strip("|").split("|")])
        elif current:
            tables.append(current)
            current = []
    if current:
        tables.append(current)
    return tables


def known_cluster_name(name, where):
    if name not in CLUSTERS:
        raise Map_Error(f"unknown cluster {name} in {where}")
    return name


def listed_clusters(cell, where):
    """Returns the clusters a cell lists, [] for "nothing"."""
    names = [word.strip() for word in re.split(r",|\band\b", cell.replace("`", "")) if word.strip()]
    if names == ["nothing"]:
        return []
    return [known_cluster_name(name, where) for name in names]


def allowed_table(text):
    """Returns {cluster: set of allowed clusters} from the table whose
    second header cell is "May reference"."""
    where = "the allowed dependency table"
    tables = [table for table in markdown_tables(text) if len(table[0]) >= 2 and table[0][1].lower() == "may reference"]
    if not tables:
        raise Map_Error("no allowed dependency table found")
    allowed = {}
    for row in tables[0][2:]:
        cluster = known_cluster_name(row[0].replace("`", ""), where)
        if cluster in allowed:
            raise Map_Error(f"duplicate row for the cluster {cluster} in {where}")
        allowed[cluster] = set(listed_clusters(row[1] if len(row) > 1 else "", where))
    for cluster in CLUSTERS:
        if cluster not in allowed:
            raise Map_Error(f"no row for the cluster {cluster} in {where}")
    return allowed


def top_level_parts(text):
    """Splits at the commas outside parentheses."""
    parts, depth, current = [], 0, ""
    for character in text:
        depth += {"(": 1, ")": -1}.get(character, 0)
        if character == "," and depth == 0:
            parts.append(current)
            current = ""
        else:
            current += character
    return parts + [current]


def reach_record(line, source):
    """Returns {(source, target): count} from one "Reaches into:" line."""
    body = line.split("Reaches into:", 1)[1].strip().rstrip(".")
    if body == "nothing":
        return {}
    record = {}
    for part in top_level_parts(body):
        match = re.match(r"\s*(\w+) (\d+)\b", part)
        if match is None:
            raise Map_Error(f"cannot read the reach record of {source}: {part.strip()}")
        target = known_cluster_name(match.group(1), f"the reach record of {source}")
        record[(source, target)] = int(match.group(2))
    return record


def recorded_reaches(text):
    """Returns {(source, target): count} from the "Reaches into:" line of
    each cluster section (a "## <cluster>" heading)."""
    record, section, seen = {}, None, set()
    for line in text.split("\n"):
        if line.startswith("## "):
            section = line[3:].strip()
        elif "Reaches into:" in line and section in CLUSTERS:
            if section in seen:
                raise Map_Error(f"two reach records in the section {section}")
            seen.add(section)
            record.update(reach_record(line, section))
    return record


def disallowed_edges(totals, allowed):
    return {pair: count for pair, count in totals.items() if pair[1] not in allowed[pair[0]]}


def edge_verdict(count, recorded):
    if recorded is None:
        return "not recorded, new", True
    if count > recorded:
        return f"recorded {recorded}, grew", True
    if count < recorded:
        return f"recorded {recorded}, below: lower the map's record", False
    return f"recorded {recorded}", False


def check_map(map_path, totals):
    text = pathlib.Path(map_path).read_text()
    try:
        allowed, record = allowed_table(text), recorded_reaches(text)
    except Map_Error as error:
        print(f"{map_path}: {error}")
        return 2
    edges = disallowed_edges(totals, allowed)
    failures = 0
    print(f"Cluster edges against the allowed table of {map_path} (references):")
    for (source, target), count in sorted(edges.items(), key=lambda item: (-item[1], item[0])):
        verdict, failed = edge_verdict(count, record.get((source, target)))
        failures += failed
        print(f"  {source:>12} -> {target:<12} {count} ({verdict})")
    for (source, target), recorded in sorted(record.items()):
        if (source, target) not in edges:
            print(f"  {source:>12} -> {target:<12} 0 (recorded {recorded}, gone: remove it from the map)")
    print(f"{len(edges)} edges against the table, {sum(edges.values())} references, {failures} new or grown")
    return 1 if failures else 0


def parse_arguments():
    parser = argparse.ArgumentParser(description="The file and cluster dependency graph of src/.")
    parser.add_argument("--files", action="store_true", help="also print each file's in and out edges")
    parser.add_argument("--json", action="store_true", help="dump the graph as JSON")
    parser.add_argument("--tests", action="store_true", help="include the *_test.odin files")
    parser.add_argument("--check", metavar="MAP", help="print the cluster edges the map's allowed table does not allow")
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    edges = file_edges(source_files(arguments.tests))
    clusters, chosen = assign_clusters(edges)
    totals = cluster_edges(edges, clusters)
    if arguments.check:
        print_cluster_assignment(chosen)
        return check_map(arguments.check, totals)
    components = strongly_connected_components(edges)
    if arguments.json:
        dump_json(edges, clusters, totals, components)
        return 0
    print_cluster_assignment(chosen)
    print_cluster_edges(totals)
    print_mutual_pairs(mutual_pairs(totals))
    print_components(components, edges)
    if arguments.files:
        print_file_edges(edges, clusters)
    return 0


if __name__ == "__main__":
    sys.exit(main())
