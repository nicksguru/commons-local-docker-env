#
# Extracts optional suffix from version tag. The suffix is everything after the first hyphen.
# Example:
#   "8.3.1-noble"   →  "noble"
#   "2.8.2-jre17"   →  "jre17"
#   "9.4.0"         →  ""
#   "1.2.3-456-7"   →  "456-7"
#   "v1.2.3-alpine" →  "alpine"
#
# TimescaleDB tags are handled specially because their first hyphen separates the PostgreSQL and
# TimescaleDB version parts rather than the suffix:
#   "pg18.4-ts2.29.0"          →  ""
#   "pg18.4-ts2.29.0-all-oss"  →  "all-oss"
#
# @param $1   version string to extract suffix from
# @return     suffix without leading hyphen, or empty string if no suffix
#
function extract_version_suffix() {
    local -r version=${1?Missing version}

    # TimescaleDB format pg<PgVersion>-ts<TsVersion>: both the PG and TS versions take part in
    # comparison (PG first, then TS), so the suffix is only what follows the TS version
    if [[ "$version" =~ ^pg[0-9]+(\.[0-9]+)*-ts[0-9]+(\.[0-9]+)*(-(.+))?$ ]]; then
        echo "${BASH_REMATCH[4]}"
        return
    fi

    # extract suffix after FIRST hyphen ('##' would match LAST hyphen)
    if [[ "$version" =~ - ]]; then
      local -r suffix="${version#*-}"
      echo "$suffix"
    else
      echo ""
    fi
}

#
# Checks if a suffix is an Ubuntu codename.
# Example:
#   "noble"  → 0 (true)
#   "trixie" → 0 (true)
#   "jammy"  → 0 (true)
#   "alpine" → 1 (false)
#   "jre17"  → 1 (false)
#
# @param $1   suffix string to check (with or without leading hyphen)
# @return (in $?): 0 (true) if suffix is a valid Ubuntu codename, 1 (false) otherwise
#
function is_ubuntu_codename() {
    local -r suffix=${1?Missing suffix}
    # remove leading hyphen for checking
    local -r check_suffix="${suffix#-}"

    # common Ubuntu codenames plus Debian 'trixie' (also used as an image tag suffix)
    local codenames="noble|trixie|jammy|focal|bionic|xenial|trusty|precise|oneiric|natty|maverick|lucid|karmic|jaunty|intrepid|hardy|gutsy|feisty|edgy|dapper|breezy|warty"

    if [[ "$check_suffix" =~ ^($codenames)$ ]]; then
        return 0
    fi

    return 1
}

#
# Extracts version components for comparison.
# Format: "type:component1:component2:...".
# Types: semver, postgres, date, numeric, unknown
# Example:
#   "1.2.3"           → "semver:1:2:3"
#   "pg18.3-ts2.26.4" → "timescaledb:18.3:2.26.4"
#   "20260324"        → "date:20260324"
#   "144"             → "numeric:144"
#   "v2.8"            → "semver:2:8:0"
#
# @param $1   version string to parse
# @return     colon-separated type and components
#
function extract_version_components() {
    local -r version=${1?Missing version}
    local -r normalized=$(normalize_version_for_comparison "$version")

    # handle special cases like pg18.3-ts2.26.4 (component counts may vary, e.g. pg18-ts2.29.0)
    if [[ $normalized =~ ^pg([0-9]+(\.[0-9]+)*)-ts([0-9]+(\.[0-9]+)*) ]]; then
        echo "timescaledb:${BASH_REMATCH[1]}:${BASH_REMATCH[3]}"
        return
    fi

    # date-based versions like 20260324
    if [[ $normalized =~ ^[0-9]{8}$ ]]; then
        echo "date:$normalized"
        return
    fi

    # simple numeric versions like 144
    if [[ $normalized =~ ^[0-9]+$ ]]; then
        echo "numeric:$normalized"
        return
    fi

    # standard semantic versions
    if [[ $normalized =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
        echo "semver:${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:${BASH_REMATCH[3]}"
        return
    fi

    # versions with major.minor only
    if [[ $normalized =~ ^([0-9]+)\.([0-9]+)$ ]]; then
        echo "semver:${BASH_REMATCH[1]}:${BASH_REMATCH[2]}:0"
        return
    fi

    echo "unknown:$normalized"
}

#
# Compares two dot-separated version numbers.
# Example:
#   "1.2.3" "1.2.3" → 0 (equal)
#   "1.2.4" "1.2.3" → 1 (first > second)
#   "1.2.3" "1.2.4" → 2 (second > first)
#   "2.0"   "1.9.9" → 1 (first > second)
#
# @param $1 First version number to compare
# @param $2 Second version number to compare
# @return 0 = equal, 1 = first > second, 2 = second > first
#
function compare_semver() {
    local -r v1=$1
    local -r v2=$2

    if [[ "$v1" == "$v2" ]]; then
        return 0
    fi

    # split by dots and compare each component (quoted assignment would NOT split, so use 'read')
    local -a parts1 parts2
    local IFS='.'
    read -r -a parts1 <<< "$v1"
    read -r -a parts2 <<< "$v2"

    # get the maximum length
    local max_len=${#parts1[@]}
    if [[ ${#parts2[@]} -gt $max_len ]]; then
        max_len=${#parts2[@]}
    fi

    # compare each component
    local -i i
    for ((i=0; i<max_len; i++)); do
        local p1=${parts1[$i]:-0}
        local p2=${parts2[$i]:-0}

        # remove leading zeros for numeric comparison
        p1=$((10#$p1))
        p2=$((10#$p2))

        if [[ $p1 -gt $p2 ]]; then
            return 1
        elif [[ $p1 -lt $p2 ]]; then
            return 2
        fi
    done

    return 0
}

#
# Classifies the update type between two dot-separated numeric versions by the position of the
# first differing component: first component → "major", second → "minor", any later → "patch".
# A downgrade or equal versions yield "none".
# Example:
#   "18.4"   "19.0"   → "major"
#   "18.4"   "18.5"   → "minor"
#   "2.29.0" "2.29.1" → "patch"
#   "2.29.0" "2.29.0" → "none"
#   "2.29.1" "2.29.0" → "none" (downgrade)
#
# @param $1   current version components (dot-separated)
# @param $2   latest version components (dot-separated)
# @return     update type: "major", "minor", "patch", or "none" (equal or downgrade)
#
function classify_component_update() {
    local -r current=${1?Missing current}
    local -r latest=${2?Missing latest}

    # split into component arrays ('.' as delimiter)
    local -a current_parts latest_parts
    local IFS='.'
    read -r -a current_parts <<< "$current"
    read -r -a latest_parts <<< "$latest"

    # the longer component list wins if one is a prefix of the other (e.g. "18" vs "18.4")
    local -i max_len=${#current_parts[@]}
    if [[ ${#latest_parts[@]} -gt $max_len ]]; then
        max_len=${#latest_parts[@]}
    fi

    # find the first differing component - its position determines the update type
    local -i i
    for ((i=0; i<max_len; i++)); do
        # missing components count as zero
        local p1=${current_parts[$i]:-0}
        local p2=${latest_parts[$i]:-0}

        # remove leading zeros for numeric comparison
        p1=$((10#$p1))
        p2=$((10#$p2))

        if [[ $p2 -gt $p1 ]]; then
            case $i in
                0) echo "major" ;;
                1) echo "minor" ;;
                *) echo "patch" ;;
            esac
            return
        elif [[ $p2 -lt $p1 ]]; then
            # downgrade
            echo "none"
            return
        fi
    done

    echo "none"
}

#
# Compares two version strings and determines the type of update.
# Example:
#   "1.2.3" "1.2.3"   → "none"
#   "1.2.3" "2.0.0"   → "major"
#   "1.2.3" "1.3.0"   → "minor"
#   "1.2.3" "1.2.4"   → "patch"
#   "1.2.3" "1.2.3.4" → "unknown"
#
# @param $1   current version string
# @param $2   latest version string
# @return     update type: "none", "major", "minor", "patch", "unknown"
#
function detect_version_update() {
    local current=$1
    local latest=$2

    local -r current_parts=$(extract_version_components "$current")
    local -r latest_parts=$(extract_version_components "$latest")

    local -r current_type=$(echo "$current_parts" | cut -d: -f1)
    local -r latest_type=$(echo "$latest_parts" | cut -d: -f1)

    # if versions are identical
    if [[ "$current" == "$latest" ]]; then
        echo "none"
        return
    fi

    # handle different version types
    if [[ "$current_type" != "$latest_type" ]]; then
        echo "unknown"
        return
    fi

    case "$current_type" in
        "semver")
            local -r current_major=$(echo "$current_parts" | cut -d: -f2)
            local -r current_minor=$(echo "$current_parts" | cut -d: -f3)
            local -r current_patch=$(echo "$current_parts" | cut -d: -f4)

            local -r latest_major=$(echo "$latest_parts" | cut -d: -f2)
            local -r latest_minor=$(echo "$latest_parts" | cut -d: -f3)
            local -r latest_patch=$(echo "$latest_parts" | cut -d: -f4)

            # check if this is an upgrade (latest > current)
            compare_semver "$latest_major" "$current_major"
            local major_cmp=$?

            compare_semver "$latest_minor" "$current_minor"
            local minor_cmp=$?

            compare_semver "$latest_patch" "$current_patch"
            local patch_cmp=$?

            # determine if it's an upgrade
            if [[ $major_cmp -eq 1 ]]; then
                echo "major"
            elif [[ $major_cmp -eq 0 && $minor_cmp -eq 1 ]]; then
                echo "minor"
            elif [[ $major_cmp -eq 0 && $minor_cmp -eq 0 && $patch_cmp -eq 1 ]]; then
                echo "patch"
            # either downgrade or unknown
            else
                echo "none"
            fi
            ;;

        # Docker image (PostgreSQL + TimescaleDB extension), format: pg<PgVersion>-ts<TsVersion>.
        # Both parts are compared - the PostgreSQL part first, the TimescaleDB part only when the
        # PG parts are equal (different PG versions like 17 and 18 bundle the same TS version):
        # - pg major bump → "major", pg minor bump → "minor", pg patch bump → "patch"
        # - pg downgrade → "none" (a ts bump cannot offset an older pg part)
        # - if pg is unchanged, a ts major/minor bump → "minor", a ts patch bump → "patch"
        "timescaledb")
            local -r current_pg=$(echo "$current_parts" | cut -d: -f2)
            local -r current_ts=$(echo "$current_parts" | cut -d: -f3)
            local -r latest_pg=$(echo "$latest_parts" | cut -d: -f2)
            local -r latest_ts=$(echo "$latest_parts" | cut -d: -f3)

            # PostgreSQL part orders first - a pg bump classifies the update by itself
            local -i pg_cmp=0
            compare_semver "$latest_pg" "$current_pg" || pg_cmp=$?
            if [[ $pg_cmp -eq 1 ]]; then
                local pg_update
                pg_update=$(classify_component_update "$current_pg" "$latest_pg")
                echo "$pg_update"
                return
            fi

            # pg downgrade - the ts part cannot offset an older pg part
            if [[ $pg_cmp -eq 2 ]]; then
                echo "none"
                return
            fi

            # PostgreSQL unchanged - classify by the TimescaleDB extension part
            local ts_update
            ts_update=$(classify_component_update "$current_ts" "$latest_ts")
            case "$ts_update" in
                "major" | "minor") echo "minor" ;;
                *)                 echo "$ts_update" ;;
            esac
            ;;

        "date")
            if [[ "$latest" -gt "$current" ]]; then
                echo "major"
            else
                echo "none"
            fi
            ;;

        "numeric")
            if [[ "$latest" -gt "$current" ]]; then
                echo "major"
            else
                echo "none"
            fi
            ;;

        *)
            echo "unknown"
            ;;
    esac
}

#
# Normalizes version string for comparison by removing common suffixes.
# Example:
#   "v1.2.3-alpine" → "1.2.3"
#   "8.3.1-noble"   → "8.3.1"
#   "2.8.2-jre17"   → "2.8.2"
#   "9.4.0"         → "9.4.0"
#
# @param $1   version string to normalize
# @return     normalized version string
#
function normalize_version_for_comparison() {
    local version=$1

    # remove 'v' prefix if present
    version="${version#v}"

    # remove common suffixes for comparison (keep base version)
    version="${version%%-alpine}"
    version="${version%%-noble}"
    version="${version%%-jre*}"
    version="${version%%-bullseye}"
    version="${version%%-slim}"
    version="${version%%-bookworm}"
    version="${version%%-all-oss}"

    echo "$version"
}

#
# Finds the start index in 'new' from which it differs from 'old': the first differing character,
# extended backwards to include the full numeric run containing it (multi-digit numbers are never
# split, so the highlight does not render a partial number). Used to highlight the changed part
# of the latest version.
# Example:
#   "1.2.1"   "1.3.0"        → 2   (highlights "3.0")
#   "16.4"    "17.0"         → 0   (highlights "17.0", not "7.0")
#   "2.29.0"  "2.30.0"       → 2   (highlights "30.0")
#   "2.29.0"  "2.29.1"       → 5   (highlights "1")
#   "144"     "145"          → 0   (a single number is one numeric run)
#   "1.2.3"   "1.2.3.4"      → 5   (highlights ".4" - the inserted '.' is not a digit, so no back-up)
#   "1.2.3"   "1.2.3"        → -1  (no difference)
#   "1.2.3.4" "1.2.3"        → -1  (nothing added)
#
# @param $1   old version string
# @param $2   new version string
# @return     start index in $2 from which the strings differ, or -1 if there is nothing to highlight
#
function find_version_diff_start() {
    local -r old=${1?Missing old version}
    local -r new=${2?Missing new version}

    # identical strings - nothing to highlight
    if [[ "$old" == "$new" ]]; then
        echo "-1"
        return
    fi

    # find the first differing character
    local -i common_len=0
    local -i max_common=$((${#old} < ${#new} ? ${#old} : ${#new}))

    while ((common_len < max_common)); do
        if [[ "${old:common_len:1}" != "${new:common_len:1}" ]]; then
            break
        fi

        common_len=$((common_len + 1))
    done

    # nothing was added to 'new' - nothing to highlight
    if ((common_len >= ${#new})); then
        echo "-1"
        return
    fi

    # extend backwards over the numeric run containing the first differing character
    # (only when the differing character itself is a digit)
    local -i start=$common_len

    if [[ "${new:start:1}" =~ [0-9] ]]; then
        while ((start > 0)) && [[ "${new:start-1:1}" =~ [0-9] ]]; do
            start=$((start - 1))
        done
    fi

    echo "$start"
}
