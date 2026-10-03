"""Configure authored 3D PNG imports without changing source pixels or GLBs.

Run with --apply to change sidecars, or --check for a read-only CI check.
Only textures/ and models/ extracted PNGs are eligible; UI/captures are excluded.
No application configuration, environment, importer, or global cache is changed.
"""
import argparse
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
EXCLUDED = {"ui", "hud", "icons", "captures", "screenshots", "output"}


def desired_options(source):
    options = {
        "compress/mode": "2",
        "compress/high_quality": "false",  # S3TC/RGTC; older OpenGL hardware.
        "mipmaps/generate": "true",
        "detect_3d/compress_to": "1",
    }
    if source.stem.lower().endswith("_normal"):
        options["compress/normal_map"] = "1"
    return options


def replace_params(text, options):
    # Preserve UID, resource remaps, channel remaps, normal Y convention and size.
    match = re.search(r"(?ms)^\[params\]\s*\n(.*?)(?=^\[|\Z)", text)
    if not match:
        raise ValueError("Texture sidecar has no [params] section")
    block = match.group(1)
    changed = []
    for key, value in options.items():
        pattern = re.compile(r"(?m)^" + re.escape(key) + r"=(.*)$")
        found = pattern.search(block)
        if found and found.group(1).strip() == value:
            continue
        changed.append(key)
        if found:
            block = pattern.sub(lambda _: key + "=" + value, block, count=1)
        else:
            block = block.rstrip() + "\n" + key + "=" + value + "\n"
    return text[:match.start(1)] + block + text[match.end(1):], changed


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument("--apply", action="store_true")
    mode.add_argument("--check", action="store_true")
    parser.add_argument("--verbose", action="store_true", help="List each changed sidecar")
    args = parser.parse_args()
    eligible = changed_files = normals = 0
    errors = []
    sources = sorted(path for folder in [ROOT / "textures", ROOT / "models"] for path in folder.rglob("*.png"))
    for source in sources:
        if EXCLUDED.intersection(part.lower() for part in source.relative_to(ROOT).parts[:-1]):
            continue
        eligible += 1
        sidecar = Path(str(source) + ".import")
        try:
            text = sidecar.read_text(encoding="utf-8-sig")
            if 'importer="texture"' not in text:
                raise ValueError("Not a Godot texture import")
            options = desired_options(source)
            normals += "compress/normal_map" in options
            replacement, changes = replace_params(text, options)
            if changes:
                changed_files += 1
                if args.apply:
                    sidecar.write_text(replacement, encoding="utf-8", newline="\n")
                if args.verbose:
                    print(("UPDATED" if args.apply else "NEEDS_UPDATE"), sidecar.relative_to(ROOT).as_posix(), ",".join(changes))
        except (OSError, ValueError) as error:
            errors.append(str(source.relative_to(ROOT)) + ": " + str(error))
    print("TEXTURE_IMPORT_CONFIGURATION", "eligible=", eligible, "normal_maps=", normals,
          "changed=", changed_files, "errors=", len(errors), "mode=", "apply" if args.apply else "check")
    for error in errors:
        print("ERROR", error)
    return 1 if errors or (not args.apply and changed_files) else 0


if __name__ == "__main__":
    raise SystemExit(main())
