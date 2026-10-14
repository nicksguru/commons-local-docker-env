#############################################################################
# Unit-test suite for the version-comparison functions.
#
# Sourced exclusively by bin/check-image-versions, which invokes
# run_version_function_tests() at every startup - a broken version parser
# must never produce misleading version tables.
#
# Covers lib/version-functions.bash (extract_version_suffix, is_ubuntu_codename,
# normalize_version_for_comparison, extract_version_components, compare_semver,
# classify_component_update, detect_version_update, find_version_diff_start) and the script's own
# is_comparable_version (bash resolves function calls at call time, so the
# script's definition is available by the time the suite runs).
#
# Behavior:
# - silent on success (keeps the script's table output clean)
# - on failure, every failing case is printed to stderr (function, inputs,
#   expected vs actual) plus a summary line, and the runner returns 1
#
# Pure bash, no network, completes in milliseconds.
#############################################################################

# suite counters (global - incremented by the assert helpers)
declare -gi VFT_PASSED=0
declare -gi VFT_FAILED=0

#
# Asserts that the actual value equals the expected value and records the result.
#
# @param $1   function name under test (for failure messages)
# @param $2   rendered function inputs (for failure messages)
# @param $3   expected value
# @param $4   actual value
# @return     nothing (updates the global pass/fail counters)
#
function assert_equals() {
    local -r function_name=${1?Missing function_name}
    local -r inputs=${2?Missing inputs}
    local -r expected=${3?Missing expected}
    local -r actual=${4?Missing actual}

    if [[ "$expected" == "$actual" ]]; then
        VFT_PASSED=$((VFT_PASSED + 1))
    else
        VFT_FAILED=$((VFT_FAILED + 1))
        echo " FAIL $function_name($inputs): expected '$expected', actual '$actual'" >&2
    fi
}

#
# Asserts is_ubuntu_codename's verdict for a suffix.
#
# @param $1   suffix to check (with or without leading hyphen)
# @param $2   expected verdict: "true" or "false"
# @return     nothing (records pass/fail)
#
function assert_ubuntu_codename() {
    local -r suffix=${1?Missing suffix}
    local -r expected=${2?Missing expected}

    local actual="false"
    if is_ubuntu_codename "$suffix"; then
        actual="true"
    fi

    assert_equals "is_ubuntu_codename" "'$suffix'" "$expected" "$actual"
}

#
# Asserts compare_semver's verdict for a version pair.
#
# @param $1   first version
# @param $2   second version
# @param $3   expected verdict: "equal", "greater" (first > second), or "less" (second > first)
# @return     nothing (records pass/fail)
#
function assert_compare_semver() {
    local -r v1=${1?Missing v1}
    local -r v2=${2?Missing v2}
    local -r expected=${3?Missing expected}

    # capture the exit code without tripping 'set -e'
    local -i actual_code=0
    compare_semver "$v1" "$v2" || actual_code=$?

    # map the exit code to a readable verdict
    local actual="equal"
    if [[ $actual_code -eq 1 ]]; then
        actual="greater"
    elif [[ $actual_code -eq 2 ]]; then
        actual="less"
    elif [[ $actual_code -ne 0 ]]; then
        actual="unexpected exit code $actual_code"
    fi

    assert_equals "compare_semver" "'$v1' vs '$v2'" "$expected" "$actual"
}

#
# Asserts detect_version_update's classification for a current/latest version pair.
#
# @param $1   current version
# @param $2   latest version
# @param $3   expected update type: "none", "major", "minor", "patch", or "unknown"
# @return     nothing (records pass/fail)
#
function assert_version_update() {
    local -r current=${1?Missing current}
    local -r latest=${2?Missing latest}
    local -r expected=${3?Missing expected}

    local -r actual=$(detect_version_update "$current" "$latest")
    assert_equals "detect_version_update" "'$current' -> '$latest'" "$expected" "$actual"
}

#
# Asserts is_comparable_version's verdict for a candidate tag.
# is_comparable_version is defined in bin/check-image-versions itself; bash resolves
# it at call time, so it is available when the suite runs.
#
# @param $1   expected verdict: "accept" or "reject"
# @param $2   candidate version tag
# @param $3   current suffix for matching (empty string if none)
# @return     nothing (records pass/fail)
#
function assert_comparable() {
    local -r expected=${1?Missing expected}
    local -r version=${2?Missing version}
    local -r current_suffix=${3?Missing current_suffix}

    # capture the exit code without tripping 'set -e'
    local -i actual_code=0
    is_comparable_version "$version" "$current_suffix" || actual_code=$?

    # map the exit code to a readable verdict
    local actual="accept"
    if [[ $actual_code -ne 0 ]]; then
        actual="reject"
    fi

    assert_equals "is_comparable_version" "'$version', suffix '$current_suffix'" "$expected" "$actual"
}

#
# Asserts find_version_diff_start's verdict for an old/new version pair.
#
# @param $1   old version
# @param $2   new version
# @param $3   expected start index of the difference in $2, or "-1" for no highlight
# @return     nothing (records pass/fail)
#
function assert_diff_start() {
    local -r old=${1?Missing old}
    local -r new=${2?Missing new}
    local -r expected=${3?Missing expected}

    local -r actual=$(find_version_diff_start "$old" "$new")
    assert_equals "find_version_diff_start" "'$old' -> '$new'" "$expected" "$actual"
}

#
# Runs the full unit-test suite for the version-comparison functions.
#
# Silent on success. On failure, prints every failing case to stderr (function,
# inputs, expected vs actual) plus a summary line, and returns 1.
#
# @return     0 if all tests pass, 1 otherwise
#
function run_version_function_tests() {
    # reset counters so the suite can be re-run
    VFT_PASSED=0
    VFT_FAILED=0

    # the script (and only the script) defines is_comparable_version - fail fast otherwise
    if ! declare -F is_comparable_version >/dev/null; then
        echo "is_comparable_version is not defined - source this library from bin/check-image-versions" >&2
        return 1
    fi

    #########################################################################
    # extract_version_suffix
    #########################################################################
    assert_equals "extract_version_suffix" "'9.4.0'" "" "$(extract_version_suffix "9.4.0")"
    assert_equals "extract_version_suffix" "'8.3.1-noble'" "noble" "$(extract_version_suffix "8.3.1-noble")"
    assert_equals "extract_version_suffix" "'2.8.2-jre17'" "jre17" "$(extract_version_suffix "2.8.2-jre17")"
    assert_equals "extract_version_suffix" "'v1.2.3-alpine'" "alpine" "$(extract_version_suffix "v1.2.3-alpine")"
    assert_equals "extract_version_suffix" "'1.2.3-456-7'" "456-7" "$(extract_version_suffix "1.2.3-456-7")"
    assert_equals "extract_version_suffix" "'v2.8'" "" "$(extract_version_suffix "v2.8")"
    assert_equals "extract_version_suffix" "'pg18.4-ts2.29.0'" "" "$(extract_version_suffix "pg18.4-ts2.29.0")"
    assert_equals "extract_version_suffix" "'pg18-ts2.29.0'" "" "$(extract_version_suffix "pg18-ts2.29.0")"
    assert_equals "extract_version_suffix" "'pg18.4-ts2.29.0-all-oss'" "all-oss" "$(extract_version_suffix "pg18.4-ts2.29.0-all-oss")"
    assert_equals "extract_version_suffix" "'pg17.10-ts2.28.2-all-oss'" "all-oss" "$(extract_version_suffix "pg17.10-ts2.28.2-all-oss")"

    #########################################################################
    # is_ubuntu_codename
    #########################################################################
    assert_ubuntu_codename "noble" "true"
    assert_ubuntu_codename "trixie" "true"
    assert_ubuntu_codename "jammy" "true"
    assert_ubuntu_codename "focal" "true"
    assert_ubuntu_codename "-noble" "true"
    assert_ubuntu_codename "alpine" "false"
    assert_ubuntu_codename "oss" "false"
    assert_ubuntu_codename "all-oss" "false"
    assert_ubuntu_codename "jre17" "false"

    #########################################################################
    # normalize_version_for_comparison
    #########################################################################
    assert_equals "normalize_version_for_comparison" "'v1.2.3-alpine'" "1.2.3" "$(normalize_version_for_comparison "v1.2.3-alpine")"
    assert_equals "normalize_version_for_comparison" "'8.3.1-noble'" "8.3.1" "$(normalize_version_for_comparison "8.3.1-noble")"
    assert_equals "normalize_version_for_comparison" "'2.8.2-jre17'" "2.8.2" "$(normalize_version_for_comparison "2.8.2-jre17")"
    assert_equals "normalize_version_for_comparison" "'1.2.3-slim'" "1.2.3" "$(normalize_version_for_comparison "1.2.3-slim")"
    assert_equals "normalize_version_for_comparison" "'1.2.3-bookworm'" "1.2.3" "$(normalize_version_for_comparison "1.2.3-bookworm")"
    assert_equals "normalize_version_for_comparison" "'1.2.3-bullseye'" "1.2.3" "$(normalize_version_for_comparison "1.2.3-bullseye")"
    assert_equals "normalize_version_for_comparison" "'9.4.0'" "9.4.0" "$(normalize_version_for_comparison "9.4.0")"
    assert_equals "normalize_version_for_comparison" "'v2.8'" "2.8" "$(normalize_version_for_comparison "v2.8")"
    assert_equals "normalize_version_for_comparison" "'pg18.4-ts2.29.0'" "pg18.4-ts2.29.0" "$(normalize_version_for_comparison "pg18.4-ts2.29.0")"
    assert_equals "normalize_version_for_comparison" "'pg18.4-ts2.29.0-all-oss'" "pg18.4-ts2.29.0" "$(normalize_version_for_comparison "pg18.4-ts2.29.0-all-oss")"

    #########################################################################
    # extract_version_components
    #########################################################################
    assert_equals "extract_version_components" "'1.2.3'" "semver:1:2:3" "$(extract_version_components "1.2.3")"
    assert_equals "extract_version_components" "'2.8'" "semver:2:8:0" "$(extract_version_components "2.8")"
    assert_equals "extract_version_components" "'v2.8'" "semver:2:8:0" "$(extract_version_components "v2.8")"
    assert_equals "extract_version_components" "'8.0.1-noble'" "semver:8:0:1" "$(extract_version_components "8.0.1-noble")"
    assert_equals "extract_version_components" "'pg18.4-ts2.29.0'" "timescaledb:18.4:2.29.0" "$(extract_version_components "pg18.4-ts2.29.0")"
    assert_equals "extract_version_components" "'pg18.4-ts2.29.0-all-oss'" "timescaledb:18.4:2.29.0" "$(extract_version_components "pg18.4-ts2.29.0-all-oss")"
    assert_equals "extract_version_components" "'pg18-ts2.29.0'" "timescaledb:18:2.29.0" "$(extract_version_components "pg18-ts2.29.0")"
    assert_equals "extract_version_components" "'pg19.0-ts2.29.0'" "timescaledb:19.0:2.29.0" "$(extract_version_components "pg19.0-ts2.29.0")"
    assert_equals "extract_version_components" "'20260324'" "date:20260324" "$(extract_version_components "20260324")"
    assert_equals "extract_version_components" "'144'" "numeric:144" "$(extract_version_components "144")"
    assert_equals "extract_version_components" "'v1.2.3-beta'" "unknown:1.2.3-beta" "$(extract_version_components "v1.2.3-beta")"

    #########################################################################
    # compare_semver
    #########################################################################
    assert_compare_semver "1.2.3" "1.2.3" "equal"
    assert_compare_semver "5" "5" "equal"
    assert_compare_semver "18.4" "18.4" "equal"
    assert_compare_semver "2.09" "2.9" "equal" # leading zeros are ignored
    assert_compare_semver "1.2.4" "1.2.3" "greater"
    assert_compare_semver "2.0" "1.9.9" "greater"
    assert_compare_semver "2.29.1" "2.29.0" "greater"
    assert_compare_semver "18.4" "18" "greater" # missing components count as zero
    assert_compare_semver "7" "5" "greater"
    assert_compare_semver "1.2.3" "1.2.4" "less"
    assert_compare_semver "1.9.9" "2.0" "less"
    assert_compare_semver "18" "18.4" "less"
    assert_compare_semver "5" "7" "less"

    #########################################################################
    # classify_component_update
    #########################################################################
    assert_equals "classify_component_update" "'18.4' vs '19.0'" "major" "$(classify_component_update "18.4" "19.0")"
    assert_equals "classify_component_update" "'18' vs '19'" "major" "$(classify_component_update "18" "19")"
    assert_equals "classify_component_update" "'18.4' vs '18.5'" "minor" "$(classify_component_update "18.4" "18.5")"
    assert_equals "classify_component_update" "'18' vs '18.4'" "minor" "$(classify_component_update "18" "18.4")"
    assert_equals "classify_component_update" "'2.28.0' vs '2.29.0'" "minor" "$(classify_component_update "2.28.0" "2.29.0")"
    assert_equals "classify_component_update" "'2.29.0' vs '2.29.1'" "patch" "$(classify_component_update "2.29.0" "2.29.1")"
    assert_equals "classify_component_update" "'1.2.3.4' vs '1.2.3.5'" "patch" "$(classify_component_update "1.2.3.4" "1.2.3.5")"
    assert_equals "classify_component_update" "'2.29.0' vs '2.29.0'" "none" "$(classify_component_update "2.29.0" "2.29.0")"
    assert_equals "classify_component_update" "'2.29.1' vs '2.29.0'" "none" "$(classify_component_update "2.29.1" "2.29.0")"
    assert_equals "classify_component_update" "'2.0' vs '1.9'" "none" "$(classify_component_update "2.0" "1.9")"

    #########################################################################
    # find_version_diff_start
    #########################################################################
    assert_diff_start "1.2.1" "1.3.0" 2 # highlights "3.0"
    assert_diff_start "16.4" "17.0" 0 # highlights "17.0", not "7.0"
    assert_diff_start "12.1" "13.1" 0 # highlights "13.1", not "3.1"
    assert_diff_start "2.29.0" "2.30.0" 2 # highlights "30.0"
    assert_diff_start "2.9.0" "2.10.0" 2 # highlights "10.0"
    assert_diff_start "2.29.0" "2.29.1" 5 # highlights "1"
    assert_diff_start "144" "145" 0 # numeric versions: a single number is one numeric run
    assert_diff_start "20260324" "20260325" 0 # date-based versions: same, the whole date is one run
    assert_diff_start "8.0.1-noble" "8.0.2-trixie" 4 # suffix change included
    assert_diff_start "8.0.1-noble" "8.0.1-trixie" 6 # only the codename changed
    assert_diff_start "pg17.10-ts2.28.2" "pg18.4-ts2.29.0" 2 # highlights "18.4-ts2.29.0"
    assert_diff_start "pg18.4-ts2.29.0" "pg18.4.1-ts2.29.0" 6 # the inserted '.' is not a digit, so no backup
    assert_diff_start "1.2.3" "1.2.3.4" 5 # appended component
    assert_diff_start "1.2.3" "1.2.3" -1 # equal - nothing to highlight
    assert_diff_start "1.2.3.4" "1.2.3" -1 # nothing added

    #########################################################################
    # detect_version_update - TimescaleDB pg/ts matrix
    #########################################################################
    # pg part bumps (takes precedence over the ts part)
    assert_version_update "pg18.4-ts2.29.0" "pg19.0-ts2.29.0" "major" # pg major
    assert_version_update "pg18.4-ts2.29.0" "pg18.5-ts2.29.0" "minor" # pg minor
    assert_version_update "pg18.4.1-ts2.29.0" "pg18.4.2-ts2.29.0" "patch" # pg patch
    # ts part bumps (pg unchanged): ts major/minor collapse to 'minor', ts patch stays 'patch'
    assert_version_update "pg18.4-ts2.29.0" "pg18.4-ts2.29.1" "patch"
    assert_version_update "pg18.4-ts2.28.0" "pg18.4-ts2.29.0" "minor"
    assert_version_update "pg18.4-ts1.29.0" "pg18.4-ts2.29.0" "minor"
    # equal and downgrade
    assert_version_update "pg18.4-ts2.29.0" "pg18.4-ts2.29.0" "none"
    assert_version_update "pg18.4-ts2.29.0" "pg18.4-ts2.29.0-all-oss" "none" # suffix-only difference
    assert_version_update "pg18.4-ts2.29.1" "pg18.4-ts2.29.0" "none" # ts downgrade
    assert_version_update "pg19.0-ts2.29.0" "pg18.4-ts2.29.0" "none" # pg downgrade
    # suffixed and short-component variants
    assert_version_update "pg18.4-ts2.29.0-all-oss" "pg18.4-ts2.29.1-all-oss" "patch"
    assert_version_update "pg18-ts2.29.0" "pg18-ts2.29.1" "patch"
    # cross-PG updates with the same TS version (different PG versions bundle the same TS version)
    assert_version_update "pg17.10-ts2.29.0" "pg18.4-ts2.29.0" "major" # pg major, same ts
    assert_version_update "pg17.10-ts2.29.0" "pg17.11-ts2.29.0" "minor" # pg minor, same ts
    assert_version_update "pg17.10.0-ts2.29.0" "pg17.10.1-ts2.29.0" "patch" # pg patch, same ts
    # the pg part wins over the ts part
    assert_version_update "pg18.0-ts2.29.0" "pg17.99-ts2.99.0" "none" # ts bump cannot offset a pg downgrade
    assert_version_update "pg17.99-ts2.99.0" "pg18.0-ts2.29.0" "major" # pg bump wins over a ts downgrade
    assert_version_update "pg18.4-ts2.29.0" "pg17.10-ts2.31.0" "none" # pg downgrade despite a newer ts

    #########################################################################
    # sort -V - pg/ts tags order by PG first, then TS (picks the latest tag)
    #########################################################################
    local -r pg_ts_sorted=$(printf '%s\n' pg18.4-ts2.29.1 pg17.99-ts2.99.0 pg18.4-ts2.29.0 pg17.10-ts2.29.0 | sort -V | paste -sd' ' -)
    assert_equals "sort -V" "pg/ts tags" "pg17.10-ts2.29.0 pg17.99-ts2.99.0 pg18.4-ts2.29.0 pg18.4-ts2.29.1" "$pg_ts_sorted"

    #########################################################################
    # detect_version_update - plain versions
    #########################################################################
    assert_version_update "16.4" "17.0" "major"
    assert_version_update "16.4" "16.5" "minor"
    assert_version_update "16.4.1" "16.4.2" "patch"
    assert_version_update "16.4" "16.4" "none"
    assert_version_update "16.5" "16.4" "none" # downgrade
    assert_version_update "8.0.1" "8.0.2" "patch"
    assert_version_update "2.8" "2.9" "minor"
    assert_version_update "20260324" "20260325" "major" # date-based
    assert_version_update "144" "145" "major" # numeric
    assert_version_update "16.4" "20260324" "unknown" # type mismatch
    assert_version_update "1.2.3" "1.2.3.4" "unknown" # 4-component version is unknown

    #########################################################################
    # is_comparable_version - accept matrix
    #########################################################################
    assert_comparable "accept" "16.4" ""
    assert_comparable "accept" "16.4.1" ""
    assert_comparable "accept" "v1.2.3" ""
    assert_comparable "accept" "8.0.2-noble" "noble" # exact suffix match
    assert_comparable "accept" "8.0.2-trixie" "noble" # codename-to-codename update allowed
    assert_comparable "accept" "2.9-jre17" "jre17"
    assert_comparable "accept" "v1.2.3-alpine" "alpine"
    assert_comparable "accept" "1.2.3-456-7" "456-7" # multi-hyphen suffix matches exactly
    assert_comparable "accept" "pg18.4-ts2.29.1" ""
    assert_comparable "accept" "pg18.4-ts2.29.1-all-oss" "all-oss"
    assert_comparable "accept" "pg17.10-ts2.28.2-all-oss" "all-oss"
    assert_comparable "accept" "pg18.4-ts2.29.0-all-oss" "all-oss" # cross-PG candidate (current pg17.10-ts2.28.2-all-oss): the pg part is not exact-matched
    assert_comparable "accept" "20260325" "" # date-based
    assert_comparable "accept" "145" "" # numeric

    #########################################################################
    # is_comparable_version - reject matrix
    #########################################################################
    assert_comparable "reject" "nightly" ""
    assert_comparable "reject" "latest" ""
    assert_comparable "reject" "alpine" "" # standalone codename-ish tags
    assert_comparable "reject" "noble" ""
    assert_comparable "reject" "trixie" ""
    assert_comparable "reject" "1.2.3-beta" "" # pre-releases
    assert_comparable "reject" "1.2.3-alpha1" ""
    assert_comparable "reject" "1.2.3-rc1" ""
    assert_comparable "reject" "1.2.3-Windows" "" # platform tags (case-insensitive)
    assert_comparable "reject" "1.2.3-amd64" ""
    assert_comparable "reject" "1.2.3-arm64" ""
    assert_comparable "reject" "1.2.3-ppc64le" ""
    assert_comparable "reject" "1.2.3-alpine" "" # suffix mismatch: candidate has suffix, current has none
    assert_comparable "reject" "1.2.3" "alpine" # suffix mismatch: current has suffix, candidate has none
    assert_comparable "reject" "1.2.3-alpine" "noble" # non-codename suffixes must match exactly
    assert_comparable "reject" "1.2.3-jre17" "jre18"
    assert_comparable "reject" "1.2.3-noble" "jre17" # codename current requires codename candidate
    assert_comparable "reject" "pg18.4-ts2.29.1-all-oss" "" # pg/ts suffix mismatch
    assert_comparable "reject" "pg18.4-ts2.29.1" "all-oss"
    assert_comparable "reject" "pg18.4-ts2.29.1-oss" "all-oss" # '-oss' must not mix with '-all-oss'
    assert_comparable "reject" "pg18.4-ts2.29.1-oss" ""

    # report failures only - success stays silent to keep the table output clean
    local -ri total=$((VFT_PASSED + VFT_FAILED))
    if [[ $VFT_FAILED -gt 0 ]]; then
        echo "$VFT_FAILED/$total unit tests failed" >&2
        return 1
    fi

    return 0
}
