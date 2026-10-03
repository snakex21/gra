"""Push the current branch using existing gh login, without changing global config."""
from pathlib import Path
import subprocess
import sys

root = Path(__file__).resolve().parents[1]
branch = subprocess.check_output(
    ["git", "branch", "--show-current"], cwd=root, text=True
).strip()
if not branch:
    raise SystemExit("No current branch; refusing to publish a detached checkout")
result = subprocess.run(
    ["git", "-c", "credential.helper=", "-c",
     "credential.helper=!gh auth git-credential", "push", "--set-upstream", "origin", branch],
    cwd=root,
)
sys.exit(result.returncode)
