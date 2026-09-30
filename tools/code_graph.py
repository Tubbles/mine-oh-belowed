#!/usr/bin/env python3
"""Print the file and cluster dependency graph of the game package.

File A has an edge to file B when A's code names a top level definition
of B (the parser of check_dead_code.py: comments and strings stripped).
The weight of an edge is the number of such references. Files are
grouped into clusters by the name prefix before the first underscore,
through the tables below (a file override first); a file whose prefix
the tables do not know joins the cluster it references most, and the
script prints that choice.

Prints the cluster edge table, the pairs of clusters that reference each
other, the strongly connected components of the file graph (the size of
the largest and the files outside it) and the ten files of the largest
component with the fewest edges into it.

Options: --files adds each file's edges, --json dumps the graph instead,
--tests includes the *_test.odin files. Run from anywhere:
python3 tools/code_graph.py
"""

import argparse
import json
import pathlib
import sys

# The import would otherwise leave a __pycache__ directory in tools/.
sys.dont_write_bytecode = True
sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from check_dead_code import (  # noqa: E402
    code_lines,
    game_source_files,
    identifier_occurrences,
    is_test_file,
    parse_definitions,
)

CLUSTERS = ("ui", "world", "presentation", "simulation", "content", "loop")

PREFIX_CLUSTERS = {
    "ui": ("hud", "touch", "input", "bindings", "text", "haptics", "system"),
    "world": ("generation", "save", "block"),
    "presentation": ("render", "model", "texture", "particles", "ambient", "audio", "sound", "display", "raylib"),
    "simulation": (
        "entity", "belt", "splitter", "inserter", "fluid", "power", "machine", "assembler",
        "furnace", "drill", "lab", "launch", "crafting", "inventory", "item", "player",
        "loose", "statistics",
    ),
    "content": (
        "data", "recipe", "technology", "quest", "contract", "notes", "configuration",
        "settings", "command", "logging", "local", "platform", "export", "sjson", "run", "jni",
    ),
    "loop": ("loop", "main", "session", "simulation"),
}

# Files whose prefix names the wrong cluster; the prefix rule keeps the
# other files of the prefix (item_transfer.odin stays in simulation).
FILE_CLUSTERS = {
    "item.odin": "content",
}

LARGEST_COMPONENT_REPORT_COUNT = 10


def file_prefix(name):
    return name.removesuffix(".odin").split("_")[0]


def known_cluster(prefix):
    for cluster, prefixes in PREFIX_CLUSTERS.items():
        if prefix in prefixes:
            return cluster
    return prefix if prefix in CLUSTERS else None


def source_files(include_tests):
    return [path for path in game_source_files() if include_tests or not is_test_file(path)]


def file_edges(paths):
    """Returns {from name: {to name: reference count}} over the files."""
    lines_by_file = {path.name: code_lines(path) for path in paths}
    owners, sites = {}, set()
    for path in paths:
        for definition in parse_definitions(path, lines_by_file[path.name]):
            owners.setdefault(definition["name"], set()).add(path.name)
            sites.add((definition["name"], path.name, definition["line"]))
    edges = {path.name: {} for path in paths}
    for path in paths:
        targets = edges[path.name]
        for name, line in identifier_occurrences(path, lines_by_file[path.name]):
            # A definition line of the name (a platform variant's) is no
            # reference to it.
            if (name, path.name, line) in sites:
                continue
            for owner in owners.get(name, ()):
                if owner != path.name:
                    targets[owner] = targets.get(owner, 0) + 1
    return edges


def assign_clusters(edges):
    """Returns ({file: cluster}, {file: cluster chosen by its edges})."""
    clusters = {name: FILE_CLUSTERS.get(name) or known_cluster(file_prefix(name)) for name in edges}
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


def parse_arguments():
    parser = argparse.ArgumentParser(description="The file and cluster dependency graph of src/.")
    parser.add_argument("--files", action="store_true", help="also print each file's in and out edges")
    parser.add_argument("--json", action="store_true", help="dump the graph as JSON")
    parser.add_argument("--tests", action="store_true", help="include the *_test.odin files")
    return parser.parse_args()


def main():
    arguments = parse_arguments()
    edges = file_edges(source_files(arguments.tests))
    clusters, chosen = assign_clusters(edges)
    totals = cluster_edges(edges, clusters)
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
