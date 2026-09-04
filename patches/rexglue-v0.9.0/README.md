# ReXGlue v0.9.0 patches

These patches are maintained against ReXGlue SDK v0.9.0, commit
`3eb9b511b4140d2769e27be63eae57d41bfa2afa`.

| Patch | Purpose |
| --- | --- |
| `0001-preserve-callback-nonvolatile-registers.patch` | Preserves the PPC ABI across reentrant host-to-guest callbacks. |
| `0002-unlink-posix-shared-memory-eagerly.patch` | Prevents abnormal exits from leaving multi-gigabyte objects in `/dev/shm`. |
| `0003-complete-local-content-operations-inline.patch` | Makes host-local content mounting observable immediately through an overlapped result while retaining `X_ERROR_IO_PENDING`. |
| `0004-honor-vsync-and-stabilize-frame-metrics.patch` | Makes Vulkan presentation honor `vsync` and records per-swap frame timing. |
| `0005-enable-release-frame-telemetry.patch` | Enables CSV performance counters in Release builds and initializes logging in the module that emits frames. |
| `0006-add-deterministic-input-replay.patch` | Replays timestamped Linux controller events through the SDL input driver without `uinput`. |
| `0007-back-off-contended-posix-multi-waits.patch` | Prevents contended POSIX multi-object waits from consuming an entire host CPU core. |
| `0008-speed-up-linux-memory-map-queries.patch` | Removes formatted parsing from the Linux access-violation and write-watch hot path. |
| `0009-add-adaptive-vsync-mode.patch` | Adds opt-in FIFO-relaxed presentation while retaining synchronized guest timing. |
| `0010-stream-linux-memory-maps.patch` | Replaces C++ stream traversal in Linux protection queries with allocation-free buffered reads. |
| `0011-bypass-linux-write-fault-map-query.patch` | Uses guest heap metadata directly for write-watch faults instead of querying `/proc/self/maps`. |
| `0012-honor-host-file-delete-on-close.patch` | Deletes writable host files marked through `NtSetInformationFile` when their guest handle closes. |
| `0013-fast-path-cleared-write-watch-faults.patch` | Resumes queued write-watch faults from guest metadata after another thread has already cleared the watch. |
| `0014-add-low-jitter-vsync-worker.patch` | Adds an opt-in runnable VSync worker mode to reduce guest timer wakeup jitter. |
| `0015-update-gpu-read-pointer-incrementally.patch` | Writes back command-ring progress at the configured interval so large GPU batches do not stall guest submission until the entire batch finishes. |
| `0016-honor-configured-function-chunks.patch` | Prevents configured chunks from becoming independent entry points so their parent function can own internal branches through those ranges. |
| `0017-decouple-guest-vblank-from-host-vsync.patch` | Adds an opt-in mode that keeps guest VBlank at the configured refresh rate while host presentation VSync is disabled. |
| `0018-add-frame-stage-timing-counters.patch` | Adds per-swap timing for guest-output generation, Vulkan synchronization, swapchain acquisition, command recording, submission, and presentation. |

Apply the full series with `scripts/apply-rexglue-patches.sh`. The script checks
the ReXGlue commit and is safe to run again after all patches are applied.
