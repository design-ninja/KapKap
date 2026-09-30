#!/usr/bin/env python3
"""Put KapKap's own FFmpeg build (script/build_ffmpeg.sh) and its license texts into the app bundle."""
import pathlib
import shutil
import subprocess
import sys

MINIMUM_MACOS = "15.0"
bundle = pathlib.Path(sys.argv[1]).resolve()
root = pathlib.Path(__file__).resolve().parent.parent
build = subprocess.run([str(root / "script/build_ffmpeg.sh")], check=True, stdout=subprocess.PIPE, text=True)
ffmpeg = pathlib.Path(build.stdout.strip().splitlines()[-1])
resources = bundle / "Contents/Resources"
frameworks = bundle / "Contents/Frameworks"
resources.mkdir(parents=True, exist_ok=True)

# Earlier builds bundled Homebrew's FFmpeg libraries; the static executable needs none of them.
for stale in frameworks.glob("*.dylib"):
    stale.unlink()

subprocess.run(["lipo", "-verify_arch", "arm64", str(ffmpeg)], check=True)
linked = subprocess.check_output(["otool", "-L", str(ffmpeg)], text=True).splitlines()[1:]
foreign = [line.strip() for line in linked if not line.strip().startswith(("/usr/lib/", "/System/Library/"))]
if foreign:
    raise SystemExit(f"FFmpeg links libraries outside macOS: {foreign}")
build_version = subprocess.check_output(["vtool", "-show-build", str(ffmpeg)], text=True)
if f"minos {MINIMUM_MACOS}" not in build_version:
    raise SystemExit(f"FFmpeg must run on macOS {MINIMUM_MACOS}:\n{build_version}")

target = resources / "ffmpeg"
shutil.copy2(ffmpeg, target)
target.chmod(0o755)
# Local symbols only help debugging FFmpeg itself.
subprocess.run(["strip", "-x", str(target)], check=True, stderr=subprocess.DEVNULL)
subprocess.run(["codesign", "--force", "--sign", "-", str(target)], check=True,
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

licenses = resources / "Licenses/FFmpeg"
shutil.rmtree(licenses, ignore_errors=True)
shutil.copytree(ffmpeg.parent.parent / "licenses", licenses)
print(f"Bundled FFmpeg ({target.stat().st_size / 1_000_000:.1f} MB) built from source for macOS {MINIMUM_MACOS}")
