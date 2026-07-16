#
# Extracts optional suffix from version tag. The suffix is everything after the first hyphen.
# Example:
#   "8.3.1-noble"   →  "noble"
#   "2.8.2-jre17"   →  "jre17"
#   "9.4.0"         →  ""
#   "1.2.3-456-7"   →  "456-7"
#   "v1.2.3-alpine" →  "alpine"
#
# @param $1   version string to extract suffix from
# @return     suffix with leading hyphen, or empty string if no suffix
#
function extract_version_suffix() {
    local -r version=${1?Missing version}

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

    # common Ubuntu codenames
    local codenames="noble|jammy|focal|bionic|xenial|trusty|precise|oneiric|natty|maverick|lucid|karmic|jaunty|intrepid|hardy|gutsy|feisty|edgy|dapper|breezy|warty"

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

    # handle special cases like pg18.3-ts2.26.4
    if [[ $normalized =~ ^pg([0-9]+\.[0-9]+)\-ts([0-9]+\.[0-9]+\.[0-9]+) ]]; then
        echo "timescaledb:${BASH_REMATCH[1]}:${BASH_REMATCH[2]}"
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

    # split by dots and compare each component
    local IFS='.'
    local -r parts1=("$v1")
    local -r parts2=("$v2")

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

        # Docker image (PosgreSQL + TimescaleDB extension), format: pg1.2.3-ts4.5.6
        "timescaledb")
            local -r current_pg=$(echo "$current_parts" | cut -d: -f2)
            local -r current_ts=$(echo "$current_parts" | cut -d: -f3)
            local -r latest_pg=$(echo "$latest_parts" | cut -d: -f2)
            local -r latest_ts=$(echo "$latest_parts" | cut -d: -f3)

            # check Postgres version
            compare_semver "$latest_pg" "$current_pg"
            local pg_cmp=$?

            # check Timescale version
            compare_semver "$latest_ts" "$current_ts"
            local ts_cmp=$?

            if [[ $pg_cmp -eq 1 ]]; then
                echo "major"
            elif [[ $pg_cmp -eq 0 && $ts_cmp -eq 1 ]]; then
                echo "minor"
            else
                echo "none"
            fi
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
