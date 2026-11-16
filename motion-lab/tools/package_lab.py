#!/usr/bin/env python3
"""Package an existing motion-lab export and its complete editable source."""

from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import struct
import zipfile
from pathlib import Path


def digest(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def archive(paths: list[tuple[Path, str]], destination: Path) -> dict:
    destination.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(destination, "w", zipfile.ZIP_DEFLATED, compresslevel=6) as out:
        for source, name in sorted(paths, key=lambda item: item[1]):
            out.write(source, name)
    with zipfile.ZipFile(destination) as check:
        corrupt = check.testzip()
        if corrupt:
            raise RuntimeError(f"Archive verification failed: {corrupt}")
    return {"path": str(destination), "bytes": destination.stat().st_size,
            "sha256": digest(destination), "files": len(paths)}


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--project", type=Path, default=Path(__file__).resolve().parents[1])
    parser.add_argument("--exe", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--version", default="v0.5")
    args = parser.parse_args()
    project, exe, output = args.project.resolve(), args.exe.resolve(), args.output.resolve()
    if not (project / "project.godot").is_file():
        raise SystemExit("project.godot is missing")
    if not exe.is_file() or exe.read_bytes()[:2] != b"MZ":
        raise SystemExit("A valid exported Windows executable is required")
    pe = exe.read_bytes()
    pe_offset = struct.unpack_from("<I", pe, 0x3C)[0]
    if pe[pe_offset:pe_offset+4] != b"PE\0\0":
        raise SystemExit("Missing PE signature")
    if struct.unpack_from("<H", pe, pe_offset+4)[0] != 0x8664:
        raise SystemExit("Export is not x86_64")
    output.mkdir(parents=True, exist_ok=True)

    root_name = f"Black_Crusade_Motion_Lab_{args.version}"
    runtime = [(exe, f"{root_name}/{exe.name}")]
    for suffix in (".pck", ".console.exe"):
        companion = exe.with_suffix(suffix)
        if companion.is_file():
            runtime.append((companion, f"{root_name}/{companion.name}"))
    for name in ("icudt_godot.dat",):
        companion = exe.parent / name
        if companion.is_file():
            runtime.append((companion, f"{root_name}/{name}"))
    for rel in ("README.txt", "README.md", "docs/QA.txt", "docs/ASSETS.txt", "docs/CONTROLS.txt"):
        path = project / rel
        if path.is_file():
            runtime.append((path, f"{root_name}/{rel}"))
    license_dir = project / "licenses"
    if license_dir.exists():
        for path in license_dir.rglob("*"):
            if path.is_file():
                runtime.append((path, f"{root_name}/{path.relative_to(project).as_posix()}"))

    excluded = {".godot", ".git", "build", "dist", "__pycache__", "node_modules", "deliverables"}
    source = []
    for path in project.rglob("*"):
        rel = path.relative_to(project)
        if not path.is_file() or any(part in excluded for part in rel.parts):
            continue
        if path.suffix in {".log", ".tmp", ".pyc"} or output in path.parents:
            continue
        source.append((path, f"{root_name}_Source/{rel.as_posix()}"))
    results = [
        archive(runtime, output / f"{root_name}_Windows.zip"),
        archive(source, output / f"{root_name}_Source.zip"),
    ]
    manifest = {"version": args.version, "export": {"file": exe.name, "sha256": digest(exe)},
                "archives": results,
                "verification": "ZIP CRC and PE32+ x86_64 signature verified. See docs/QA.txt for actual Linux/headless tests; Windows execution not performed."}
    (output / f"{root_name}_manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(manifest, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
