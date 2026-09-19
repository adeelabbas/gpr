# CLAUDE.md

Project context and standards for Claude Code sessions and PR reviews in this
repository.

## What this repo is

A public fork of [gopro/gpr](https://github.com/gopro/gpr), the GoPro RAW
(GPR) SDK: the VC-5 wavelet codec, a C API that converts between GPR / DNG /
RAW / VC5 / RGB, a patched copy of the Adobe DNG SDK 1.4, and the `gpr_tools`
CLI.

The fork carries a deliberately **minimal** set of changes on top of upstream,
all of them in service of writing GPR and DNG files well:

- **enhancements** so capture formats from other sensors encode correctly
  (the BGGR mosaic, large black level and `ActiveArea` crop of an iPhone DNG,
  for example) and so the DNGs the SDK writes render correctly in Apple, Adobe
  and other readers (equalized green gain maps, thumbnails in IFD 0, faithful
  `WarpRectilinear`, lens profiles, embedded previews);
- **bug fixes** (VC-5 memory streams that wrote past their buffer, a fixed
  thumbnail buffer, an out-of-bounds read in the Bayer phase shift, DNG SDK
  exceptions escaping the C API, XMP toolkit data races);
- **code cleanups** that make the API easier to integrate (CMake feature
  options, `gpr_parameters_parse_dng`, one `RGB_PARAMETERS` struct shared by
  encoder and decoder, a contiguous output stream, `gpr_convert_gpr_to_gpr`,
  a test suite and CI).

It is **pure C/C++**: C is pinned to C99 (`CMakeLists.txt`), C++ builds at the
compiler default, and there is no application code. The GPRaw macOS app that
consumes this SDK lives in its own repository and is never reviewed here.

## The three repositories, and keeping them in sync

| Repository | Role |
|---|---|
| `gopro/gpr` (upstream) | Where everything here comes from. This fork must read as a small, reviewable delta on top of its `master`. |
| `adeelabbas/gpr` (this repository) | The public fork: encoder and DNG-writer work meant for GoPro, Apple and other adopters. |
| `gpraw/gpr` (downstream, private) | The GPRaw app's SDK. Carries everything here plus private-only work (multithreaded decoding, a VLC lookup cursor, extra sample fixtures, its own CI). |

**Changes here must stay minimal against both neighbours**, and every change
has to be carried across so the three do not drift. The rules:

- **Land it here first.** Anything that changes what the SDK writes, keeps the
  writer safe, or makes the API easier to use is a PR against `master` here,
  then a cherry-pick into `gpraw/gpr`. Write the commit so that the cherry-pick
  applies without conflicts: touch only lines the two trees share (downstream
  differs in the `thread_count` argument on every `gpr_convert_*`, in
  `source/lib/vc5_decoder/decoder.c` and `vlc.c`, in its sample list and its
  CI), keep README, CLAUDE.md and workflow edits in their own commits, and
  write new tests against the `gpr_tools` conversion layer (`dng_convert_main`)
  rather than against the `gpr_convert_*` signatures. Before opening the PR,
  cherry-pick the code commits onto a scratch branch of a local `gpraw/gpr`
  clone, build, run its suite, and say so in the PR body.
- **Borrow from downstream.** Patterns that already exist in `gpraw/gpr` and
  apply to GPR file writing (encoder features, DNG metadata handling, writer
  robustness, test cases, review findings) belong here as well. Port them
  rather than re-deriving them, and prove the port: build both trees and
  compare `gpr_tools` output over `data/samples` with `cmp`; outputs are
  expected to be byte-identical unless the PR says which ones change and why.
- **Do not bring decoder-only work here** (threading, the VLC cursor, render
  changes that do not affect what the encoder writes) unless a PR says
  explicitly that it does and why.
- **Track upstream.** When `gopro/gpr` `master` moves, merge it into `master`
  here first; downstream then merges this repository.
- **The private fixtures stay private.** `data/samples` holds upstream's six
  files and the suite must pass on exactly those. The HERO13, MISSION 1 PRO
  and iPhone fixtures, and `lena.jpg`, live only in `gpraw/gpr`; a test that
  needs them has to degrade to what ships here (the MISSION 1 PRO lens profile
  is checked through the table lookup, for example).

## README.md: the "About this fork" section is the contract

The section at the top of `README.md` headed **About this fork** lists what
this repository does that upstream does not. **It must always match the
actual delta against `gopro/gpr` `master`.** A PR that adds, removes or
changes a user-visible behaviour, a public API entry point, a `gpr_tools`
option or a build switch updates that section in the same PR, and a reviewer
treats a stale section as a blocking finding. Keep it a list of behaviours in
plain language, grouped the way it is now, not a changelog of commits.

## Layout and ownership

| Path | Status |
|---|---|
| `source/lib/gpr_sdk/public` | First-party. The public C API (`gpr.h`, `gpr_tuning_info.h`, `gpr_lens_profiles.h`, ...). |
| `source/lib/gpr_sdk/private` | First-party. Conversion matrix, DNG bridging, the render helpers, the flat write stream, the lens profile table. |
| `source/lib/common` | First-party. `gpr_platform.h`, the allocator, buffers, log, timer, `jpeg.h`, and the public types shared with the codec (`gpr_rgb_buffer.h`). |
| `source/lib/vc5_common`, `vc5_decoder`, `vc5_encoder` | First-party. The codec. NEON kernels are encoder-only. |
| `source/app/gpr_tools` | First-party. The CLI and `dng_convert_main`, which the test suite also drives. |
| `source/app/vc5_encoder_app`, `vc5_decoder_app` | First-party upstream samples; kept building, otherwise untouched. |
| `source/test` | First-party. The whole test suite, one file. |
| `source/lib/dng_sdk` | **Vendored and forked.** Adobe DNG SDK 1.4 with upstream's patches plus this fork's in `dng_shared.cpp`, `dng_xmp_sdk.cpp`, `dng_image_writer.cpp` and the added `dng_stage1_negative.*`. Edits are legitimate but must be surgical and justified in the PR body. |
| `source/lib/xmp_core`, `expat_lib`, `md5_lib`, `tiny_jpeg`, `source/app/common/cJSON` | Vendored. `xmp_core` carries the locking fix and `tiny_jpeg` the batched writer and 4:2:0 path; otherwise keep diffs minimal and never restyle. |
| `source/app/common/argument_parser` | Mixed: `program_options_lite.*` is vendored ITU/ISO BSD; `argument_parser.*` is first-party. |
| `scripts` | First-party. The build-flag matrix, the conversion pipeline over a folder of samples, the lens-profile fitting tool. |
| `.github/workflows` | The build-flag matrix on hosted Ubuntu x86_64 and macOS arm64 runners. |

Ignore entirely: `build/` (gitignored) and anything under `scripts/out` or
`out/`.

## Build and test

```sh
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
ctest --test-dir build --output-on-failure
```

Add `-C Release` (or `-C Debug`) to the `ctest` line for multi-config
generators (Xcode, MSVC). The test binary also runs directly and takes an
optional sample directory as `argv[1]`:
`./build/source/test/gpr_tools_tests data/samples` (Xcode puts it under a
`Release/` or `Debug/` subdirectory). It prints a per-case log and a final
`Cases run: N failed: 0 ...` line, exiting non-zero if any non-xfail case
failed or crashed.

`scripts/test_build_flags.sh` builds the baseline, each of `GPR_NEON`,
`GPR_READING`, `GPR_WRITING`, `GPR_JPEG_AVAILABLE` and `GPR_TIMING` off on its
own, and all off: seven configure-and-build passes. CI
(`.github/workflows/build-flags.yml`) runs it on `ubuntu-latest` (x86_64,
scalar) and `macos-latest` (arm64, NEON) and then `ctest` on the baseline
build. It is the check most PRs actually trip; reason about the matrix when
reviewing.

## Review standards

Order findings by the sections below. Report a finding only after reading the
code that proves it, cite `file:line`, and give the concrete failure scenario
(inputs or state -> wrong output or crash). Say plainly when nothing blocking
was found.

### 1. Memory safety and crash behaviour: blocking

- **Allocator pairing.** `Alloc*` fills a caller-owned struct and pairs with
  `Release*`; `Create*` allocates the struct too and pairs with `Delete*`.
  Codec functions take `gpr_allocator *allocator` first and call
  `allocator->Alloc` / `->Free`.
- **`gpr_buffer` carries no ownership**; whoever receives one frees it.
- **`gpr_buffer_auto` has three traps** (`source/lib/common/private/gpr_buffer_auto.h`):
  `resize()` only rewrites `.size` and does not reallocate, `set()` adopts a
  pointer non-owning by default, and `allocate()` asserts the buffer is
  currently NULL.
- **Two allocation domains.** `gpr_allocator` and the DNG SDK's
  `dng_memory_allocator` / `dng_memory_block` are separate; freeing across
  them is a defect. `AutoPtr<T>::Release()` transfers ownership.
- **No exception may escape the C API.** The DNG SDK throws `dng_exception`
  on malformed input; every C-linkage `gpr_*` entry point that reaches it has
  a `catch( ... )` returning `false`. An `assert(0)` on a reachable
  malformed-input path is itself a crash in Debug builds.
- **Pointer aliases into a buffer are the recurring bug class.** A helper that
  returns an interior pointer must be checked against the callee's stride and
  length assumptions (the old `adjust_bayer_phase` read past the allocation).
- **Fixed-size buffers are a defect** when the payload has no bound: VC-5
  output and JPEG thumbnails both grew past "reasonable" sizes on large
  frames. Size from the input or grow on demand.

### 2. Build-flag correctness

Five flags, defaulted in `source/lib/common/public/gpr_platform.h` and exposed
as CMake options: `GPR_READING`, `GPR_WRITING`, `GPR_JPEG_AVAILABLE`,
`GPR_TIMING`, `GPR_NEON`. `GPR_NEON` defaults to 0 in the header and is
injected project-wide by CMake on arm64; that disagreement is deliberate.

- `GPR_READING` / `GPR_WRITING` guards run through the public header, so those
  configurations change the API surface. A declaration added outside the
  right `#if` silently breaks them; a struct field must exist in every
  configuration (`gpr_parameters` keeps one layout).
- Anything the public API needs from the codec (an enum, a constant) lives in
  `source/lib/common/public`, never in `vc5_encoder` or `vc5_decoder`, whose
  directories and include paths exist only when their flag is on.
- New `#if GPR_*` regions need `#else` fallbacks, or the all-off build fails.
- `source/lib/dng_sdk/CMakeLists.txt` does not set these symbols, so a
  flag-guarded region that changes a struct or class layout in `dng_sdk` is an
  ODR skew across translation units.

### 3. Format and interop correctness

- OpcodeList payloads are big-endian regardless of the TIFF container's byte
  order (DNG spec).
- Apple's ImageIO/CIRAWFilter drops the entire OpcodeList2 gain map unless the
  two green CFA planes carry byte-identical gains. The greens are identified
  from each opcode's own `dng_area_spec` (the `(top,left)` parity names its
  cell in the 2x2 CFA tile), never by position in the opcode list.
- A written DNG carries a JPEG thumbnail in IFD 0; without one, readers that
  show IFD 0 display the raw CFA data as black.
- Check bit depth and pixel format against the declared range
  (`PIXEL_FORMAT_RGGB_12` ... `PIXEL_FORMAT_BGGR_14`), black and white levels,
  and white-balance gains. A changed encoder default changes every file
  written without an explicit setting; the PR must say so with measured sizes.

### 4. Minimal diff, and in sync

- The change is the smallest that fixes the root cause. Special cases layered
  on shared infrastructure are the sign that a fix is too shallow.
- The cherry-pick rules above hold: shared lines only, documentation and CI
  in separate commits, tests on the CLI layer, verified downstream.
- **The README "About this fork" section reflects the change.**
- **The customer API speaks GPR, the codec stays as upstream has it.** Nothing
  in `source/lib/gpr_sdk/public` exposes a `VC5_*` name, and no codec type
  moves out of `vc5_encoder.h` / `vc5_decoder.h` to make that possible: a
  codec header that matches upstream is what lets GoPro absorb a change. When
  the SDK needs a codec enum, declare its own `GPR_*` enum in the SDK header
  and tie the two together in `gpr.cpp` with a compile-time check, as
  `GPR_QUALITY_SETTING` does for `VC5_ENCODER_QUALITY_SETTING` (and as
  `GPR_PIXEL_FORMAT` stands for `VC5_ENCODER_PIXEL_FORMAT`). `gpr.h` cannot
  include the codec headers in any case: they exist only when the matching
  `GPR_READING` / `GPR_WRITING` switch is on.
- Reuse what exists rather than adding a parallel implementation:
  `gpr_buffer_auto`, `gpr_flat_write_stream`, `read_from_file` /
  `write_to_file`, the `Alloc` / `Create` pairs, `dng_stage1_negative`, and in
  tests `validate_dng_like`, `validate_raw`, `validate_rgb`,
  `tiff_parse_gain_maps`, `tiff_find_jpeg_preview`, `preview_cli_params`,
  `scratch_path`.
- Keep the diff readable: no drive-by reformatting, no unrelated renames, no
  whole-file reindentation. There is no `.clang-format`; the codec is
  tab-indented and the SDK space-indented, both deliberately.
- Do not report whitespace, brace or formatting nits at all, and do not flag
  style inside vendored directories.

## Code style: match the file you are in

Two dialects coexist. Follow whichever the file already uses.

- **Codec** (`vc5_*`): `PascalCase` functions, `ALL_CAPS` typedefs declared as
  `typedef struct _lower_name { ... } UPPER_NAME;`, tab indentation,
  `CODEC_ERROR` return codes.
- **SDK / public API** (`gpr_sdk`, `common`, `gpr_tools`): `snake_case`
  functions and types, anonymous `typedef struct { ... } gpr_thing;`, 4-space
  indentation, `bool` returns, `int` return codes in the tool (`0` = success).

Common to both: header guards as `#ifndef NAME_H` / `#define` / `#endif`; no
`#pragma once`; public headers wrap declarations in `extern "C"`; C++ stays
conservative (`NULL` not `nullptr`, no `auto`, no `std::unique_ptr`, no
in-house templates). Doxygen file headers (`/*! @file ... @brief ...`)
followed by the dual Apache/MIT license block. Comments explain *why*, with
the measurement that settled a number. Code comments and commit messages are
plain ASCII: write `->` and `--` rather than arrows or em dashes.

## Testing standards

There is one test file, `source/test/gpr_conversion_tests.cpp`, built as
target `gpr_tools_tests` and registered as the single ctest entry
`gpr_conversion_tests`. It uses a **hand-rolled harness: no gtest, no Catch2,
no golden images, no checksums.** New tests follow its patterns exactly.

- `run_case( "name", []{ ... } )` runs one case, forked on POSIX so a segfault
  is a failed case rather than a dead suite. Assertions are
  `check( cond, "message" )`, which records and continues. Case bodies are
  **capture-less lambdas** reading file-scope globals (`g_gpr`, `g_params`,
  `g_W`/`g_H`, `g_sample_path`, `g_cli_sample`, `g_cli_W`/`g_cli_H`) set up in
  the parent before the fork. `Buffer` and `RgbBuffer` are the RAII wrappers
  for SDK-allocated memory. `run_case(..., expect_fail=true)` marks a known
  broken path: XFAIL passes, XPASS fails the suite.
- New cases go inside the matching group function (`run_sample`,
  `run_preview_cli_tests`, `run_lens_correction_cli_tests`,
  `run_argument_parser_tests`, `run_flat_write_stream_tests`); a new group needs a call in `main()`.
  `file(GLOB)` picks up new `.cpp` files, which must not define `main()`.
- **Deterministic.** No `rand`, `time`, `clock`, sleeps, network, or
  file-system state beyond `TMPDIR`. Synthetic data comes from a fixed formula
  (`src[i] = (unsigned char)( ( i * 131 + 7 ) & 0xFF )`). Scratch files go
  through `scratch_path()` and are removed inside the same case; negative
  cases assert no file was written.
- **Assert exactness** through an independent ground truth rather than the
  code under test: the TIFF Compression tag read by hand and cross-checked
  against `gpr_check_vc5()`, byte-for-byte `memcmp`, file sizes that must grow
  with a finer quantizer. The suite has one tolerance (JPEG sizes within 10%
  where quantization noise makes exactness impossible). A test that mirrors
  the implementation's assumption is a defect, not coverage.
- Guard anything using tiny_jpeg with `#if GPR_JPEG_AVAILABLE`, since CI builds
  with it off. Adding a file to `samples[]` in `main()` also requires
  classifying it in the `expect_warp` list, which names the files by their
  upstream basenames (`GOPR2657.GPR`, `GPFR7066.GPR`, `GPBK7066.GPR`).
- Case names are `"<sample>: <api_name>"`, `"--flag: behavior"`, or
  `"subject: behavior"`; check messages are short lowercase statements of the
  expected state.

A PR touching the encoder, the DNG/TIFF writer, the `gpr_convert_*` matrix, a
`gpr_tools` option or a build flag adds or extends a case in the same PR. Pure
refactors that keep output byte-identical are the accepted exception and carry
that verification in the commit message.

## PR and commit conventions

Titles are imperative sentences describing the user-visible outcome, with an
optional `component:` prefix: `Restore the VC-5 encoder's default quality to
Filmscan-X`, `README: document --quality`.

Bodies follow a three-part shape, wrapped at about 72 columns in plain ASCII:

1. What was wrong and why it mattered, at mechanism level.
2. What the change does, as bullets, including the fallback or safety
   behaviour and anything that changes for existing callers.
3. Quantitative verification: `gpr_tools_tests` case count and result, the
   build-flag matrix, measured sizes or timings, and the byte-for-byte
   comparison against the previous build or against `gpraw/gpr` where output
   is expected to be identical.

A PR body also states whether the code commits were cherry-picked onto
`gpraw/gpr` and with what result, and confirms that the README "About this
fork" section was updated or did not need to be.
