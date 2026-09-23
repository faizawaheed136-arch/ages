"""Report what is inside each downloaded .glb: its meshes, their sizes, and the model's bounds.

    python sandbox/dealership/props/inspect_glb.py [key ...]

Reads the glTF JSON chunk only -- accessor min/max give every mesh's extent without decoding a
single vertex -- and walks the node tree applying each node's matrix or translation, rotation and
scale. Sizes are in glTF units (metres, Y up), the same units Roblox's importer reads them in.
Used to decide how each prop is scaled and turned when it stands in for the builder's block
version, and to find which object in a pack (a tree pack, a cone pack) to use.
"""

import json
import pathlib
import struct
import sys

import numpy as np

HERE = pathlib.Path(__file__).resolve().parent


def gltf_json(path: pathlib.Path) -> dict:
    data = path.read_bytes()
    magic, _version, _length = struct.unpack_from("<III", data, 0)
    if magic != 0x46546C67:
        raise ValueError(f"{path.name} is not a .glb")
    chunk_length, chunk_type = struct.unpack_from("<II", data, 12)
    if chunk_type != 0x4E4F534A:
        raise ValueError(f"{path.name}: first chunk is not JSON")
    return json.loads(data[20 : 20 + chunk_length])


def node_matrix(node: dict) -> np.ndarray:
    if "matrix" in node:
        return np.array(node["matrix"], float).reshape(4, 4).T
    t = np.array(node.get("translation", [0, 0, 0]), float)
    x, y, z, w = node.get("rotation", [0, 0, 0, 1])
    s = np.array(node.get("scale", [1, 1, 1]), float)
    r = np.array(
        [
            [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
            [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
            [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
        ]
    )
    m = np.eye(4)
    m[:3, :3] = r * s
    m[:3, 3] = t
    return m


def mesh_bounds(doc: dict, mesh_index: int):
    lo, hi = np.full(3, np.inf), np.full(3, -np.inf)
    for prim in doc["meshes"][mesh_index]["primitives"]:
        acc = doc["accessors"][prim["attributes"]["POSITION"]]
        lo = np.minimum(lo, acc["min"])
        hi = np.maximum(hi, acc["max"])
    return lo, hi


def objects(doc: dict):
    """Every mesh node with its world-space bounds, walking from the scene's roots."""
    out = []
    scene = doc["scenes"][doc.get("scene", 0)]

    def walk(index, parent):
        node = doc["nodes"][index]
        world = parent @ node_matrix(node)
        if "mesh" in node:
            lo, hi = mesh_bounds(doc, node["mesh"])
            corners = np.array([[x, y, z, 1] for x in (lo[0], hi[0]) for y in (lo[1], hi[1]) for z in (lo[2], hi[2])])
            pts = (world @ corners.T).T[:, :3]
            out.append((node.get("name", f"node{index}"), pts.min(axis=0), pts.max(axis=0)))
        for child in node.get("children", []):
            walk(child, world)

    for root in scene["nodes"]:
        walk(root, np.eye(4))
    return out


def main() -> int:
    keys = sys.argv[1:] or sorted(p.stem for p in (HERE / "downloads").glob("*.glb"))
    for key in keys:
        doc = gltf_json(HERE / "downloads" / f"{key}.glb")
        objs = objects(doc)
        lo = np.min([o[1] for o in objs], axis=0)
        hi = np.max([o[2] for o in objs], axis=0)
        size = hi - lo
        tris = sum(
            doc["accessors"][p["indices"]]["count"] // 3 if "indices" in p else doc["accessors"][p["attributes"]["POSITION"]]["count"] // 3
            for m in doc["meshes"]
            for p in m["primitives"]
        )
        print(f"{key}: {len(objs)} mesh nodes, {tris} triangles, {len(doc.get('images', []))} textures")
        print(f"   bounds  x {lo[0]:8.2f}..{hi[0]:8.2f}  y {lo[1]:8.2f}..{hi[1]:8.2f}  z {lo[2]:8.2f}..{hi[2]:8.2f}   size {size[0]:.2f} x {size[1]:.2f} x {size[2]:.2f}")
        if len(objs) > 1:
            for name, a, b in objs[:12]:
                c = (a + b) / 2
                s = b - a
                print(f"     - {name[:36]:36} centre ({c[0]:7.2f},{c[1]:7.2f},{c[2]:7.2f}) size {s[0]:.2f} x {s[1]:.2f} x {s[2]:.2f}")
            if len(objs) > 12:
                print(f"     ... {len(objs) - 12} more")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
