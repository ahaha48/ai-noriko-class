"""Build reviewed, deterministic ZIP artifacts; never include runtime data."""
from pathlib import Path
import hashlib
import json
import re
import zipfile

ROOT = Path(__file__).resolve().parent.parent
WORKSPACE = ROOT.parent
OUT = ROOT / "docs" / "downloads"
OUT.mkdir(parents=True, exist_ok=True)
KIT = WORKSPACE / "AI-NORIKO-Starter-Kit"
GUIDE = WORKSPACE / "AI-NORIKO-Learning-Guide"
ROOT_FILES = [".gitignore", "AGENTS.md", "CODEX_SETUP_PROMPT.md", "README.md", "START_HERE.md",
              "START-MAC.command", "START-WINDOWS.bat", "package.json", "package-lock.json",
              "index.html", "tsconfig.json", "vite.config.ts"]
ALLOWED_DIRS = {"docs": {".md"}, "templates": {".md"}, "scripts": {".mjs"},
                "electron": {".cjs"}, "src": {".ts", ".tsx", ".css"}}
EXTRA_FILES = ["course/prompts.json", "models/README.md", "examples/revenue.csv",
               "public/assets/noriko-character-closed.png", "public/assets/noriko-character-open.png"]

def kit_files():
    paths = [KIT / name for name in ROOT_FILES + EXTRA_FILES]
    for folder, suffixes in ALLOWED_DIRS.items():
        for item in (KIT / folder).rglob("*"):
            if item.is_symlink():
                raise RuntimeError(f"Symlink forbidden: {item.relative_to(KIT)}")
            if item.is_dir():
                continue
            if item.suffix not in suffixes or item.name.startswith("."):
                raise RuntimeError(f"Review unexpected source: {item.relative_to(KIT)}")
            paths.append(item)
    return sorted(paths)

def guide_files():
    paths = []
    for item in GUIDE.rglob("*"):
        if item.is_symlink():
            raise RuntimeError("Guide symlink forbidden")
        if item.is_dir():
            continue
        if item.suffix != ".md" and item.relative_to(GUIDE).as_posix() != "course/prompts.json":
            raise RuntimeError(f"Review unexpected guide asset: {item.relative_to(GUIDE)}")
        paths.append(item)
    return sorted(paths)

def bundle(base, paths, filename):
    records = []
    with zipfile.ZipFile(OUT / filename, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as archive:
        for item in paths:
            if not item.is_file() or item.is_symlink():
                raise RuntimeError(f"Not a regular source file: {item.name}")
            relative = item.relative_to(base).as_posix()
            data = item.read_bytes()
            if item.suffix not in {".png"}:
                content = data.decode("utf-8-sig")
                if re.search(r"sk-(?:proj-)?[A-Za-z0-9_-]{30,}|AIza[A-Za-z0-9_-]{30,}|-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----", content):
                    raise RuntimeError(f"Sensitive pattern in {relative}; review without printing values")
            info = zipfile.ZipInfo(base.name + "/" + relative, (2026, 9, 19, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.create_system = 3
            info.external_attr = (0o100755 if relative.endswith(".command") else 0o100644) << 16
            archive.writestr(info, data)
            records.append({"path": relative, "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest()})
    with zipfile.ZipFile(OUT / filename) as archive:
        if archive.testzip() is not None:
            raise RuntimeError("ZIP CRC verification failed")
    return records

version = json.loads((KIT / "package.json").read_text())["version"]
inventory = bundle(KIT, kit_files(), "AI-NORIKO-Starter-Kit.zip")
guide_inventory = bundle(GUIDE, guide_files(), "AI-NORIKO-Learning-Guide.zip")
kit_bytes = (OUT / "AI-NORIKO-Starter-Kit.zip").read_bytes()
kit_hash = hashlib.sha256(kit_bytes).hexdigest()
release = Path("releases") / version / kit_hash[:12] / "AI-NORIKO-Starter-Kit.zip"
release_path = OUT / release
release_path.parent.mkdir(parents=True, exist_ok=True)
if release_path.exists() and release_path.read_bytes() != kit_bytes:
    raise RuntimeError("Refusing to change an immutable release")
if not release_path.exists():
    release_path.write_bytes(kit_bytes)
(OUT / "kit-files.json").write_text(json.dumps({"version": version, "files": inventory}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
(OUT / "release.json").write_text(json.dumps({"version": version, "sha256": kit_hash, "starterKit": "downloads/" + release.as_posix()}, indent=2) + "\n", encoding="utf-8")
print(f"Packaged v{version}: kit {len(inventory)} files; guide {len(guide_inventory)} files. CRC, allowlist and sensitive-pattern checks passed.")
