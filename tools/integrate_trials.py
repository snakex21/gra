"""Attach common trial navigation to completed scenes only."""
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
COMPLETED = ("valus", "quadratus", "gaius", "phaedra", "avion", "hydrus", "cave", "barba", "kuromori", "basaran", "dirge", "pelagia", "argus")
for kind in COMPLETED:
    path = ROOT / "scenes" / f"{kind}_arena.gd"
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    if "TrialMenu.attach(self)" not in text:
        needle = "\tInputSetup.ensure_defaults()"
        if needle not in text:
            raise RuntimeError(f"No input setup in {path}")
        path.write_text(text.replace(needle, needle + "\n\tTrialMenu.attach(self)", 1), encoding="utf-8")
