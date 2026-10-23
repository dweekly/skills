#!/usr/bin/env python3
"""Capture integrated simulator screens plus metadata without changing app state."""

import argparse
import datetime
import json
import os
from pathlib import Path
import re
import subprocess
import sys


def run(command):
    return subprocess.run(command, capture_output=True, text=True, timeout=45)


def checked(command):
    result = run(command)
    if result.returncode:
        raise RuntimeError(f"{' '.join(command)} failed: {result.stderr.strip()}")
    return result.stdout


def integrated_displays(enumeration):
    # Xcode 27.1's Connected Screens format. Older formats require an explicit
    # --display selector; do not confuse port UUIDs with connected screen IDs.
    blocks = re.split(r"(?m)^\s*Screen ID:\s*", enumeration)[1:]
    screens = []
    for block in blocks:
        lines = block.splitlines()
        screen_id = lines[0].strip()
        if re.search(r"(?m)^\s*Screen Type:\s*Integrated\s*$", block):
            if screen_id.isdigit() and screen_id not in screens:
                screens.append(screen_id)
    return screens


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--udid", required=True, help="Exact booted simulator UUID")
    parser.add_argument("--output", required=True, type=Path, help="New output directory")
    parser.add_argument("--display", action="append", help="Explicit display selector; repeat to capture several")
    args = parser.parse_args()
    if not re.fullmatch(r"[0-9a-fA-F]{8}(?:-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}", args.udid):
        parser.error("--udid must be an exact UUID, not a name or 'booted'")

    devices = json.loads(checked(["xcrun", "simctl", "list", "devices", "--json"]))
    matches = [(runtime, device) for runtime, group in devices["devices"].items()
               for device in group if device["udid"].lower() == args.udid.lower()]
    if len(matches) != 1 or matches[0][1]["state"] != "Booted":
        parser.error("The selected simulator must exist and already be booted")
    runtime, device = matches[0]
    enumeration = checked(["xcrun", "simctl", "io", args.udid, "enumerate"])
    displays = args.display or integrated_displays(enumeration)
    if not displays:
        parser.error("No Integrated screens found in this toolchain's enumeration; inspect simctl io help and supply --display")
    version = checked(["xcodebuild", "-version"]).strip()
    # Refuse overwrites so checkpoints and older failure evidence survive.
    args.output.mkdir(parents=True, exist_ok=False)
    (args.output / "displays.txt").write_text(enumeration)
    metadata = {
        "captured_at_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "developer_dir": os.environ.get("DEVELOPER_DIR"),
        "xcode": version,
        "runtime": runtime,
        "device": {key: device.get(key) for key in ("name", "udid", "state", "deviceTypeIdentifier")},
        "selection": "explicit" if args.display else "enumerated Integrated screens",
        "screens": [],
    }
    failed = False
    for index, display in enumerate(displays):
        filename = f"screen-{index}.png"
        command = ["xcrun", "simctl", "io", args.udid, "screenshot", f"--display={display}", str(args.output / filename)]
        try:
            result = run(command)
            entry = {"display": display, "file": filename, "exit_code": result.returncode,
                     "stdout": result.stdout, "stderr": result.stderr}
            if result.returncode or not (args.output / filename).is_file():
                failed = True
        except subprocess.TimeoutExpired:
            entry = {"display": display, "file": filename, "error": "capture timed out after 45 seconds"}
            failed = True
        metadata["screens"].append(entry)
        (args.output / "metadata.json").write_text(json.dumps(metadata, indent=2) + "\n")
    print(f"{'Capture incomplete' if failed else 'Captured'}: {args.output}")
    print("Inspect the images to identify the active display; a black inactive screen is possible.")
    return 1 if failed else 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, RuntimeError, subprocess.TimeoutExpired, ValueError) as error:
        print(f"Capture failed: {error}", file=sys.stderr)
        sys.exit(1)
