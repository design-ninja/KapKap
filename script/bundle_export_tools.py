#!/usr/bin/env python3
"""Copy the installed ARM FFmpeg and its non-system dylibs into the app bundle."""
import pathlib
import shutil
import subprocess
import sys

bundle = pathlib.Path(sys.argv[1]).resolve()
ffmpeg = shutil.which("ffmpeg")
if not ffmpeg:
    raise SystemExit("ARM FFmpeg is required to build export support. Install it with Homebrew: brew install ffmpeg")
resources = bundle / "Contents/Resources"
frameworks = bundle / "Contents/Frameworks"
resources.mkdir(parents=True, exist_ok=True)
frameworks.mkdir(parents=True, exist_ok=True)
copied = {}


def dependencies(path):
    result = subprocess.check_output(["otool", "-L", str(path)], text=True)
    return [line.strip().split(" (compatibility")[0] for line in result.splitlines()[1:]]


def install(source, destination):
    source = source.resolve()
    if source in copied:
        return copied[source]
    subprocess.run(["lipo", "-verify_arch", "arm64", str(source)], check=True)
    shutil.copy2(source, destination)
    destination.chmod(0o755)
    copied[source] = destination
    changes = []
    for dependency in dependencies(source):
        if dependency.startswith(("/usr/lib/", "/System/Library/")):
            continue
        if not dependency.startswith("/"):
            raise SystemExit(f"Unresolved non-system dependency: {dependency} in {source}")
        original = pathlib.Path(dependency).resolve()
        if original == source:
            continue
        target = frameworks / original.name
        if target.exists() and original not in copied:
            raise SystemExit(f"Library name collision: {target}")
        install(original, target)
        relative = "@executable_path/../Frameworks/" + target.name
        changes.extend(["-change", dependency, relative])
    if destination.parent == frameworks:
        changes.extend(["-id", "@executable_path/../Frameworks/" + destination.name])
    if changes:
        subprocess.run(["install_name_tool", *changes, str(destination)], check=True, stdout=subprocess.DEVNULL)
    subprocess.run(["codesign", "--force", "--sign", "-", str(destination)], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    return destination


install(pathlib.Path(ffmpeg), resources / "ffmpeg")
print(f"Bundled ARM FFmpeg and {len(copied) - 1} libraries")
