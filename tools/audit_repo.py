"""Read-only packaging inventory. Never reads file contents or follows symlinks."""
from pathlib import Path
import os
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
if "--staged" in sys.argv:
    names = subprocess.check_output(["git", "diff", "--cached", "--name-only", "-z"], cwd=root).decode().split("\0")
    selected = [root / name for name in names if name and (root / name).is_file()]
    forbidden = [p.relative_to(root).as_posix() for p in selected if p.relative_to(root).as_posix().startswith(("tools/runtime/", ".godot/", "data/tests/", "data/replays/")) or p.name.startswith("save") and p.parent == root / "data"]
    large = [p.relative_to(root).as_posix() for p in selected if p.stat().st_size >= 100 * 2**20]
    print(f"Staged {len(selected)} files, {sum(p.stat().st_size for p in selected) / 2**20:.1f} MiB; largest {max((p.stat().st_size for p in selected), default=0) / 2**20:.1f} MiB")
    print("Runtime/player-data files:", forbidden)
    print("Files above 100 MiB:", large)
    raise SystemExit(1 if forbidden or large else 0)
skip = {".git", ".godot", "runtime", "__pycache__"}
files = []
for directory, dirs, names in os.walk(root, followlinks=False):
    dirs[:] = [d for d in dirs if d not in skip]
    for name in names:
        path = Path(directory) / name
        if not path.is_symlink():
            files.append((path.stat().st_size, path.relative_to(root).as_posix()))
print(f"Files excluding engine/cache: {len(files)}; total {sum(s for s, _ in files) / 2**20:.1f} MiB")
for size, name in sorted(files, reverse=True)[:30]:
    print(f"{size / 2**20:9.1f} MiB {name}")
for size, name in files:
    if Path(name).name.startswith(".env") or Path(name).suffix.lower() in {".pem", ".pfx", ".key"}:
        print("Potential private configuration filename:", name)
