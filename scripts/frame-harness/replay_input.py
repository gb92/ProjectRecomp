#!/usr/bin/env python3

import argparse
import json
import os
import signal
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def normalize_absolute_value(code, value, capabilities):
    if code in (16, 17):
        return max(-1, min(1, value))
    if code not in (0, 1, 2, 3, 4, 5):
        return value

    axis = capabilities.get(str(code))
    if not axis:
        raise RuntimeError(f"Trace is missing capabilities for absolute axis {code}")
    minimum = axis["minimum"]
    maximum = axis["maximum"]
    if maximum <= minimum:
        raise RuntimeError(f"Trace has an invalid range for absolute axis {code}")

    value = max(minimum, min(maximum, value))
    if code in (2, 5):
        return round((value - minimum) * 255 / (maximum - minimum))
    return round((value - minimum) * 65535 / (maximum - minimum)) - 32768


def main():
    parser = argparse.ArgumentParser(
        description="Launch a command and replay a recorded controller trace"
    )
    parser.add_argument("trace", type=Path, help="Recorded controller JSON")
    parser.add_argument("--tail", type=float, default=5.0, help="Seconds to wait after replay")
    parser.add_argument("--perf-csv", type=Path, help="Write ReXGlue frame counters here")
    try:
        separator = sys.argv.index("--")
    except ValueError:
        parser.error("a command is required after --")
    args = parser.parse_args(sys.argv[1:separator])
    command = sys.argv[separator + 1 :]
    if not command:
        parser.error("a command is required after --")

    trace = json.loads(args.trace.read_text())
    if trace.get("format_version") != 1:
        raise RuntimeError("Unsupported trace format")
    events = trace.get("events")
    if not isinstance(events, list) or not events:
        raise RuntimeError("Trace contains no controller events")
    absolute_axes = trace.get("device", {}).get("capabilities", {}).get(
        "absolute_axes", {}
    )

    with tempfile.NamedTemporaryFile(
        mode="w", prefix="rexglue-input-", suffix=".txt", delete=False
    ) as output:
        runtime_trace = Path(output.name)
        for timestamp, event_type, code, value in events:
            if event_type == 3:
                value = normalize_absolute_value(code, value, absolute_axes)
            output.write(f"{timestamp} {event_type} {code} {value}\n")

    environment = os.environ.copy()
    environment["REXGLUE_INPUT_REPLAY"] = str(runtime_trace)
    if args.perf_csv:
        environment["REXGLUE_PERF_LOG_CSV"] = str(args.perf_csv.resolve())
    popen_options = {}
    if os.name == "nt":
        popen_options["creationflags"] = subprocess.CREATE_NEW_PROCESS_GROUP
    else:
        popen_options["start_new_session"] = True
    process = subprocess.Popen(command, env=environment, **popen_options)
    duration = (events[-1][0] / 1_000_000_000) + args.tail
    print(f"Started PID {process.pid}; replaying {len(events)} events")

    try:
        deadline = time.monotonic() + duration
        while process.poll() is None and time.monotonic() < deadline:
            time.sleep(0.25)
        if process.poll() is not None:
            raise RuntimeError(f"Command exited early with status {process.returncode}")
    finally:
        if process.poll() is None:
            if os.name == "nt":
                process.send_signal(signal.CTRL_BREAK_EVENT)
            else:
                os.killpg(process.pid, signal.SIGINT)
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                if os.name == "nt":
                    process.kill()
                    process.wait()
                else:
                    os.killpg(process.pid, signal.SIGTERM)
                    try:
                        process.wait(timeout=2)
                    except subprocess.TimeoutExpired:
                        os.killpg(process.pid, signal.SIGKILL)
                        process.wait()
            if os.name != "nt":
                deadline = time.monotonic() + 2
                while time.monotonic() < deadline:
                    try:
                        os.killpg(process.pid, 0)
                    except ProcessLookupError:
                        break
                    time.sleep(0.1)
                else:
                    os.killpg(process.pid, signal.SIGKILL)
        runtime_trace.unlink(missing_ok=True)
    print("Replay completed")


if __name__ == "__main__":
    main()
