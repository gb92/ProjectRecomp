#!/usr/bin/env python3

import argparse
import json
import select
import time
from pathlib import Path

from evdev import InputDevice, ecodes


def serialize_capabilities(device):
    capabilities = {"keys": [], "absolute_axes": {}}
    for event_type, entries in device.capabilities(absinfo=True).items():
        if event_type == ecodes.EV_KEY:
            capabilities["keys"] = entries
        elif event_type == ecodes.EV_ABS:
            for code, info in entries:
                capabilities["absolute_axes"][str(code)] = {
                    "minimum": info.min,
                    "maximum": info.max,
                    "fuzz": info.fuzz,
                    "flat": info.flat,
                    "resolution": info.resolution,
                }
    return capabilities


def main():
    parser = argparse.ArgumentParser(description="Record a Linux evdev controller trace")
    parser.add_argument("device", help="Controller event device")
    parser.add_argument("output", type=Path, help="Output JSON file")
    parser.add_argument("--duration", type=float, default=90.0, help="Recording duration in seconds")
    args = parser.parse_args()

    device = InputDevice(args.device)
    trace = {
        "format_version": 1,
        "device": {
            "name": device.name,
            "vendor": device.info.vendor,
            "product": device.info.product,
            "version": device.info.version,
            "capabilities": serialize_capabilities(device),
        },
        "events": [],
    }

    args.output.parent.mkdir(parents=True, exist_ok=True)
    start = time.monotonic_ns()
    deadline = start + int(args.duration * 1_000_000_000)
    next_status = start
    print(f"Recording {device.name} for {args.duration:.0f} seconds...")

    try:
        while True:
            now = time.monotonic_ns()
            if now >= deadline:
                break
            if now >= next_status:
                remaining = max(0.0, (deadline - now) / 1_000_000_000)
                print(f"{remaining:5.0f} seconds remaining", flush=True)
                next_status = now + 10_000_000_000

            timeout = min(1.0, (deadline - now) / 1_000_000_000)
            readable, _, _ = select.select([device.fd], [], [], timeout)
            if not readable:
                continue
            for event in device.read():
                if event.type not in (ecodes.EV_SYN, ecodes.EV_KEY, ecodes.EV_ABS):
                    continue
                trace["events"].append(
                    [time.monotonic_ns() - start, event.type, event.code, event.value]
                )
    except KeyboardInterrupt:
        print("Recording stopped")

    args.output.write_text(json.dumps(trace, separators=(",", ":")) + "\n")
    print(f"Saved {len(trace['events'])} events to {args.output}")


if __name__ == "__main__":
    main()
