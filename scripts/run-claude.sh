#!/usr/bin/env bash
# Run Claude Code headlessly. If it stops because the usage limit was hit,
# sleep until the limit resets and try again.
#
# Deliberately not using `set -e`: we need to inspect claude's non-zero exit
# code rather than die on it.
set -uo pipefail

PROMPT="${CLAUDE_PROMPT:-Hi da machi!! Wake up!!}"
MAX_ATTEMPTS="${MAX_ATTEMPTS:-10}"
MAX_SLEEP="${MAX_SLEEP:-18000}"        # 5h ceiling, keeps us inside the 6h job timeout
FALLBACK_SLEEP="${FALLBACK_SLEEP:-900}" # 15m, used when the reset time can't be parsed
SLEEP_PAD="${SLEEP_PAD:-60}"           # small cushion so we don't wake up a second too early

# Print the usage-limit reset time found in claude's output, or nothing.
# The message format is not stable across CLI versions, so try each known shape.
extract_reset_time() {
    local output="$1" match

    # 1. classic pipe form: "Claude AI usage limit reached|1756576800"
    match=$(grep -oE 'usage limit reached\|[0-9]+' <<<"$output" | head -1)
    if [ -n "$match" ]; then
        printf '%s\n' "${match##*|}"
        return 0
    fi

    # 2. structured field: "resetsAt": "..." / "reset_at": 1756576800
    # Strip only the key and its separator -- an ISO-8601 value contains colons
    # of its own, so a greedy strip would eat the timestamp.
    match=$(grep -oE '"?(resetsAt|reset_at)"?[[:space:]]*[:=][[:space:]]*"?[^",}[:space:]]+' <<<"$output" | head -1)
    if [ -n "$match" ]; then
        printf '%s\n' "$(sed -E 's/^"?(resetsAt|reset_at)"?[[:space:]]*[:=][[:space:]]*"?//' <<<"$match")"
        return 0
    fi

    # 3. unknown
    return 1
}

# Print the number of seconds to sleep before retrying, given a reset time
# that is either epoch seconds or an ISO-8601 timestamp.
calculate_wait() {
    local reset_time="$1" reset_epoch now wait

    if [[ "$reset_time" =~ ^[0-9]+$ ]]; then
        reset_epoch="$reset_time"
    else
        reset_epoch=$(date -d "$reset_time" +%s 2>/dev/null) || return 1
    fi
    [ -n "$reset_epoch" ] || return 1

    now=$(date +%s)
    wait=$(( reset_epoch - now + SLEEP_PAD ))

    # Clamp: a stale or bogus timestamp must not wedge (or skip) the wait.
    [ "$wait" -lt 60 ] && wait=60
    [ "$wait" -gt "$MAX_SLEEP" ] && wait="$MAX_SLEEP"

    printf '%s\n' "$wait"
}

attempt=1
while [ "$attempt" -le "$MAX_ATTEMPTS" ]; do
    echo "Starting a New Claude Code run... (attempt $attempt/$MAX_ATTEMPTS)"

    output=$(claude -p "$PROMPT" 2>&1)
    exit_code=$?

    echo "$output"

    if [ "$exit_code" -eq 0 ]; then
        echo "Claude completed successfully"
        exit 0
    fi

    if ! grep -qi 'usage limit reached' <<<"$output"; then
        echo "Claude failed for another reason (exit $exit_code)"
        exit "$exit_code"
    fi

    echo "Claude usage limit reached"

    if reset_time=$(extract_reset_time "$output") && sleep_seconds=$(calculate_wait "$reset_time"); then
        echo "Reset time: $reset_time"
    else
        echo "Could not determine reset time, backing off"
        sleep_seconds="$FALLBACK_SLEEP"
    fi

    echo "Waiting $sleep_seconds seconds..."
    sleep "$sleep_seconds"

    echo "Reset should now be available"
    attempt=$(( attempt + 1 ))
done

echo "Giving up after $MAX_ATTEMPTS attempts"
exit 1
