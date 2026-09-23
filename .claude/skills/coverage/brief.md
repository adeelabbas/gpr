## Test coverage

Find code this change touches that lacks test coverage, and close the gap.
Scope: only behavior this change altered. Do not add coverage for unrelated
pre-existing gaps, and do not add sample files to data/samples: use the
samples the repository ships, or synthesize the input in the test itself.
Where CLAUDE.md says some fixtures live only in another repository, a case
that would need one degrades to what ships here, the way CLAUDE.md
describes.

The suite is one file, source/test/gpr_conversion_tests.cpp, with a
hand-rolled harness: run_case plus check, capture-less lambdas over
file-scope globals, fork-isolated cases. There is no gtest and there are no
golden images. Match the existing patterns exactly: add cases inside the
run_* group function they belong to (run_sample, run_preview_cli_tests,
run_lens_correction_cli_tests, run_argument_parser_tests,
run_flat_write_stream_tests, and the others main() calls). A brand-new
group function also needs a call added in main(). Name cases the way
neighboring cases are named.

Where CLAUDE.md says tests are written against one layer so that they
carry across to a repository kept in sync with this one, write them there
(adeelabbas/gpr: the gpr_tools conversion layer, dng_convert_main, rather
than the gpr_convert_* signatures, which differ downstream). A case that
only compiles in one of the two trees cannot be cherry-picked.

Assert exactly, against an independent ground truth rather than the code
path under test: byte-exact memcmp, a TIFF tag read by hand and
cross-checked against the public API, a file size that must grow with a
finer quantizer. Reuse validate_dng_like, validate_raw, validate_rgb,
tiff_parse_gain_maps, tiff_find_jpeg_preview, preview_cli_params,
scratch_path, and make_raw, make_dng, make_vc5 rather than writing a
parallel one. The suite has one tolerance, JPEG sizes within 10%, where
quantization noise makes exactness impossible; a new one needs a reason of
that kind, stated in a comment, and a bound a real regression lands far
outside. A test that mirrors the implementation's assumption is a defect,
not coverage.

Every test you write must be deterministic: no rand, no time or clock, no
sleeps, no dependence on file-system state, network, or environment beyond
TMPDIR. Generate synthetic data from a fixed formula; the existing idiom is
src[i] = (unsigned char)((i * 131 + 7) & 0xFF). Where the conversion calls
take a thread_count and an assertion must not depend on the machine's core
count, pass 1 explicitly rather than the suite default of 0. Route scratch
files through scratch_path() and std::remove them in the same case,
immediately after being read back. Negative cases assert no file was
written and remove it defensively. Guard anything using tiny_jpeg with
#if GPR_JPEG_AVAILABLE, since CI builds with it off.

Case strings are "<sample>: <api_name>", "--flag: behavior", or
"subject: behavior". Check messages are short lowercase statements of the
expected state. When the same fact is verified two ways, name the method in
parentheses.

Verify any test you write before you call it done, with the commands in
CLAUDE.md's "Build and test" section. The two gpr repositories spell the
configure and the build differently, and both build gpr_tools_tests.
gpraw/gpr:

  cmake -S . -B build
  cmake --build build --target gpr_tools_tests -j

adeelabbas/gpr:

  cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
  cmake --build build -j

Then run the suite binary directly, in either:

  ./build/source/test/gpr_tools_tests data/samples

It prints each case and, last, the tally, and exits non-zero when a case
fails. ctest --test-dir build --output-on-failure runs the same binary but
shows its output only when it fails, so a green ctest run has no tally to
quote.

build/ is already configured and built when an earlier run has been there,
and a new case then costs one incremental rebuild and a link. Single-config
Makefile and Ninja builds do not take -C; a multi-config generator (Xcode,
MSVC) needs the -C that CLAUDE.md names, and puts the binary under a
Release/ or Debug/ subdirectory. Do not run the build-flag matrix
(scripts/test_build_flags.sh): it is a configure and a build for every flag
configuration, and CI's build-flags.yml runs it on the pull request. Record
the suite's final tally line ("Cases run: N failed: 0 ..."); the report
quotes it.

A change under scripts/, .github/ or .claude/ alone, or a pure refactor that
keeps output byte-identical, owes no new case. Say which, and for a refactor
say what was checked instead of a tally.
