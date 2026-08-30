#!bin/bash

while true; do
    echo "Starting a New Claude Code run..."

    output=$(claude -p "Hi da machi!! Wake up!!" 2>&1)
    exit_code=$?

    echo "$output"

    if [ $exit_code -eq 0]; then
        echo "Claude completed succesfully"
        exit 0
    fi

    reset_time=$(extract_reset_time "$output")

    if [ -z "$reset_time" ]; then
        echo "Claude failed for another reason"
        exit $exit_code
    fi

    echo "Claude usage limit reached"
    echo "Reset time: $reset_time"

    sleep_seconds=$(calculate_wait "$reset)time")

    echo "Waiting $sleep_seconds seconds..."

    sleep "$sleep_seconds"

    echo "Reset should now be available"
    echo "Starting New Claude Code Run..."
done
