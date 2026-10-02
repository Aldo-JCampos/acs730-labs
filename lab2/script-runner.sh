#!/bin/bash
set -euo pipefail

# Resolve the directory this script lives in, so it works regardless of cwd
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# --- Argument parsing ---------------------------------------------------
# -v            : wait for Enter before running each script
# <list_file>   : optional, name of the list file (default: scripts.list)
WAIT_MODE=0
LIST_FILE="scripts.list"

for arg in "$@"; do
    case "$arg" in
        -v)
            WAIT_MODE=1
            ;;
        *)
            LIST_FILE="$arg"
            ;;
    esac
done

LIST_PATH="${SCRIPT_DIR}/${LIST_FILE}"

if [[ ! -f "$LIST_PATH" ]]; then
    echo "ERROR: list file not found: ${LIST_PATH}" >&2
    exit 1
fi

# Read non-empty, non-comment lines. Each line is: script.sh [arg1 arg2 ...]
LINES=()
while IFS= read -r line || [[ -n "$line" ]]; do
    # trim leading/trailing whitespace
    line="$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue
    LINES+=("$line")
done < "$LIST_PATH"

if [[ ${#LINES[@]} -eq 0 ]]; then
    echo "No scripts found in ${LIST_PATH}"
    exit 0
fi

echo "Loaded ${#LINES[@]} script(s) from ${LIST_FILE}"
if [[ "$WAIT_MODE" -eq 1 ]]; then
    echo "Mode: step-by-step (will wait for Enter before each script)"
else
    echo "Mode: run-all (no pausing between scripts)"
fi
echo

for line in "${LINES[@]}"; do
    # Split the line into script name + arguments (simple whitespace split)
    read -ra parts <<< "$line"
    script="${parts[0]}"
    args=("${parts[@]:1}")

    script_path="${SCRIPT_DIR}/${script}"

    if [[ ! -f "$script_path" ]]; then
        echo "ERROR: ${script} not found in ${SCRIPT_DIR}" >&2
        exit 1
    fi

    if [[ ! -x "$script_path" ]]; then
        echo "Making ${script} executable..."
        chmod +x "$script_path"
    fi

    if [[ ${#args[@]} -gt 0 ]]; then
        echo "Next up: ${script} (args: ${args[*]})"
    else
        echo "Next up: ${script}"
    fi

    if [[ "$WAIT_MODE" -eq 1 ]]; then
        read -r -p "Press Enter to run it (Ctrl+C to abort)... "
    fi

    echo "==> Running ${script} ${args[*]-}"
    "$script_path" "${args[@]+"${args[@]}"}"
    echo "==> Finished ${script}"
    echo
done

echo "All scripts completed successfully."