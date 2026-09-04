# Xbox 360 Static Recompilation Guide

A practical walkthrough of using [XenonRecomp](https://github.com/hedge-dev/XenonRecomp) and [XenosRecomp](https://github.com/hedge-dev/XenosRecomp) to statically recompile an Xbox 360 game's CPU code and GPU shaders for PC. This guide documents the steps taken while recompiling Tony Hawk's Project 8 and generalizes them for any Xbox 360 title.

> **What is static recompilation?** Unlike emulation (which interprets instructions at runtime), static recompilation converts the entire game binary ahead of time into equivalent C++ source code that can be compiled natively for x86-64 or ARM64. The result is dramatically faster execution, but requires a custom runtime to provide the OS/hardware services the game expects.

---

## Table of Contents

1. [Prerequisites](#1-prerequisites)
2. [Project Setup](#2-project-setup)
3. [Building the Recompiler Tools](#3-building-the-recompiler-tools)
4. [Obtaining Game Files](#4-obtaining-game-files)
5. [Analyzing the XEX](#5-analyzing-the-xex)
6. [CPU Recompilation (XenonRecomp)](#6-cpu-recompilation-xenonrecomp)
7. [Shader Recompilation (XenosRecomp)](#7-shader-recompilation-xenosrecomp)
8. [What Comes Next: The Runtime](#8-what-comes-next-the-runtime)
9. [Troubleshooting & Game-Specific Issues](#9-troubleshooting--game-specific-issues)
10. [Resources](#10-resources)

---

## 1. Prerequisites

### Required Tools

| Tool | Version | Purpose |
|------|---------|---------|
| **CMake** | ≥ 3.20 | Build system for both recompilers |
| **Clang** | ≥ 18 | C/C++ compiler (only tested/supported compiler) |
| **Git** | Any | Clone repos with submodules |
| **Python 3** | Any | Helper scripts for binary analysis |

On Windows, use the `clang-cl` toolset through Visual Studio 2022's CMake integration. On macOS/Linux, install Clang directly.

### Recommended Tools

| Tool | Purpose |
|------|---------|
| **Ghidra** (with Xbox 360 XEX loader) or **IDA Pro** | Disassembly and deeper analysis |
| **A hex editor** (HxD, ImHex) | Manual byte pattern inspection |
| **extract-xiso** or **xdvdfs** | Extracting Xbox 360 disc images |

### What You Need From Your Game

- **`default.xex`** — the main Xbox 360 executable
- **`default.xexp`** (optional) — title update patch file
- **Disc image or extracted game data** — for shader binaries and other assets

---

## 2. Project Setup

Create a directory structure to keep things organized:

```
your-game-recomp/
├── config/           # TOML config files for the recompilers
├── ppc/              # XenonRecomp C++ output (generated)
├── private/          # Your game files (XEX, ISO, etc.)
├── shaders/          # Shader extraction/recompilation workspace
├── tools/            # Recompiler tools (cloned repos)
│   ├── XenonRecomp/
│   ├── XenosRecomp/
│   └── xex_dump/     # Custom helper tool (see below)
└── docs/
```

```bash
mkdir -p your-game-recomp/{config,ppc,private,shaders,tools,docs}
```

---

## 3. Building the Recompiler Tools

### XenonRecomp (CPU: PPC → C++)

```bash
cd your-game-recomp/tools
git clone --recursive https://github.com/hedge-dev/XenonRecomp.git
cd XenonRecomp
mkdir build && cd build
cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

This produces two executables:
- **`XenonAnalyse`** — scans an XEX for jump tables, outputs a TOML file
- **`XenonRecomp`** — converts XEX → C++ source files

### XenosRecomp (GPU: Xenos shaders → HLSL)

```bash
cd your-game-recomp/tools
git clone --recursive https://github.com/hedge-dev/XenosRecomp.git
cd XenosRecomp
mkdir build && cd build
cmake .. -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ -DCMAKE_BUILD_TYPE=Release
cmake --build . --config Release
```

Produces **`XenosRecomp`** — converts Xbox 360 shader binaries → HLSL.

### xex_dump (Helper: decompress XEX + find register functions)

XEX files are typically compressed and/or encrypted. The recompiler tools handle this internally, but to search the decompressed code for byte patterns you need a helper tool.

Build one using XenonRecomp's `XenonUtils` library. A minimal implementation:

```cpp
// main.cpp — loads and decompresses an XEX, then searches for
// register save/restore function byte patterns.
#include <cstdio>
#include <cstring>
#include <fstream>
#include <vector>
#include "image.h"
#include "xex.h"

int main(int argc, char* argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: xex_dump <input.xex> <output.bin>\n");
        return 1;
    }

    std::ifstream in(argv[1], std::ios::binary | std::ios::ate);
    size_t fileSize = in.tellg();
    in.seekg(0);
    std::vector<uint8_t> fileData(fileSize);
    in.read(reinterpret_cast<char*>(fileData.data()), fileSize);
    in.close();

    Image image = Xex2LoadImage(fileData.data(), fileSize);

    printf("Base address: 0x%08zX\n", image.base);
    printf("Entry point:  0x%08zX\n", image.entry_point);
    printf("Image size:   0x%X (%u bytes)\n", image.size, image.size);

    // Dump decompressed image
    std::ofstream out(argv[2], std::ios::binary);
    out.write(reinterpret_cast<const char*>(image.data.get()), image.size);

    // Search for register save/restore patterns
    struct Pattern {
        const char* name;
        const uint8_t* bytes;
        size_t len;
    };
    const uint8_t restgprlr[] = {0xe9, 0xc1, 0xff, 0x68};
    const uint8_t savegprlr[] = {0xf9, 0xc1, 0xff, 0x68};
    const uint8_t restfpr[]   = {0xc9, 0xcc, 0xff, 0x70};
    const uint8_t savefpr[]   = {0xd9, 0xcc, 0xff, 0x70};
    const uint8_t restvmx14[] = {0x39, 0x60, 0xfe, 0xe0, 0x7d, 0xcb, 0x60, 0xce};
    const uint8_t savevmx14[] = {0x39, 0x60, 0xfe, 0xe0, 0x7d, 0xcb, 0x61, 0xce};
    const uint8_t restvmx64[] = {0x39, 0x60, 0xfc, 0x00, 0x10, 0x0b, 0x60, 0xcb};
    const uint8_t savevmx64[] = {0x39, 0x60, 0xfc, 0x00, 0x10, 0x0b, 0x61, 0xcb};

    Pattern patterns[] = {
        {"restgprlr_14_address", restgprlr, 4},
        {"savegprlr_14_address", savegprlr, 4},
        {"restfpr_14_address",   restfpr,   4},
        {"savefpr_14_address",   savefpr,   4},
        {"restvmx_14_address",   restvmx14, 8},
        {"savevmx_14_address",   savevmx14, 8},
        {"restvmx_64_address",   restvmx64, 8},
        {"savevmx_64_address",   savevmx64, 8},
    };

    for (const auto& pat : patterns) {
        for (size_t i = 0; i <= image.size - pat.len; i++) {
            if (memcmp(image.data.get() + i, pat.bytes, pat.len) == 0) {
                uint32_t va = (uint32_t)image.base + (uint32_t)i;
                printf("%s = 0x%08X\n", pat.name, va);
                break;
            }
        }
    }
    return 0;
}
```

Link it against XenonUtils sources and the required thirdparty libraries (libmspack, tiny-AES-c, TinySHA1, xxHash). See the `CMakeLists.txt` in this project's `tools/xex_dump/` for the complete build configuration.

---

## 4. Obtaining Game Files

### From a Retail Disc

1. **Dump the disc** using an Xbox 360 with RGH/JTAG or compatible disc drive + PC software. You'll get an ISO image.
2. **Extract the ISO** using `extract-xiso` or `xdvdfs`:
   ```bash
   # extract-xiso (supports both OG Xbox and Xbox 360)
   extract-xiso -d output_folder game.iso
   
   # xdvdfs (Rust-based alternative)
   cargo install xdvdfs-cli
   xdvdfs unpack game.iso output_folder
   ```
3. **Locate key files:**
   - `default.xex` — the main executable (always at the ISO root)
   - `default.xexp` — title update patch (if applicable)
   - Game data directories — vary by game engine

### Title Updates

If you have a title update `.xexp` file, XenonRecomp can apply it automatically. Place it alongside `default.xex` and reference it in your TOML config. XenonRecomp will produce a `patched_file_path` output that combines both.

---

## 5. Analyzing the XEX

This is where you extract the information XenonRecomp needs to do its job. There are 8 register save/restore function addresses and potentially `setjmp`/`longjmp` addresses to find.

### Step 1: Run xex_dump

```bash
./xex_dump private/default.xex private/default_decompressed.bin
```

This will:
- Decompress and decrypt the XEX
- Print the base address, entry point, and image size
- Search for all 8 register save/restore function byte patterns
- Output the virtual addresses ready for your TOML config

**Example output (from Tony Hawk's Project 8):**
```
Base address: 0x82000000
Entry point:  0x823AC158
Image size:   0xA80000 (11010048 bytes)

restgprlr_14_address = 0x8262BC50
savegprlr_14_address = 0x8262BC00
restfpr_14_address = 0x8262C7CC
savefpr_14_address = 0x8262C780
restvmx_14_address = 0x82631838
savevmx_14_address = 0x826315A0
restvmx_64_address = 0x826318CC
savevmx_64_address = 0x82631634
```

> **What are these functions?** Xbox 360 executables use standardized register save/restore routines inherited from the PowerPC ABI. Every function that uses non-volatile registers calls these to save them on entry and restore on exit. The recompiler needs their addresses to generate correct code for these special routines, which work like switch-case fallthroughs.

### Step 2: Find setjmp/longjmp (optional)

If the game uses `setjmp`/`longjmp` (for non-local jumps or error recovery), you need their addresses too. Look for references to `RtlUnwind` in a disassembler — `longjmp` typically calls it, and `setjmp` is nearby.

If unsure, omit them from the config — the recompiler will still work, and you'll discover at runtime if they're needed.

### Step 3: Run XenonAnalyse (jump table detection)

```bash
./XenonAnalyse private/default.xex config/switch_tables.toml
```

This scans the executable for jump table patterns and outputs a TOML file that XenonRecomp uses to convert them into proper `switch` statements.

**Important:** XenonAnalyse's detection logic was written for Sonic Unleashed. Different games (especially those compiled with different versions of the Xbox 360 compiler) may have different jump table patterns. You may see:
- **Missing jump tables** — warnings like "Found a switch jump table with no switch table entry present"
- **Boundary errors** — "Switch case is trying to jump outside function"

These indicate places where you'll need to either modify XenonAnalyse or manually add entries to your TOML config.

**THP8 results:** XenonAnalyse found thousands of jump tables successfully (13,800+ lines of TOML), though ~25 tables were missed and ~100 had boundary issues — typical for a first pass on a new game.

### Understanding the Byte Patterns

Here's what each pattern represents in PowerPC assembly:

| TOML Key | PPC Instruction | Byte Pattern | Purpose |
|----------|----------------|--------------|---------|
| `restgprlr_14_address` | `ld r14, -0x98(r1)` | `e9 c1 ff 68` | Restore general-purpose registers + link register |
| `savegprlr_14_address` | `std r14, -0x98(r1)` | `f9 c1 ff 68` | Save general-purpose registers + link register |
| `restfpr_14_address` | `lfd f14, -0x90(r12)` | `c9 cc ff 70` | Restore floating-point registers |
| `savefpr_14_address` | `stfd f14, -0x90(r12)` | `d9 cc ff 70` | Save floating-point registers |
| `restvmx_14_address` | `li r11, -0x120; lvx v14, r11, r12` | `39 60 fe e0 7d cb 60 ce` | Restore VMX (SIMD) registers 14–63 |
| `savevmx_14_address` | `li r11, -0x120; stvx v14, r11, r12` | `39 60 fe e0 7d cb 61 ce` | Save VMX registers 14–63 |
| `restvmx_64_address` | `li r11, -0x400; lvx128 v64, r11, r12` | `39 60 fc 00 10 0b 60 cb` | Restore VMX128 registers 64+ |
| `savevmx_64_address` | `li r11, -0x400; stvx128 v64, r11, r12` | `39 60 fc 00 10 0b 61 cb` | Save VMX128 registers 64+ |

These patterns are consistent across Xbox 360 titles because they come from the standard runtime library linked into every executable.

---

## 6. CPU Recompilation (XenonRecomp)

### Step 1: Create the TOML Config

Create a TOML file (e.g., `config/YourGame.toml`) with the information gathered in the analysis step:

```toml
[main]
file_path = "../private/default.xex"
# patch_file_path = "../private/default.xexp"        # Uncomment if you have a title update
# patched_file_path = "../private/default_patched.xex"  # Auto-generated by XenonRecomp
out_directory_path = "../ppc"
switch_table_file_path = "switch_tables.toml"

# Start with ALL optimizations OFF
skip_lr = false
skip_msr = false
ctr_as_local = false
xer_as_local = false
reserved_as_local = false
cr_as_local = false
non_argument_as_local = false
non_volatile_as_local = false

# Paste the addresses from xex_dump output
restgprlr_14_address = 0x????????
savegprlr_14_address = 0x????????
restfpr_14_address = 0x????????
savefpr_14_address = 0x????????
restvmx_14_address = 0x????????
savevmx_14_address = 0x????????
restvmx_64_address = 0x????????
savevmx_64_address = 0x????????

# Uncomment if the game uses setjmp/longjmp
# longjmp_address = 0x????????
# setjmp_address = 0x????????
```

**Optimization notes:** Keep all optimizations off until you have a working recompilation. Once things are running, you can enable them one at a time (see [XenonRecomp README](https://github.com/hedge-dev/XenonRecomp#optimizations) for details). The `non_volatile_as_local` optimization alone can reduce executable size by ~20 MB and improve frame times significantly.

### Step 2: Create the Output Directory and Run

```bash
mkdir -p ppc
./tools/XenonRecomp/build/XenonRecomp/XenonRecomp config/YourGame.toml tools/XenonRecomp/XenonUtils/ppc_context.h
```

### Step 3: Examine the Output

XenonRecomp generates:

| File | Purpose |
|------|---------|
| `ppc_config.h` | Image base, code base, size macros |
| `ppc_context.h` | `PPCContext` struct (all CPU registers, CR, XER, etc.) |
| `ppc_recomp_shared.h` | Shared macros and declarations for all recompiled functions |
| `ppc_func_mapping.cpp` | Maps original addresses → recompiled function pointers |
| `ppc_recomp.N.cpp` | The actual recompiled functions (many files, split for parallel compilation) |

**What the recompiled code looks like:**

```cpp
PPC_FUNC_IMPL(__imp__sub_82090020) {
    PPC_FUNC_PROLOGUE();
    // lis r11,-32105
    ctx.r11.s64 = -2104033280;
    // mr r4,r3
    ctx.r4.u64 = ctx.r3.u64;
    // lwz r3,5032(r11)
    ctx.r3.u64 = PPC_LOAD_U32(ctx.r11.u32 + 5032);
    // b 0x823996d8
    sub_823996D8(ctx, base);
    return;
}

PPC_WEAK_FUNC(sub_82090020) {
    __imp__sub_82090020(ctx, base);
}
```

Key things to notice:
- Every function takes `PPCContext& ctx` (register state) and `uint8_t* base` (guest memory pointer)
- Original PPC instructions appear as comments above their C++ translations
- Memory loads/stores include endianness swapping (`PPC_LOAD_U32` etc.)
- The `PPC_WEAK_FUNC` pattern enables hooking — you can override any function in your runtime
- Indirect calls use a "perfect hash table" lookup at runtime

### Common Warnings and How to Fix Them

**"Switch case is trying to jump outside function"**
The function boundary analyzer got the function's extent wrong — the jump table targets land outside what XenonAnalyse thinks is the function. Fix by adding explicit function boundaries:

```toml
functions = [
    { address = 0x821EF000, size = 0x300 },
]
```

**"Found a switch jump table with no switch table entry present"**
A jump table was detected during recompilation but wasn't in the switch tables TOML. Either XenonAnalyse missed it or it uses a pattern the analyzer doesn't recognize. Add it manually:

```toml
[[switch]]
base = 0x823BA1FC
r = 0          # register number containing the index
default = 0x????????
labels = [
    0x????????,
    0x????????,
]
```

**"Unrecognized instruction"**
An instruction the recompiler doesn't support. Common ones for THP8 included `vandc`, `vsel128`, `vctuxs`, `lhbrx`, `dcbst`, `mulhdu`, `frsqrte`. These would need to be implemented in XenonRecomp's instruction translator for full correctness. A `__debugbreak()` is inserted at these locations.

---

## 7. Shader Recompilation (XenosRecomp)

XenosRecomp converts Xbox 360 (Xenos GPU) shader binaries into HLSL, which can then be compiled to DXIL (D3D12) or SPIR-V (Vulkan) using the DirectX Shader Compiler (DXC).

### Finding Shader Binaries

Xbox 360 shaders may be stored in:
- **The XEX executable itself** — embedded directly in the binary
- **Game data archives** — engine-specific formats
- **Standalone files** — less common

XenosRecomp scans for shaders using the magic bytes `0x102A1100` (big-endian) in the `ShaderContainer` header. It searches every 4-byte boundary in each file.

**For single shader conversion:**
```bash
./XenosRecomp input_shader.bin output.hlsl tools/XenosRecomp/XenosRecomp/shader_common.h
```

**For directory scanning (batch mode):**
```bash
./XenosRecomp shader_directory/ output_cache.cpp tools/XenosRecomp/XenosRecomp/shader_common.h
```

The directory scanner recursively walks all files, looking for the `0x102A1100` magic at every 4-byte boundary. Multiple shaders can be embedded in a single file.

### Game-Specific Shader Formats

**This is the part most likely to require custom work.** Different game engines store shaders differently:

- **Games using standard Xbox 360 D3D containers** (e.g., Sonic Unleashed) — XenosRecomp works out of the box
- **Games using custom containers** (e.g., Tony Hawk's Project 8 with Neversoft's `MATL` format) — the compiled shader bytecode is wrapped in a proprietary format and XenosRecomp won't find the magic bytes

For THP8, we found that `MaterialLibrary.bin.xen` contains 1,180 compiled shaders (both vertex and pixel shaders, shader model 3.0) compiled by "Microsoft (R) Xbox 360 Shader Compiler 2.0.3424.0". However, they're wrapped in Neversoft's `MATL` container rather than the standard Xbox 360 shader container format.

**How to check if your game's shaders are compatible:**

```python
# Scan a file for XenosRecomp-compatible shader containers
import struct

with open("game_file.bin", "rb") as f:
    data = f.read()

count = 0
i = 0
while i < len(data) - 36:
    flags = struct.unpack('>I', data[i:i+4])[0]
    if (flags & 0xFFFFFF00) == 0x102A1100:
        vsize = struct.unpack('>I', data[i+4:i+8])[0]
        psize = struct.unpack('>I', data[i+8:i+12])[0]
        f1c = struct.unpack('>I', data[i+0x1C:i+0x20])[0]
        f20 = struct.unpack('>I', data[i+0x20:i+0x24])[0]
        total = vsize + psize
        if f1c == 0 and f20 == 0 and total > 0 and (i + total) <= len(data):
            stype = "VS" if (flags & 1) else "PS"
            print(f"{stype} shader at 0x{i:X}, size {total}")
            count += 1
            i += total
            continue
    i += 4

print(f"Found {count} shaders")
```

If this finds zero results, you'll need to reverse-engineer the game's shader container format. Look for:
- The string "Xbox 360 Shader Compiler" — a strong indicator of compiled shader data nearby
- Constant names like `g_ViewProj`, `g_World`, sampler references
- The byte sequence `vs_3_0` or `ps_3_0` (shader model identifiers)

### Compiling HLSL Output

Once XenosRecomp produces HLSL files, compile them with DXC:

```bash
# For D3D12
dxc -T vs_6_0 -E main shader_vs.hlsl -Fo shader_vs.dxil
dxc -T ps_6_0 -E main shader_ps.hlsl -Fo shader_ps.dxil

# For Vulkan
dxc -T vs_6_0 -E main shader_vs.hlsl -spirv -Fo shader_vs.spv
dxc -T ps_6_0 -E main shader_ps.hlsl -spirv -Fo shader_ps.spv
```

---

## 8. What Comes Next: The Runtime

The recompiled C++ code is just the game's logic translated to a new instruction set. It won't run without a **runtime** — the layer that provides everything the original Xbox 360 OS and hardware provided.

This is by far the most complex part of a recompilation project. Here's what you need and how to build a minimal version.

> **Historical design notes:** Sections 8.1–8.9 describe the standalone
> prototype used early in ProjectRecomp. That prototype is no longer included
> or supported. The active project uses ReXGlue as described in section 8.10.

### 8.1. Project Structure

```
runtime/
├── CMakeLists.txt          # Build system
└── src/
    ├── main.cpp            # Entry: allocates memory, loads image, sets up dispatch, executes
    ├── memory.h / .cpp     # Cross-platform guest memory (mmap / VirtualAlloc)
    ├── dispatch.h / .cpp   # Function dispatch table setup from PPCFuncMappings
    └── kernel_stubs.cpp    # Stub implementations for Xbox 360 kernel functions
```

### 8.2. Guest Memory Layout

The recompiled code accesses memory as `base[guest_addr]`, where `guest_addr` is a 32-bit Xbox 360 virtual address (typically around `0x82000000`). This means `base` must point to an allocation large enough that `base + 0x82000000 + image_size + dispatch_size` is valid.

```
base[0x00000000]  ────────────  Start of allocation
     ...
base[0x70000000]  ────────────  Guest stack (1 MB)
     ...
base[0x82000000]  ────────────  XEX image loaded here (PPC_IMAGE_BASE)
base[0x82090000]  ────────────  Code section start (PPC_CODE_BASE)
base[0x826CD884]  ────────────  Code section end
base[0x82A80000]  ────────────  Dispatch table start (PPC_IMAGE_BASE + PPC_IMAGE_SIZE)
base[0x836FB108]  ────────────  Dispatch table end
```

**Total allocation needed:** ~2.1 GB. Use `mmap` with `MAP_NORESERVE` (Linux) or `MAP_ANON` (macOS) to reserve virtual address space without committing physical memory upfront. On Windows, use `VirtualAlloc` with `MEM_RESERVE | MEM_COMMIT`.

**Key requirements:**
- The `base` pointer must be **32-byte aligned** (enforced by `PPC_FUNC_PROLOGUE()`)
- `mmap` and `VirtualAlloc` return page-aligned pointers, so this is automatic

### 8.3. Function Dispatch Table

The recompiled code uses a "perfect hash table" for indirect function calls (virtual functions, function pointers). The dispatch table lives immediately after the XEX image in guest memory:

```
dispatch_addr = base + PPC_IMAGE_BASE + PPC_IMAGE_SIZE + (guest_addr - PPC_CODE_BASE) * 2
```

The `* 2` maps each 4-byte PPC instruction address to an 8-byte function pointer slot (on 64-bit hosts). Populate it by iterating `PPCFuncMappings[]`:

```cpp
for (size_t i = 0; PPCFuncMappings[i].host != nullptr; ++i) {
    uint32_t guest_addr = PPCFuncMappings[i].guest;
    uint64_t offset = (guest_addr - PPC_CODE_BASE) * 2;
    PPCFunc** slot = (PPCFunc**)(dispatch_base + offset);
    *slot = PPCFuncMappings[i].host;
}
```

### 8.4. PPCContext Initialization

```cpp
PPCContext ctx{};
memset(&ctx, 0, sizeof(ctx));
ctx.msr = 0x200A000;              // Default machine state register
ctx.r1.u64 = stack_top;           // Stack pointer (grows downward)
// r2 = TOC pointer, r13 = SDA pointer (set from XEX headers if needed)
```

### 8.5. Xbox 360 Kernel Stubs

The recompiled code calls Xbox 360 kernel functions by name. Thanks to the weak linkage pattern, you can override any function by defining `PPC_FUNC_IMPL(FunctionName)`.

**For Tony Hawk's Project 8, 234 kernel functions needed stubs**, spanning:

| Category | Count | Examples |
|----------|-------|---------|
| NT Kernel | ~30 | `NtCreateFile`, `NtReadFile`, `NtAllocateVirtualMemory` |
| Kernel Executive | ~25 | `KeWaitForSingleObject`, `KeDelayExecutionThread` |
| Runtime Library | ~15 | `RtlInitializeCriticalSection`, `RtlEnterCriticalSection` |
| Memory Manager | ~8 | `MmAllocatePhysicalMemoryEx`, `MmFreePhysicalMemory` |
| Video Driver | ~20 | `VdInitializeEngines`, `VdSwap`, `VdSetDisplayMode` |
| Xbox App Manager | ~40 | `XamInputGetState`, `XamShowSigninUI` |
| XAudio/XMA | ~20 | `XMACreateContext`, `XAudioSubmitRenderDriverFrame` |
| Networking | ~25 | `NetDll_socket`, `NetDll_connect`, `NetDll_send` |
| C Runtime | ~3 | `sprintf`, `_vsnprintf` |

**Auto-generating stubs:** A prototype runtime can use the linker's undefined
symbol output to identify the stubs it needs:

```bash
# Build and capture undefined symbols for a project-specific generator
cmake --build . 2>&1 | grep "referenced from" | \
    sed 's/.*"__imp__//' | sed 's/(PPCContext.*//' | sort -u > missing_symbols.txt
```

Each stub logs its name on first call and returns 0 (success):

```cpp
PPC_FUNC(__imp__NtReadFile) {
    PPC_FUNC_PROLOGUE();
    static bool logged = false;
    if (!logged) { fprintf(stderr, "STUB: NtReadFile called\n"); logged = true; }
    ctx.r3.u64 = 0; // STATUS_SUCCESS
}
```

### 8.6. CMake Build Setup

```cmake
cmake_minimum_required(VERSION 3.16)
project(your_game_runtime CXX)
set(CMAKE_CXX_STANDARD 17)

# Require Clang (weak attribute not supported by MSVC)
if(NOT CMAKE_CXX_COMPILER_ID MATCHES "Clang")
    message(FATAL_ERROR "This project requires Clang")
endif()

# Paths
set(PPC_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../ppc")
set(SIMDE_DIR "${CMAKE_CURRENT_SOURCE_DIR}/../tools/XenonRecomp/thirdparty/simde")

# Collect recompiled sources
file(GLOB PPC_RECOMP_SOURCES "${PPC_DIR}/ppc_recomp.*.cpp")
list(APPEND PPC_RECOMP_SOURCES "${PPC_DIR}/ppc_func_mapping.cpp")

add_executable(your_game_runtime
    src/main.cpp src/memory.cpp src/dispatch.cpp src/kernel_stubs.cpp
    ${PPC_RECOMP_SOURCES}
)

target_include_directories(your_game_runtime PRIVATE ${PPC_DIR} ${SIMDE_DIR})
target_compile_options(your_game_runtime PRIVATE
    -Wno-null-arithmetic -Wno-unused-value -Wno-tautological-undefined-compare
)
```

### 8.7. Running It

```bash
mkdir build && cd build
cmake .. -DCMAKE_CXX_COMPILER=clang++
cmake --build . --config Release -j8
./your_game_runtime path/to/default_decompressed.bin
```

**Expected output for a minimal first run:**
```
=== THP8 Recomp Runtime ===

[1] Allocating guest memory: 2214592512 bytes (2.1 GB)...
  Guest memory base: 0x300000000
  Alignment check: base & 0x1F = 0x0 (OK)
[2] Loading XEX image...
  Loaded 11010048 bytes at base+0x82000000
[3] Setting up dispatch table...
  Functions registered: 39272
[4] Initializing PPCContext...
  r1 (stack pointer): 0x70100000
[5] Resolving entry point: 0x823AC158
[6] Attempting to execute entry point...
STUB: NtReadFile called
Entry point returned normally.
```

The game enters its initialization, hits an `NtReadFile` call (likely loading a config or boot file), and returns because the stub returns success without providing data. From here, the work is incremental: implement kernel stubs one at a time, starting with the ones that get called first.

### 8.8. Porting Kernel Code from Other Recompilations

The [UnleashedRecomp](https://github.com/hedge-dev/UnleashedRecomp) project provides battle-tested implementations of many Xbox 360 kernel primitives. Since the kernel ABI is the same across all Xbox 360 titles, the following can be ported directly with minor adaptation:

- **Events** (`KeInitializeEvent`, `KeSetEvent`, `KeResetEvent`, `KeWaitForSingleObject`) — atomic flag + `std::condition_variable`
- **Semaphores** (`KeInitializeSemaphore`, `KeReleaseSemaphore`) — counting semaphore with condition variable
- **TLS** (`KeTlsAlloc`, `KeTlsSetValue`, `KeTlsGetValue`, `KeTlsFree`) — `thread_local` vector indexed by slot
- **Spinlocks** (`KfAcquireSpinLock`, `KfReleaseSpinLock`) — `std::atomic_ref` CAS loop
- **PCR** (Processor Control Region, `r13`) — per-thread struct at a fixed guest address (`0x7F000000`)

Key adaptation: the UnleashedRecomp kernel uses C++ classes stored in a host-side map keyed by guest address. Pointer sizes differ (their target may be 32-bit vs 64-bit), so check struct layouts carefully.

### 8.9. The `trapWord` / Worker Thread Problem

Xbox 360 `tw` (trap word) instructions like `twllei r9,0` and `twlgei r11,-1` are frequently used as lightweight **inter-thread signaling primitives** — they trigger a hardware trap that the OS intercepts to reschedule waiting threads. XenonRecomp emits these as **comments only** (no-ops).

This causes silent deadlocks: producer code pushes work to a ring buffer and issues a trapWord to wake a worker thread, but the worker never wakes because the trap is a no-op.

**The symptom:** a spin-loop `while (io_obj[212] != 0)` never exits.

**The fix pattern:** Override the work-submission function to call the inline work processor (`sub_823A25E8`-style) synchronously, bypassing the worker thread entirely. Use a `thread_local bool` recursion guard to prevent infinite loops when the completion callback re-enters the submission path:

```cpp
// Capture queue_manager pointer from work-submission callers.
static thread_local uint32_t g_async_qm = 0;

PPC_FUNC(sub_823A2890) {      // work submission function
    PPC_FUNC_PROLOGUE();
    g_async_qm = ctx.r3.u32;  // capture before original runs
    __imp__sub_823A2890(ctx, base);
}

PPC_FUNC(sub_823A67B8) {      // ring-buffer push (trapWord site)
    PPC_FUNC_PROLOGUE();
    thread_local bool in_dispatch = false;
    if (!in_dispatch) {
        uint32_t slot_ptr = PPC_LOAD_U32(ctx.r4.u32);
        in_dispatch = true;
        ctx.r3.u32 = g_async_qm;
        ctx.r4.u32 = slot_ptr;
        ctx.r5.u32 = 0;
        sub_823A25E8(ctx, base);  // inline: processes work + calls completion callback
        in_dispatch = false;
    }
    // Recursive call (completion notification): skip; spin-wait already cleared.
}
```

The completion callback (`sub_823A43C8`) clears `io_obj[212] = 0` during the synchronous `sub_823A25E8` call, so the spin-wait exits immediately when control returns to the caller.

### 8.10. Alternative: Using the ReXGlue SDK (Recommended)

Building a runtime from scratch (as described in sections 8.1–8.9) is instructive but extremely time-consuming. **[ReXGlue SDK](https://github.com/rexglue/rexglue-sdk)** is a complete Xbox 360 recompilation runtime that provides kernel, D3D12 GPU translation, audio, input, and more — out of the box.

> **THP8 now uses ReXGlue.** The historical custom runtime has been removed;
> `project/` uses the ReXGlue SDK.

#### Why ReXGlue vs. custom runtime

| Aspect | Historical custom prototype | ReXGlue SDK (`project/`) |
|--------|-------------------|------------------------|
| Kernel functions | 234 stubs, ~few implemented | SDK implements all common ones |
| File I/O | Custom NtCreateFile/NtReadFile | Full VFS with game:\ path mapping |
| Threading | std::thread wrapping | XThread, event, semaphore, TLS |
| Graphics | No translation | D3D12 GPU command translation |
| Audio | Stubs only | XMA decode + SDL3 playback |
| XEX loading | Manual decompressed binary | SDK loads XEX and automatically applies a sibling XEXP |
| Build | ~10 files, simple | `find_package(rexglue)`, 3 files |

#### Setup

1. **Initialize the ReXGlue v0.10.0 submodule**:
   ```bash
   git submodule update --init --recursive tools/rexglue-sdk
   ```

2. **Run codegen** to regenerate PPC→C++ using ReXGlue's PPCContext (incompatible with XenonRecomp's context due to extra `kernel_state*` field at offset 0):
   ```bash
   tools/rexglue-sdk/out/install/linux-amd64/bin/rexglue codegen config/THP8_rexglue.toml
   ```
   This produces `generated/` with 237 recomp files plus the project headers, registration sources, and `sources.cmake`.

   ReXGlue automatically looks for `default.xexp` beside `default.xex` during
   codegen. THP8's current configuration targets the unpatched retail XEX, so
   that file must be absent or renamed before running this command.

3. **Build**:
   ```powershell
   cmake -S project -B project/build -G Ninja \
     -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
     -DCMAKE_BUILD_TYPE=RelWithDebInfo
   cmake --build project/build -j8
   ```

4. **Extract game data** from the disc image using [extract-xiso](https://github.com/XboxDev/extract-xiso):
   ```powershell
   tools/extract-xiso/artifacts/extract-xiso.exe "private/Tony Hawk's Project 8.iso"
   # Creates: "Tony Hawk's Project 8/DATA/..."
   ```

   The extracted game directory must also omit or rename `default.xexp`.
   ReXGlue applies a sibling patch automatically at runtime, which would not
   match this project's unpatched generated code.

5. **Run**:
   ```powershell
   SDL_VIDEODRIVER=x11 project/build/thp8 \
     --game_data_root="path/to/game/directory" \
     --gpu_plugin=xenos --fullscreen=false
   ```

#### Project structure with ReXGlue

```
project/
├── CMakeLists.txt      # ReXGlue submodule + generated sources
└── src/
    ├── thp8_app.h      # THP8App : rex::ReXApp — just override hooks
    ├── main.cpp        # REX_DEFINE_APP(thp8, THP8App::Create)
    └── stubs.cpp       # Legacy patched-build overrides (not compiled)

generated/              # Output of rexglue codegen (gitignored)
    thp8_pch.h          # Image config, PPC ABI, and memory helpers
    thp8_init.h/cpp     # Image info and module registration
    thp8_register.cpp   # Recompiled function registration
    thp8_recomp.N.cpp   # 237 recomp files

config/
    THP8_rexglue.toml # Project manifest and codegen config
```

#### Legacy patched-build overrides (stubs.cpp)

The historical overrides in `stubs.cpp` target patched executable addresses and
are intentionally excluded from the current unpatched build. Do not enable them
without revalidating every address against the selected XEX.

```cpp
// Heap sentinel repair (see stubs.cpp for details)
extern "C" REX_FUNC(sub_823AE680) { ... }

// Async I/O deadlock fix (trapWord-based signaling)
extern "C" REX_FUNC(sub_823A67B8) { ... }

// Disc path check suppressor (Xbox 360 disc error UI)
extern "C" REX_FUNC(sub_823A13A8) { ctx.r3.u64 = 0; }
```

### 8.11. Next Steps for the Runtime

The following list applied to the removed custom-runtime prototype. ReXGlue
provides these runtime services for the active project.

1. **File I/O** — Implement `NtCreateFile`/`NtReadFile`/`NtWriteFile` to load game data from the extracted disc
2. **Memory management** — Implement `NtAllocateVirtualMemory` and `MmAllocatePhysicalMemoryEx` to give the game real heap memory
3. **Threading** — Implement `ExCreateThread` to allow the game to spawn threads
4. **Critical sections** — Implement `RtlInitializeCriticalSection`/`Enter`/`Leave` using `std::mutex`
5. **Graphics** — Either stub `Vd*` functions or begin implementing a D3D12/Vulkan translation layer
6. **Audio** — Stub `XMA*` and `XAudio*` functions, or implement XMA decoding with FFmpeg

---

## 9. Troubleshooting & Game-Specific Issues

### "All register patterns show NOT FOUND"
The XEX is compressed/encrypted. Use the `xex_dump` helper tool (which uses XenonUtils internally) instead of searching the raw file.

### XenonAnalyse exits silently
Check that the XEX file path is correct and the file is a valid XEX2 binary (magic bytes `XEX2` at offset 0).

### XenonAnalyse misses jump tables
The detection logic was written for Sonic Unleashed's compiler output. Different Xbox 360 compiler versions produce different jump table patterns. Look for `mtctr r0` followed by `bctr` in the disassembly — that's the typical jump table pattern. You can add tables manually to the TOML.

### XenosRecomp finds zero shaders
The game uses a custom shader container format. You'll need to:
1. Find where shader data lives (search for "Xbox 360 Shader Compiler" or "vs_3_0"/"ps_3_0" strings)
2. Reverse-engineer the container format
3. Either extract shaders into the standard format or modify XenosRecomp

### Recompiled code has many unrecognized instructions
The recompiler doesn't support every PPC instruction. Common missing ones include less-used VMX (vector) instructions and some bit-manipulation instructions. These would need to be implemented in XenonRecomp's instruction translator. For each unrecognized instruction, a `__debugbreak()` is inserted — you'll discover at runtime which ones are actually hit.

### Game hangs in a spin-loop (trapWord deadlock)
See [Section 8.9](#89-the-trapword--worker-thread-problem). The game uses `twllei`/`twlgei` trap-word instructions to signal worker threads. These are no-ops in the recompilation. Find the ring-buffer push function containing these instructions (it's the callee of the work-submission function, before the spin-wait loop), and override it to call the inline work processor synchronously.

### Dispatch table collides with game globals/BSS
On some titles (including THP8), the game's BSS/global variables at runtime overlap with the dispatch table if it's placed immediately after the XEX image in guest memory. A custom runtime must keep the dispatch table in **host** (not guest) memory and update `PPC_CALL_INDIRECT_FUNC` to use the host-side table pointer directly.

---

## 10. Resources

### Xbox 360 Architecture
- [Free60 Wiki](https://free60.org/) — community-documented Xbox 360 hardware info
- [Xenia GPU Documentation](https://github.com/xenia-project/xenia/blob/master/docs/gpu.md) — Xenos GPU details
- [IBM PowerPC ISA](https://www.ibm.com/docs/en/aix/7.2?topic=programming-powerpc-architecture) — instruction set reference

### Recompilation Projects
- [Unleashed Recompiled](https://github.com/hedge-dev/UnleashedRecomp) — the reference Xbox 360 recompilation (Sonic Unleashed)
- [N64: Recompiled](https://github.com/N64Recomp/N64Recomp) — the project that inspired XenonRecomp (simpler architecture, good for understanding the concept)
- [Zelda 64: Recompiled](https://github.com/rt64/zelern64) — another successful N64 recompilation

### Emulators (for reference implementations)
- [Xenia](https://github.com/xenia-project/xenia) — Xbox 360 emulator with extensive kernel, CPU, and GPU implementations
- [Xenia Canary](https://github.com/xenia-canary/xenia-canary) — active fork with additional game compatibility

### Tools
- [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) — **recommended runtime** for new projects; provides kernel, GPU, audio, input
- [XenonRecomp](https://github.com/hedge-dev/XenonRecomp) — PPC → C++ recompiler
- [XenosRecomp](https://github.com/hedge-dev/XenosRecomp) — Xenos shader → HLSL recompiler
- [extract-xiso](https://github.com/XboxDev/extract-xiso) — Xbox/Xbox 360 disc image extractor
- [xdvdfs](https://crates.io/crates/xdvdfs-cli) — Rust-based XDVDFS extractor

---

*This guide was written while working on a recompilation of Tony Hawk's Project 8 (Xbox 360). The project started with a custom runtime (XenonRecomp + hand-rolled kernel stubs) and later migrated to the [ReXGlue SDK](https://github.com/rexglue/rexglue-sdk) for a complete runtime.*
