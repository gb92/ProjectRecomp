#include <cstdio>
#include <cstring>
#include <filesystem>
#include <fstream>
#include <vector>
#include "image.h"
#include "xex.h"
#include "xex_patcher.h"

static std::vector<uint8_t> readFile(const char* path) {
    std::ifstream in(path, std::ios::binary | std::ios::ate);
    if (!in.is_open()) return {};
    size_t sz = in.tellg();
    in.seekg(0);
    std::vector<uint8_t> buf(sz);
    in.read(reinterpret_cast<char*>(buf.data()), sz);
    return buf;
}

int main(int argc, char* argv[]) {
    if (argc < 3) {
        fprintf(stderr, "Usage: xex_dump <input.xex> <output.bin> [patch.xexp [patched_out.xex]]\n");
        fprintf(stderr, "Decompresses an XEX and dumps the raw code image.\n");
        fprintf(stderr, "If patch.xexp is provided, the patch is applied before decompression.\n");
        return 1;
    }

    std::vector<uint8_t> fileData = readFile(argv[1]);
    if (fileData.empty()) {
        fprintf(stderr, "Failed to open %s\n", argv[1]);
        return 1;
    }

    // Apply patch if provided
    if (argc >= 4) {
        std::vector<uint8_t> patchData = readFile(argv[3]);
        if (patchData.empty()) {
            fprintf(stderr, "Failed to open patch file %s\n", argv[3]);
            return 1;
        }
        printf("Applying patch %s...\n", argv[3]);
        std::vector<uint8_t> patchedData;
        auto result = XexPatcher::apply(fileData.data(), fileData.size(),
                                        patchData.data(), patchData.size(),
                                        patchedData, false);
        if (result != XexPatcher::Result::Success) {
            fprintf(stderr, "Patch failed (error %d)\n", (int)result);
            return 1;
        }
        printf("Patch applied successfully (%zu bytes).\n", patchedData.size());

        // Optionally write the patched XEX
        if (argc >= 5) {
            std::ofstream pout(argv[4], std::ios::binary);
            pout.write(reinterpret_cast<const char*>(patchedData.data()), patchedData.size());
            pout.close();
            printf("Wrote patched XEX to %s\n", argv[4]);
        }
        fileData = std::move(patchedData);
    }

    Image image = Xex2LoadImage(fileData.data(), fileData.size());

    printf("Base address: 0x%08X\n", (uint32_t)image.base);
    printf("Entry point:  0x%08X\n", (uint32_t)image.entry_point);
    printf("Image size:   0x%X (%u bytes)\n", image.size, image.size);

    // Dump the decompressed image
    std::ofstream out(argv[2], std::ios::binary);
    out.write(reinterpret_cast<const char*>(image.data.get()), image.size);
    out.close();

    printf("Wrote decompressed image to %s\n", argv[2]);

    // Now search for register save/restore patterns
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
        {"restgprlr_14_address", restgprlr, sizeof(restgprlr)},
        {"savegprlr_14_address", savegprlr, sizeof(savegprlr)},
        {"restfpr_14_address",   restfpr,   sizeof(restfpr)},
        {"savefpr_14_address",   savefpr,   sizeof(savefpr)},
        {"restvmx_14_address",   restvmx14, sizeof(restvmx14)},
        {"savevmx_14_address",   savevmx14, sizeof(savevmx14)},
        {"restvmx_64_address",   restvmx64, sizeof(restvmx64)},
        {"savevmx_64_address",   savevmx64, sizeof(savevmx64)},
    };

    printf("\n=== Register Save/Restore Functions ===\n\n");
    printf("# TOML config values:\n");

    int found = 0;
    for (const auto& pat : patterns) {
        bool matched = false;
        for (size_t i = 0; i <= image.size - pat.len; i++) {
            if (memcmp(image.data.get() + i, pat.bytes, pat.len) == 0) {
                uint32_t va = image.base + (uint32_t)i;
                printf("%s = 0x%08X\n", pat.name, va);
                matched = true;
                found++;
                break;  // Take the first match
            }
        }
        if (!matched) {
            printf("# %s = NOT FOUND\n", pat.name);
        }
    }

    printf("\n# Found %d/8 patterns\n", found);

    // Also search for longjmp/setjmp hints
    // Look for common longjmp patterns (save/restore of many registers)
    printf("\n# Entry point: 0x%08X\n", (uint32_t)image.entry_point);
    printf("# Base address: 0x%08X\n", (uint32_t)image.base);

    return 0;
}
