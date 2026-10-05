#!/usr/bin/env bash
# Source-integrity check for the HarfBuzz SDK.
#
# Four questions, all answerable without a compiler:
#
#   1. Do the 932 vendored upstream files still hash to the digests
#      UPSTREAM.sha256 records?
#   2. Is the vendored file set exactly that set -- no missing, extra or renamed
#      file under src/, docs/ or test/, and nothing unrecorded dropped at the
#      top level? A plain checksum run cannot see an addition.
#   3. Is UPSTREAM.sha256 still an upstream-only manifest? A fork-owned file in
#      it would turn a provenance record into a record of this fork's own work.
#   4. Are the licence grants still where the records say they are -- the Old
#      MIT text in COPYING, the Microsoft grant for src/ms-use, the SIL Open Font
#      License for the corpus under test/, and this fork's own grant in
#      FORK-LICENSE.md?
#
# This is a provenance gate, not a build gate. Nothing here compiles, links or
# runs a target binary; it is the check that an edit to the canonical native
# source cannot pass as a routine change.
#
# It does not check the *release* tarball digest against the bytes of the
# tarball: that file is 20 MB and is not vendored here. UPSTREAM.md records
# where that digest was read from and when, and re-fetching the release is the
# driver's call, not this script's.
#
# Usage: tools/check-provenance.sh   (run from anywhere in the repository)
#
# SPDX-License-Identifier: MIT

set -euo pipefail

cd "$(dirname "$0")/.."

# One locale for the whole script, and it is C. `sort` and `comm` have to agree
# on an order to compare two lists at all, and a caller that exported a
# UTF-8 locale would otherwise make the file-set comparison depend on it.
export LC_ALL=C

fail() {
    echo "$1" >&2
    exit 1
}

# The upstream top-level files this tree carries, and nothing else. Anything
# else at the top level is this fork's own work and must not be in the
# manifest; anything here must be.
upstream_top_level=(
    .clang-format
    .editorconfig
    AUTHORS
    AVAR2-INSTANCING.md
    BUILD.md
    CODE_OF_AI_CONDUCT.md
    CONFIG.md
    COPYING
    NEWS
    README.upstream.md
    RELEASING.md
    SECURITY.md
    TESTING.md
    THANKS
)

# 1. Bytes.
sha256sum -c --quiet UPSTREAM.sha256 || fail "an upstream file no longer matches UPSTREAM.sha256"
manifest_paths=$(awk '/^[0-9a-f]{64}  / { print $2 }' UPSTREAM.sha256)
recorded=$(printf '%s\n' "$manifest_paths" | grep -c .)
echo "all $recorded upstream files match UPSTREAM.sha256"

# 2a. No extra file under a recorded tree. An upstream file added without a
#     digest here is the shape of an unrecorded patch.
expected_tree=$(printf '%s\n' "$manifest_paths" | grep -E '^(src|docs|test)/' | LC_ALL=C sort)
actual_tree=$(find src docs test -type f | LC_ALL=C sort)
if [ "$expected_tree" != "$actual_tree" ]; then
    echo "the vendored file set differs from the recorded one:" >&2
    diff -u <(echo "$expected_tree") <(echo "$actual_tree") >&2 || true
    echo >&2
    echo "An intentional change to the native source needs an observed failure, a" >&2
    echo "small causal patch, an explicit per-file deviation record in NOTICE.md," >&2
    echo "updated digests here, and a CHANGELOG.md entry in the same change." >&2
    exit 1
fi
echo "the vendored file set is exactly the recorded $(echo "$expected_tree" | wc -l) files"

# 2b. The top level. The manifest must hold exactly these names, and every other
#     entry here must be fork-owned work that a reviewer can see by name.
expected_top=$(printf '%s\n' "${upstream_top_level[@]}" | LC_ALL=C sort)
recorded_top=$(printf '%s\n' "${upstream_top_level[@]}" | while read -r name; do
    grep -q "  $name\$" UPSTREAM.sha256 || echo "MISSING FROM MANIFEST: $name"
done)
[ -z "$recorded_top" ] || { echo "$recorded_top" >&2; fail "a recorded upstream file is absent from UPSTREAM.sha256"; }

actual_top=$(find . -maxdepth 1 -type f -printf '%f\n' | LC_ALL=C sort)
unrecorded_top=$(comm -13 <(printf '%s\n' "$expected_top") <(printf '%s\n' "$actual_top"))
echo "the top-level upstream files are all in the manifest"
echo "fork-owned files present at the top level (not upstream, no digest):"
echo "$unrecorded_top" | sed 's/^/  /'

# Is a path recorded in the manifest? Matched against `manifest_paths`, captured
# once above, rather than through `awk '/^[0-9a-f]{64}  / { print $2 }'
# UPSTREAM.sha256 | grep -qx "$path"`. Under `set -o pipefail` that pipeline is a
# race: `grep -q` exits on its first match, awk's next write raises SIGPIPE, and
# the pipeline's status becomes 141. As a positive assertion that is a false
# "not covered" -- measured, 27 failures out of 60 trials on an untouched
# manifest, all four digests already matched. As a negative assertion (below)
# the same race hides a real finding. A herestring has no pipe to close, so the
# exit status is grep's alone.
manifest_has() {
    grep -qx "$1" <<< "$manifest_paths"
}

# 3. The manifest is upstream-only.
for fork_path in build.zig build.zig.zon cross-test.profile.sh zig/root.zig zig/translate.h runtime/library.zig tests.zig smoke.zig tools/check-provenance.sh consumer/build.zig; do
    if manifest_has "$fork_path"; then
        fail "UPSTREAM.sha256 records a fork-owned file ($fork_path)"
    fi
done
echo "the manifest records no fork-owned file"

# 4a. The release digest must be recorded identically in both records, so the
#     two files cannot disagree about which upstream release this is.
# `-m1` rather than a pipe into `head -1`: with `pipefail` a `head` that closes
# the pipe early sends SIGPIPE to grep and turns a successful match into a
# failed pipeline.
digest_md=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.md)
digest_list=$(grep -m1 -oE '[0-9a-f]{64}' UPSTREAM.sha256)
[ -n "$digest_md" ] || fail "UPSTREAM.md records no sha256 digest"
[ -n "$digest_list" ] || fail "UPSTREAM.sha256 records no sha256 digest"
[ "$digest_md" = "$digest_list" ] ||
    fail "UPSTREAM.md and UPSTREAM.sha256 name different release digests"
echo "the release digest is recorded consistently: $digest_md"

# 4b. The compiled core's own grant, in the file that carries it.
grep -q 'HarfBuzz is licensed under the so-called "Old MIT" license' COPYING ||
    fail "the Old MIT statement is missing from COPYING"
grep -q 'Google, Inc.' COPYING ||
    fail "upstream's copyright notices are missing from COPYING"
for file in NOTICE.md FORK-LICENSE.md; do
    grep -q 'Google, Inc.' "$file" ||
        fail "upstream's copyright notice is missing from $file"
done
grep -q 'THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND' FORK-LICENSE.md ||
    fail "FORK-LICENSE.md does not reproduce the permission and warranty text"
echo "the Old MIT grant is present in COPYING and in the records"

# 4c. The per-file exceptions this tree actually ships. COPYING:2-3 says parts
#     of HarfBuzz are under other licenses and names a per-directory COPYING;
#     there are exactly two of them, and a tree that grows a third must fail
#     here rather than be summarised as one licence.
#
#     Build output is pruned, using the same `-name .zig-cache -o -name zig-out
#     -prune` form the workspace's other checkers use (see
#     predicates/tools/check-provenance.sh and mpfr/tools/check-upstream-baseline.sh).
#     `zig build` installs a copy of this package's own COPYING to
#     `zig-out/share/licenses/harfbuzz/COPYING`, so an unpruned walk counted an
#     installed third copy of the top-level licence as a fourth per-directory
#     exception and failed on a tree with exactly the two it documents. What is
#     counted is what the source tree carries; `zig-out/` is build output and
#     `.gitignore` already excludes it from the package.
[ "$(find . \( -name .git -o -name .zig-cache -o -name zig-out \) -prune -o -name COPYING -type f -print | wc -l)" -eq 3 ] ||
    fail "the tree no longer has exactly three COPYING files; NOTICE.md must record the new one"
grep -q 'Copyright (c) Microsoft Corporation.' src/ms-use/COPYING ||
    fail "the Microsoft grant for src/ms-use is missing"
grep -q 'src/ms-use' NOTICE.md ||
    fail "NOTICE.md does not record the src/ms-use exception"
grep -q 'SIL OPEN FONT LICENSE Version 1.1' test/COPYING ||
    fail "the SIL Open Font License for the test corpus is missing"
grep -q 'test/COPYING' NOTICE.md ||
    fail "NOTICE.md does not record the test corpus licence"
echo "both per-directory exceptions are present and recorded"

# 4d. The oracle this package's tests hold themselves to must itself be covered
#     by the manifest: a recorded expectation that nothing checks the bytes of
#     is an expectation that can drift.
#
for fixture in \
    test/shape/data/in-house/tests/harfbust.tests \
    test/shape/data/in-house/tests/digits.tests \
    test/shape/data/in-house/fonts/HarfBust.ttf \
    test/shape/data/in-house/fonts/3b791518a9ba89675df02f1eefbc9026a50648a6.ttf
do
    manifest_has "$fixture" ||
        fail "the oracle fixture $fixture is not covered by UPSTREAM.sha256"
done
echo "the shaping oracle and both of its fonts are covered by the manifest"

# 4e. Upstream's README is preserved beside this fork's own, and the fork's
#     front page is not upstream's. `README.upstream.md` is the imported
#     original and `sha256sum -c` above already checks its bytes, so what is
#     left is the *naming* claim: the preserved copy must still be upstream's
#     own heading, and the manifest must record it under that name rather than
#     under the fork's README.md.
grep -q '^# HarfBuzz' README.upstream.md ||
    fail "README.upstream.md no longer carries upstream's own HarfBuzz heading"
manifest_has 'README.upstream.md' ||
    fail "UPSTREAM.sha256 does not record README.upstream.md"
if manifest_has 'README.md'; then
    fail "UPSTREAM.sha256 still records README.md, which is this fork's own file now"
fi
[ -f README.zig.md ] || fail "README.zig.md, this fork's Zig-facing document, is missing"
echo "README.upstream.md is upstream's own README and README.md is this fork's"

echo "provenance checks passed"