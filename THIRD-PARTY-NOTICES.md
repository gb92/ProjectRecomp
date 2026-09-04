# Third-Party Notices

ProjectRecomp includes or links third-party software. Those components remain
under their own licenses; the ProjectRecomp BSD 3-Clause License does not
replace them.

The Windows package is built from ReXGlue commit
`4c1350847bb2bbc5fbf4272c78731632fccce8ab` plus the ordered patches in
`patches/rexglue-v0.10.0/`. Full license texts are installed in the `licenses`
directory.

## Corresponding Source

FFmpeg and libmspack are linked statically into the ReXGlue runtime under the
GNU Lesser General Public License version 2.1.

The complete machine-readable source used to build each release, including the
exact recursive ReXGlue submodules, configuration files, ProjectRecomp patches,
and build instructions, is distributed beside the installer as:

- `ProjectRecomp-<version>-Source.zip`

Checksums are provided in
`ProjectRecomp-<version>-Source-SHA256SUMS.txt`. See
`docs/recompilation-guide.md` in the archive for rebuilding and relinking
instructions. The archive contains no game executable or game assets.

## Runtime Components

| Component | Use | License |
|-----------|-----|---------|
| ReXGlue SDK and Xenia-derived runtime code | Runtime and Xenos GPU plugin | BSD 3-Clause |
| SDL3 | Windowing, input, and audio | zlib |
| Dear ImGui and ProggyClean font | Host configuration UI | MIT |
| fmt | Formatting | MIT |
| spdlog | Logging | MIT |
| toml++ | Configuration | MIT |
| SIMDe | Portable SIMD helpers | MIT |
| utf8cpp | UTF-8 conversion | Boost Software License 1.0 |
| CLI11 | Command-line parsing | BSD 3-Clause |
| disruptorplus | Timer queue | MIT |
| xxHash | Hashing | BSD 2-Clause |
| o1heap | Guest heap support | MIT |
| AES-128 and DES implementations | Xbox cryptography support | MIT |
| TinySHA1 | Xbox cryptography support | ISC-like permissive license |
| SHA-256 by Stephan Brumme | Xbox cryptography support | zlib-style |
| Rijndael implementation | Xbox cryptography support | Public domain |
| FFmpeg libavcodec/libavutil | XMA and other audio decoding | LGPL 2.1 or later |
| libmspack | XEX LZX decompression | LGPL 2.1 |
| Tracy client | Optional profiling in non-Release builds | BSD 3-Clause |
| Tracy's LZ4 | Tracy compression | BSD 2-Clause |
| moodycamel concurrentqueue | Tracy queue | BSD 2-Clause |
| Erik Rigtorp SPSCQueue | Tracy queue | MIT |
| rpmalloc | Tracy allocation | Public domain |
| stb_image | Image loading | Public domain or MIT |
| RenderDoc API header | Optional graphics capture integration | MIT |
| DirectX Shader Compiler API headers | D3D12 shader API declarations | University of Illinois/NCSA |
| AMD ShaderUtils DXBC checksum | DXBC checksum generation | MIT, with RSA MD5 notice |
| Microsoft Visual C++ Runtime | App-local C/C++ runtime | Microsoft Redistributable Code |
| Inno Setup | Windows installer engine | Inno Setup license |

The complete corresponding-source archives also contain build-only and
test-only dependencies. Their presence in source does not mean they are linked
into the installed application.

## FFmpeg

This product uses FFmpeg under the LGPL version 2.1 or later. The Windows x64
configuration recorded by the pinned source is:

```text
--toolchain=msvc --arch=x86_64 --disable-everything --disable-programs
--disable-all --disable-x86asm --disable-autodetect --disable-network
--enable-avcodec --enable-avformat --enable-avutil
--enable-decoder='mp3,mp3float,wmav2,xmaframes'
--enable-parser=mpegaudio --enable-demuxer='asf,mp3'
--enable-protocol=file
```

`CONFIG_GPL`, `CONFIG_NONFREE`, and `CONFIG_VERSION3` are disabled. ProjectRecomp
does not modify FFmpeg source files; ReXGlue selects the required sources and
provides platform configuration headers.

This software is based in part on the work of the Independent JPEG Group.

See `licenses/FFmpeg-LICENSE.md` and `licenses/FFmpeg-LGPL-2.1.txt`.

## libmspack

ReXGlue compiles libmspack's LZX decompressor for XEX loading. ProjectRecomp
does not modify the libmspack source. See
`licenses/libmspack-LGPL-2.1.txt`.

## Microsoft Visual C++ Runtime

The Windows installer redistributes unmodified release runtime files selected
from the Visual Studio v143 Redistributable directory:

- `msvcp140.dll`
- `msvcp140_atomic_wait.dll`
- `vcruntime140.dll`
- `vcruntime140_1.dll`

These files are Microsoft Redistributable Code governed by the applicable
Visual Studio license terms. They are not open-source software.

## Additional Attribution

The DXBC checksum implementation is derived from the RSA Data Security, Inc.
MD5 Message Digest Algorithm. The required RSA notice is preserved in
`licenses/AMD-ShaderUtils-MIT-and-RSA-MD5.txt`.

The embedded ProggyClean font is Copyright (c) 2004, 2005 Tristan Grimmer and
is used under the MIT License included with Dear ImGui.
