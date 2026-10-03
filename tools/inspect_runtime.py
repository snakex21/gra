"""Locate local runtimes and read selected source ranges without shell quoting."""
import os
import sys
from pathlib import Path

if len(sys.argv) > 1:
    p = Path(sys.argv[1])
    lines = p.read_text(encoding="utf-8-sig").splitlines()
    start = int(sys.argv[2]) if len(sys.argv) > 2 else 1
    end = int(sys.argv[3]) if len(sys.argv) > 3 else len(lines)
    for i in range(start - 1, min(end, len(lines))):
        print(f"{i + 1}: {lines[i]}")
else:
    roots = [Path("C:/Program Files"), Path("C:/tools"), Path("C:/Users/ASRock/Desktop"), Path("C:/Users/ASRock/Downloads"), Path("D:/")]
    for root in roots:
        if not root.exists():
            continue
        for folder, dirs, files in os.walk(root):
            depth = len(Path(folder).relative_to(root).parts)
            dirs[:] = [d for d in dirs if depth < 3 and d not in ("node_modules", ".git", ".godot")]
            for name in files:
                if name.lower().endswith(".exe") and any(t in name.lower() for t in ("godot", "blender")):
                    print(Path(folder) / name)
