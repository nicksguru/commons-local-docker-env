#
# Helper functions for building JSON documents with 'jq'.
#

#
# Prints a JSON error document on stdout. Used for error exits in JSON mode
# (log messages go to stderr, see log_raw).
#
# @param $1   error message
#
function emit_json_error() {
    local -r message=${1?Missing message}
    jq --compact-output --null-input --arg error "$message" '{error: $error}'
}

#
# Converts the given strings to a JSON array of strings.
# Messages are always single-line (parsed from '.env' comment newline_separated_string), so newline separation is safe.
#
# @param $@   strings to convert
# @return     JSON array literal (e.g. '["msg1","msg2"]')
#
function convert_to_json_array() {
    # printf '%s\n' with zero arguments would still print one empty line, which would become [""] instead of []
    if [[ $# -eq 0 ]]; then
        echo "[]"
        return
    fi

    # 1. each item of $@ becomes a separate argument to printf and therefore a separate line in the output
    # 2. --raw-input wraps each line in double quotes
    # 3. --slurp collects all newline_separated_string into an array
    # 4. --compact-output removes whitespace
    printf '%s\n' "$@" | jq --raw-input . | jq --slurp --compact-output .
}

#
# Converts a newline-separated string to a JSON array of strings.
#
# @param $1   newline-separated string (possibly empty)
# @return     JSON array literal (e.g. '["msg1","msg2"]'; '[]' for empty input)
#
function split_by_newline_to_json_array() {
    local -r newline_separated_string=${1?Missing newline_separated_string}

    if [[ -z "$newline_separated_string" ]]; then
        echo "[]"
        return
    fi

    local -a split=()
    # mapfile:
    #   * splits strictly on newlines
    #   * no word-splitting on spaces
    #   * no globbing
    #   * handles a trailing newline without producing an empty element
    mapfile -t split <<< "$newline_separated_string"
    convert_to_json_array "${split[@]}"
}

#
# Builds a compact JSON object for one checked image (see emit_json_output for the document structure).
#
# @param $1   Docker image name
# @param $2   version variable name (e.g. REDIS_VERSION)
# @param $3   current (local) version
# @param $4   latest version from Docker Hub
# @param $5   update type (none/major/minor/patch/unknown)
# @param $6   'true' when the Docker Hub fetch failed and the local version was used as fallback
# @param $7   info messages (newline-separated, empty if none)
# @param $8   warning messages (newline-separated, empty if none)
# @param $9   error messages (newline-separated, empty if none)
# @return     compact JSON object
#
function build_image_json_row() {
    local -r image=${1?Missing image}
    local -r variable_name=${2?Missing variable_name}
    local -r local_version=${3?Missing local_version}
    local -r latest_version=${4?Missing latest_version}
    local -r update_type=${5?Missing update_type}
    local -r fetch_failed=${6?Missing fetch_failed}
    local -r infos=${7?Missing infos}
    local -r warnings=${8?Missing warnings}
    local -r errors=${9?Missing errors}

    # --argjson outputs raw numbers and booleans
    jq --compact-output --null-input \
        --arg image "$image" \
        --arg variable "$variable_name" \
        --arg localVersion "$local_version" \
        --arg latestVersion "$latest_version" \
        --arg updateType "$update_type" \
        --argjson fetchFailed "$fetch_failed" \
        --argjson info "$(split_by_newline_to_json_array "$infos")" \
        --argjson warnings "$(split_by_newline_to_json_array "$warnings")" \
        --argjson errors "$(split_by_newline_to_json_array "$errors")" \
        '{image: $image, variable: $variable, localVersion: $localVersion, latestVersion: $latestVersion, updateType: $updateType, fetchFailed: $fetchFailed, info: $info, warnings: $warnings, errors: $errors}'
}

#
# Assembles and prints the final JSON document: one image row per element of the given rows array
# plus summary statistics.
#
# @param $1   name of the indexed array with per-image JSON rows (passed by reference)
# @param $2   total number of images checked
# @param $3   total number of images with updates
# @param $4   number of major updates
# @param $5   number of minor updates
# @param $6   number of patch updates
# @param $7   number of special updates
#
function emit_json_output() {
    local -n image_rows_json=${1?Missing image_rows_json}
    shift
    local -r total_images=${1?Missing total_images}
    local -r total_updates=${2?Missing total_updates}
    local -r major_updates=${3?Missing major_updates}
    local -r minor_updates=${4?Missing minor_updates}
    local -r patch_updates=${5?Missing patch_updates}
    local -r special_updates=${6?Missing special_updates}

    # 'printf' with no arguments would still print one empty line, breaking 'jq --slurp';
    # --argjson skips wrapping in quotes - the numbers are already valid JSON
    if [[ ${#image_rows_json[@]} -eq 0 ]]; then
        printf ''
    else
        printf '%s\n' "${image_rows_json[@]}"
    fi | jq --slurp \
        --argjson totalImages "$total_images" \
        --argjson imagesWithUpdates "$total_updates" \
        --argjson major "$major_updates" \
        --argjson minor "$minor_updates" \
        --argjson patch "$patch_updates" \
        --argjson special "$special_updates" \
        '{
            images: .,
            summary: {
                totalImages: $totalImages,
                imagesWithUpdates: {
                    total: $imagesWithUpdates,
                    major: $major,
                    minor: $minor,
                    patch: $patch,
                    special: $special
                }
            }
        }'
}
