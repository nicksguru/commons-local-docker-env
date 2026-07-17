# Detect if we're in a terminal and should use colors.
# Namely, check if both stdout (fd 1) and stderr (fd 2) are connected to a terminal
if [[ -t 1 && -t 2 ]]; then
    # Color codes for output (ANSI escape sequences). Format: '\033[<style>;<color>m'. Example:
    #   \033 = ESC character (starts escape sequence)
    #   [    = CSI (Control Sequence Introducer)
    #   0;   = style 0 (normal/bold off)
    #   31   = foreground color (red)
    #   m    = end of sequence
    readonly COLOR_RESET='\033[0m'      # reset all attributes to default
    readonly COLOR_ERROR='\033[0;31m'   # red
    readonly COLOR_WARN='\033[0;33m'    # yellow
    readonly COLOR_INFO='\033[0;32m'    # green
    readonly COLOR_DEBUG='\033[0;36m'   # cyan
    readonly BOLD='\033[1m'
# when not in a terminal, each color code becomes a no-op, so messages become plain text
else
    # not in a terminal - use empty strings to avoid escape sequences in output
    readonly COLOR_RESET=''
    readonly COLOR_ERROR=''
    readonly COLOR_WARN=''
    readonly COLOR_INFO=''
    readonly COLOR_DEBUG=''
    readonly BOLD=''
fi

#
# Logs a message.
# $@ - message, possibly with ANSI colors
#
function log_raw() {
    echo -e "$(date --iso-8601=seconds) $@"
}

# errors are not sent to stderr - to ease output redirection
function log_error() { log_raw "${COLOR_ERROR}[ERROR]${COLOR_RESET} $*"; }
function log_warn()  { log_raw "${COLOR_WARN}[WARN ]${COLOR_RESET} $*";  }
function log_info()  { log_raw "${COLOR_INFO}[INFO ]${COLOR_RESET} $*";  }
function log_debug() { log_raw "${COLOR_DEBUG}[DEBUG]${COLOR_RESET}$*";  }

#
# Loads environment variables from '.env' file in the parent directory.
# Exits with error if the file doesn't exist or isn't readable.
#
function load_env_file() {
    local env_file
    env_file="$(dirname "$0")/../.env"

    if ! ensure_files_exist "$env_file"; then
        log_error "Please generate the above file according to instructions in README.md"
        exit 1
    fi

    . "$env_file"
}

#
# Checks if files do not exist.
# Arguments:
#   $@ - list of files to check
# Returns (in $?):
#   0 if none of the files exist
#   1 if any file exists (with error messages)
# Example:
#   ensure_files_do_not_exist "file1.txt" "file2.txt"
#
function ensure_files_do_not_exist() {
    local error=0

    for i in "$@"; do
        if [ -f "$i" ]; then
            log_error "File '$i' already exists, please back up or remove it"
            error=1
        fi
    done

    if [ $error -ne 0 ]; then
        return 1
    fi
}

#
# Checks if files exist and are readable.
# Arguments:
#   $@ - list of files to check
# Returns (in $?):
#   0 if all files exist and are readable
#   1 if any file doesn't exist or isn't readable (with error messages)
# Example:
#   ensure_files_exist "required1.txt" "required2.txt"
#
function ensure_files_exist() {
    local error=0

    for i in "$@"; do
        if [ ! -r "$i" ]; then
            log_error "File '$i' does not exist or is not readable"
            error=1
        fi
    done

    if [ $error -ne 0 ]; then
        return 1
    fi
}

#
# Checks if directories exist.
# Arguments:
#   $@ - list of directories to check
# Returns (in $?):
#   0 if all directories exist
#   1 if any directory doesn't exist (with error messages)
# Example:
#   ensure_dirs_exist "/tmp" "/var"
#
function ensure_dirs_exist() {
    local error=0

    for i in "$@"; do
        if [ ! -d "$i" ]; then
            log_error "Directory '$i' does not exist"
            error=1
        fi
    done

    if [ $error -ne 0 ]; then
        return 1
    fi
}

#
# Searches for a given value in an array and returns 0 if found, 1 otherwise.
#
# Arguments:
#   $1 - The value to search for (needle)
#   $@ - The array to search in (haystack), passed as remaining arguments
#
# Returns (in $?):
#   0 if the value is found in the array
#   1 if the value is not found
#
function find_in_array() {
    local -r needle=${1?Missing needle}
    shift
    local -r haystack=("$@")
    local -i i

    for ((i=0; i<${#haystack[@]}; i++)); do
        if [[ "${haystack[$i]}" == "$needle" ]]; then
            return 0
        fi
    done

    return 1
}
