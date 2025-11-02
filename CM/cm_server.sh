#!/bin/bash

# CM (Codex Manager) - MCP Server for listing agent terminals
# Pure Bash + AppleScript implementation

# Source the MCP server core
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/mcpserver_core.sh"

# Check if jq is available (optional but recommended)
HAS_JQ=false
if command -v jq &> /dev/null; then
    HAS_JQ=true
fi

# Conversation history log file
CONVERSATION_LOG="$SCRIPT_DIR/conversations/history.jsonl"

# Function: Log conversation to history
# Args: $1 = from_agent, $2 = to_agents (comma-separated or array display), $3 = message
log_conversation() {
    local from="$1"
    local to="$2"
    local message="$3"

    # Create conversations directory if it doesn't exist
    mkdir -p "$(dirname "$CONVERSATION_LOG")"

    # Build JSON entry (compact format for JSONL)
    local entry=$(jq -nc \
        --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg from "$from" \
        --arg to "$to" \
        --arg msg "$message" \
        '{timestamp: $ts, from: $from, to: ($to|split(",")), message: $msg}')

    # Append to log file
    echo "$entry" >> "$CONVERSATION_LOG"
}

# Function: Get all Terminal windows with their TTY information
# Returns: Tab-separated list of: windowId<TAB>windowName<TAB>tty
get_terminal_windows() {
    osascript <<'EOF'
tell application "Terminal"
    set output to ""
    try
        repeat with w in windows
            repeat with t in tabs of w
                set wId to (id of w) as text
                set wName to name of w
                set ttyValue to tty of t
                -- Format: windowId|windowName|tty
                if output is "" then
                    set output to wId & "|" & wName & "|" & ttyValue
                else
                    set output to output & linefeed & wId & "|" & wName & "|" & ttyValue
                end if
            end repeat
        end repeat
    end try
    return output
end tell
EOF
}

# Function: Check if a process matching agent patterns is running on a TTY
# Args: $1 = tty (e.g., "ttys001"), $2 = agent_pattern (e.g., "codex|aider" or empty for all)
# Returns: pid<TAB>command or empty string
check_agent_on_tty() {
    local tty="$1"
    local agent_pattern="$2"

    # Extract just the tty device name (e.g., "ttys001" from "/dev/ttys001")
    local tty_device="${tty##*/}"

    # Get all processes on this TTY, excluding shells and system processes
    local all_processes=$(ps -t "$tty_device" -o pid=,args= 2>/dev/null)

    # Filter out common shell processes and system processes
    # Exclude: login, shells (bash, zsh, sh, tcsh, csh), ps, grep
    local filtered=$(echo "$all_processes" | grep -v -E "(^[[:space:]]*[0-9]+ login |^[[:space:]]*[0-9]+ -(bash|zsh|sh|tcsh|csh)|grep|ps )")

    if [ -z "$agent_pattern" ]; then
        # No pattern specified - return the first non-shell process
        echo "$filtered" | head -1
    else
        # Pattern specified - filter for specific agents and return the first match
        echo "$filtered" | grep -E "$agent_pattern" | grep -v grep | head -1
    fi
}

# Function: Send text to a Terminal window's input box
# Args: $1 = windowId, $2 = text to send
# Returns: 0 on success, 1 on failure
send_text_to_terminal() {
    local window_id="$1"
    local text="$2"

    # Escape single quotes in the text for AppleScript
    local escaped_text=$(echo "$text" | sed "s/'/'\\\\''/g")

    osascript <<EOF
tell application "Terminal"
    try
        set targetWindow to first window whose id is $window_id
        -- Activate Terminal and bring the target window to front
        activate
        set frontmost of targetWindow to true
        set selected tab of targetWindow to tab 1 of targetWindow
        -- Copy text to clipboard
        set the clipboard to "$escaped_text"
        -- Give Terminal time to become active and focused
        delay 0.3
        -- Use System Events to paste and press enter
        tell application "System Events"
            tell process "Terminal"
                -- Paste from clipboard (Command+V)
                keystroke "v" using command down
                delay 0.1
                -- Press Enter
                keystroke return
            end tell
        end tell
        return "success"
    on error errMsg
        return "error: " & errMsg
    end try
end tell
EOF
}

# Function: Get agent status based on recent activity
# Args: $1 = agent name
# Returns: "busy" if active within 5 minutes, "idle" if active within 30 minutes, "online" otherwise
get_agent_status() {
    local agent_name="$1"

    # If no conversation log exists, default to online
    if [[ ! -f "$CONVERSATION_LOG" ]]; then
        echo "online"
        return 0
    fi

    # Get the last message from or to this agent
    local last_activity=$(jq -s -r --arg agent "$agent_name" '
        map(select(.from == $agent or (.to | index($agent))))
        | last
        | .timestamp // ""
    ' "$CONVERSATION_LOG" 2>/dev/null)

    if [ -z "$last_activity" ] || [ "$last_activity" = "null" ]; then
        echo "online"
        return 0
    fi

    # Calculate time difference in seconds
    # Convert ISO 8601 timestamp to epoch seconds
    if date --version &>/dev/null 2>&1; then
        # GNU date
        local last_epoch=$(date -d "$last_activity" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
    else
        # BSD date (macOS)
        local last_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%S" "${last_activity:0:19}" +%s 2>/dev/null || echo 0)
        local now_epoch=$(date +%s)
    fi

    local diff=$((now_epoch - last_epoch))

    # Determine status based on time since last activity
    if [ $diff -lt 300 ]; then
        # Active within last 5 minutes
        echo "busy"
    elif [ $diff -lt 1800 ]; then
        # Active within last 30 minutes
        echo "idle"
    else
        # No recent activity
        echo "online"
    fi
}

# Main tool function: list_agent_terminals
# Args: $1 = JSON arguments from MCP client
tool_list_agent_terminals() {
    local args="$1"

    # Parse agentNames from JSON args
    # If not specified or empty array, search for all agents (empty pattern)
    local agent_names=""

    if [ "$HAS_JQ" = true ]; then
        # Check if agentNames is provided and not empty
        local has_agent_names=$(echo "$args" | jq 'has("agentNames")')

        if [ "$has_agent_names" = "true" ]; then
            # Use jq to parse agent names
            local parsed_agents=$(echo "$args" | jq -r '.agentNames | join("|")')
            if [ -n "$parsed_agents" ] && [ "$parsed_agents" != "null" ] && [ "$parsed_agents" != "" ]; then
                agent_names="$parsed_agents"
            fi
        fi
    fi

    # Get all Terminal windows
    local windows=$(get_terminal_windows)

    if [ -z "$windows" ]; then
        # No terminal windows found
        echo '{"terminals":[],"message":"No Terminal windows found"}'
        return 0
    fi

    # Build result JSON
    local results="["
    local first=true

    # Process each window
    while IFS='|' read -r window_id window_name tty; do
        # Skip empty lines
        [ -z "$window_id" ] && continue

        # Check if an agent is running on this TTY
        local process_info=$(check_agent_on_tty "$tty" "$agent_names")

        if [ -n "$process_info" ]; then
            # Extract PID and full command line
            local pid=$(echo "$process_info" | awk '{print $1}')
            local full_command=$(echo "$process_info" | cut -d' ' -f2-)

            # Extract agent name from command line (e.g., "gemini" from "node /opt/homebrew/bin/gemini")
            local agent_name=""

            if [ -n "$agent_names" ]; then
                # Specific agent names provided - try to match them
                if echo "$full_command" | grep -qE "$agent_names"; then
                    # Find which agent name matches in the command
                    for agent in $(echo "$agent_names" | tr '|' ' '); do
                        if echo "$full_command" | grep -q "$agent"; then
                            agent_name="$agent"
                            break
                        fi
                    done
                fi
            fi

            # If no match found, extract agent name from command
            if [ -z "$agent_name" ]; then
                # Try to extract from common patterns like "node /path/to/agent" or "/path/to/agent"
                if echo "$full_command" | grep -qE "^(node|python|python3|ruby|perl) "; then
                    # Extract the script name after the interpreter
                    agent_name=$(echo "$full_command" | awk '{print $2}')
                    agent_name="${agent_name##*/}"
                else
                    # Direct command execution
                    agent_name=$(echo "$full_command" | awk '{print $1}')
                    agent_name="${agent_name##*/}"
                fi
            fi

            # Get agent status based on recent activity
            local agent_status=$(get_agent_status "$agent_name")

            # Escape special characters in strings for JSON
            window_name=$(echo "$window_name" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
            full_command=$(echo "$full_command" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

            # Build JSON object for this terminal
            if [ "$first" = true ]; then
                first=false
            else
                results+=","
            fi

            results+="{\"windowId\":$window_id,\"windowName\":\"$window_name\",\"tty\":\"$tty\",\"agent\":{\"pid\":$pid,\"name\":\"$agent_name\",\"command\":\"$full_command\",\"status\":\"$agent_status\"}}"
        fi
    done <<< "$windows"

    results+="]"

    # Build final response
    if [ "$HAS_JQ" = true ]; then
        # Use jq to format nicely
        echo "{\"terminals\":$results}" | jq -c .
    else
        # Manual JSON construction
        echo "{\"terminals\":$results}"
    fi

    return 0
}

# Helper function: Send message to a single agent
# Args: $1 = agent_name, $2 = from_agent, $3 = message, $4 = recipients_display
send_to_single_agent() {
    local agent_name="$1"
    local from_agent="$2"
    local message="$3"
    local recipients_display="$4"

    # Get all Terminal windows
    local windows=$(get_terminal_windows)

    if [ -z "$windows" ]; then
        echo '{"success":false,"error":"No Terminal windows found"}'
        return 1
    fi

    # Search for the agent window
    local window_id=""
    local found=false
    while IFS='|' read -r wid wname tty; do
        [ -z "$wid" ] && continue

        # Check if this agent is running on this TTY
        local process_info=$(check_agent_on_tty "$tty" "$agent_name")

        if [ -n "$process_info" ]; then
            window_id="$wid"
            found=true
            break
        fi
    done <<< "$windows"

    if [ "$found" = false ]; then
        echo "{\"success\":false,\"agent\":\"$agent_name\",\"error\":\"Agent not found\"}"
        return 1
    fi

    # Format message with source and recipients information
    local formatted_message="[${from_agent} → ${recipients_display}]: ${message}"

    # Send the message to the Terminal window
    local result=$(send_text_to_terminal "$window_id" "$formatted_message")

    if echo "$result" | grep -q "success"; then
        echo "{\"success\":true,\"agent\":\"$agent_name\",\"windowId\":$window_id}"
        return 0
    else
        local error_msg=$(echo "$result" | sed 's/^error: //' | sed 's/"/\\"/g')
        echo "{\"success\":false,\"agent\":\"$agent_name\",\"error\":\"$error_msg\"}"
        return 1
    fi
}

# Main tool function: send_to_agent
# Args: $1 = JSON arguments from MCP client
tool_send_to_agent() {
    local args="$1"

    # Parse arguments from JSON
    local agent_name_raw=""
    local from_agent=""
    local message=""

    if [ "$HAS_JQ" = true ]; then
        from_agent=$(echo "$args" | jq -r '.from // "unknown"')
        message=$(echo "$args" | jq -r '.message // ""')

        # Check if agentName is array or string
        local is_array=$(echo "$args" | jq -r '.agentName | type')

        if [ "$is_array" = "array" ]; then
            agent_name_raw=$(echo "$args" | jq -r '.agentName | @json')
        else
            agent_name_raw=$(echo "$args" | jq -r '.agentName // ""')
        fi
    else
        echo '{"success":false,"error":"jq is required for this tool"}'
        return 1
    fi

    # Validate required parameters
    if [ -z "$agent_name_raw" ] || [ "$agent_name_raw" = "null" ]; then
        echo '{"success":false,"error":"agentName is required"}'
        return 1
    fi

    if [ -z "$message" ] || [ "$message" = "null" ]; then
        echo '{"success":false,"error":"message is required"}'
        return 1
    fi

    # Handle array or single agent name
    local agent_names=()
    local recipients_display=""

    if [[ "$agent_name_raw" == "["* ]]; then
        # Array of agents (group chat) - use portable method instead of mapfile
        while IFS= read -r agent; do
            [ -n "$agent" ] && agent_names+=("$agent")
        done < <(echo "$agent_name_raw" | jq -r '.[]')
        recipients_display=$(echo "$agent_name_raw" | jq -r 'join(",")')
    else
        # Single agent
        agent_names=("$agent_name_raw")
        recipients_display="$agent_name_raw"
    fi

    # Send message to all recipients
    local results="["
    local first=true
    local success_count=0
    local total_count=${#agent_names[@]}

    for agent in "${agent_names[@]}"; do
        [ -z "$agent" ] && continue

        local result=$(send_to_single_agent "$agent" "$from_agent" "$message" "$recipients_display")

        if [ "$first" = true ]; then
            first=false
        else
            results+=","
        fi

        results+="$result"

        # Count successes
        if echo "$result" | grep -q '"success":true'; then
            ((success_count++))
        fi
    done

    results+="]"

    # Log conversation if at least one message was sent successfully
    if [ $success_count -gt 0 ]; then
        log_conversation "$from_agent" "$recipients_display" "$message"
    fi

    # Build final response
    if [ "$HAS_JQ" = true ]; then
        echo "{\"success\":true,\"sent\":$success_count,\"total\":$total_count,\"results\":$results}" | jq -c .
    else
        echo "{\"success\":true,\"sent\":$success_count,\"total\":$total_count,\"results\":$results}"
    fi

    return 0
}

# Main tool function: register_commands
# Args: $1 = JSON arguments from MCP client
tool_register_commands() {
    local args="$1"

    # Path to dynamic commands file
    local dynamic_file="$SCRIPT_DIR/assets/agent_commands_dynamic.json"

    # Parse arguments
    if [ "$HAS_JQ" != true ]; then
        echo '{"success":false,"error":"jq is required for this tool"}'
        return 1
    fi

    local agent_name=$(echo "$args" | jq -r '.agentName // ""')
    local commands=$(echo "$args" | jq -c '.commands // []')

    # Validate required parameters
    if [ -z "$agent_name" ] || [ "$agent_name" = "null" ]; then
        echo '{"success":false,"error":"agentName is required"}'
        return 1
    fi

    if [ "$commands" = "[]" ] || [ "$commands" = "null" ]; then
        echo '{"success":false,"error":"commands array is required"}'
        return 1
    fi

    # Create or load dynamic commands file
    if [[ ! -f "$dynamic_file" ]]; then
        echo '{}' > "$dynamic_file"
    fi

    # Update dynamic commands
    local updated=$(jq --arg agent "$agent_name" --argjson cmds "$commands" \
        '.[$agent] = {description: ("Dynamically registered commands for " + $agent), commands: $cmds}' \
        "$dynamic_file")

    echo "$updated" > "$dynamic_file"

    echo "{\"success\":true,\"agent\":\"$agent_name\",\"commandsRegistered\":$(echo "$commands" | jq 'length')}" | jq -c .
    return 0
}

# Main tool function: list_agent_commands
# Args: $1 = JSON arguments from MCP client
tool_list_agent_commands() {
    local args="$1"

    # Paths to agent commands configurations
    local static_file="$SCRIPT_DIR/assets/agent_commands.json"
    local dynamic_file="$SCRIPT_DIR/assets/agent_commands_dynamic.json"

    # Check if static commands file exists
    if [[ ! -f "$static_file" ]]; then
        echo '{"error":"Agent commands configuration not found"}'
        return 1
    fi

    # Merge static and dynamic commands
    local merged_commands=""
    if [[ -f "$dynamic_file" ]]; then
        # Merge: dynamic commands override static ones
        merged_commands=$(jq -s '.[0] * .[1]' "$static_file" "$dynamic_file")
    else
        merged_commands=$(cat "$static_file")
    fi

    # Parse agentName from args (optional)
    local agent_name=""
    if [ "$HAS_JQ" = true ] && [ -n "$args" ] && [ "$args" != "{}" ]; then
        agent_name=$(echo "$args" | jq -r '.agentName // ""')
    fi

    if [ -n "$agent_name" ] && [ "$agent_name" != "null" ]; then
        # Return commands for specific agent
        local agent_data=$(echo "$merged_commands" | jq --arg agent "$agent_name" '.[$agent] // null')

        if [ "$agent_data" = "null" ] || [ -z "$agent_data" ]; then
            echo "{\"error\":\"Agent not found: $agent_name\"}"
            return 1
        fi

        echo "{\"agent\":\"$agent_name\",\"info\":$agent_data}" | jq -c .
    else
        # Return all agents and their commands
        echo "$merged_commands" | jq -c '{agents: .}'
    fi

    return 0
}

# Main tool function: get_collaboration_stats
# Args: $1 = JSON arguments from MCP client
tool_get_collaboration_stats() {
    local args="$1"

    # Check if conversation log exists
    if [[ ! -f "$CONVERSATION_LOG" ]]; then
        echo '{"stats":{},"message":"No conversation history available"}'
        return 0
    fi

    # Parse optional agentName filter
    local filter_agent=""
    if [ "$HAS_JQ" = true ] && [ -n "$args" ] && [ "$args" != "{}" ]; then
        filter_agent=$(echo "$args" | jq -r '.agentName // ""')
    fi

    # Build stats using jq
    if [ -n "$filter_agent" ] && [ "$filter_agent" != "null" ]; then
        # Stats for specific agent
        jq -s --arg agent "$filter_agent" '
            {
                agent: $agent,
                messagesSent: (map(select(.from == $agent)) | length),
                messagesReceived: (map(select(.to | index($agent))) | length),
                topCollaborators: (
                    map(select(.from == $agent or (.to | index($agent))))
                    | map(if .from == $agent then .to[] else .from end)
                    | map(select(. != $agent))
                    | group_by(.) | map({agent: .[0], count: length})
                    | sort_by(-.count) | .[0:5]
                ),
                mostUsedCommands: (
                    map(select(.from == $agent and (.message | startswith("/"))))
                    | map(.message | split(" ")[0])
                    | group_by(.) | map({command: .[0], count: length})
                    | sort_by(-.count) | .[0:10]
                ),
                recentActivity: (
                    map(select(.from == $agent or (.to | index($agent))))
                    | .[-10:] | map({
                        timestamp: .timestamp,
                        from: .from,
                        to: (.to | join(",")),
                        isCommand: (.message | startswith("/"))
                    })
                )
            }
        ' "$CONVERSATION_LOG" | jq -c .
    else
        # Overall stats for all agents
        jq -s '
            {
                totalMessages: length,
                totalAgents: ([.[].from] + ([.[].to] | flatten) | unique | length),
                messagesByAgent: (
                    group_by(.from) | map({agent: .[0].from, sent: length})
                ),
                mostActiveCollaborations: (
                    map({pair: ([.from] + .to | sort | join("-")), msg: .})
                    | group_by(.pair) | map({pair: .[0].pair, count: length})
                    | sort_by(-.count) | .[0:10]
                ),
                commandUsage: (
                    map(select(.message | startswith("/")))
                    | map(.message | split(" ")[0])
                    | group_by(.) | map({command: .[0], count: length})
                    | sort_by(-.count) | .[0:10]
                ),
                timeRange: {
                    earliest: .[0].timestamp,
                    latest: .[-1].timestamp
                }
            }
        ' "$CONVERSATION_LOG" | jq -c .
    fi

    return 0
}

# Main tool function: resources_read
# Args: $1 = JSON arguments from MCP client
tool_resources_read() {
    local args="$1"
    local uri=$(echo "$args" | jq -r '.uri')

    # Check if conversation log exists
    if [[ ! -f "$CONVERSATION_LOG" ]]; then
        echo ""
        return 0
    fi

    case "$uri" in
        conversation://latest/*)
            # Get last N messages
            local limit="${uri##*/}"
            # Validate limit is a positive integer
            if ! [[ "$limit" =~ ^[0-9]+$ ]]; then
                echo "{\"error\":\"Invalid limit parameter: must be a positive integer\"}"
                return 1
            fi
            tail -n "$limit" "$CONVERSATION_LOG" 2>/dev/null | jq -s -r '
                map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]' 2>/dev/null || echo ""
            ;;
        conversation://with/*)
            # Get messages related to a specific agent
            local agent="${uri##*/}"
            jq -s -r --arg agent "$agent" '
                map(select(.from == $agent or (.to | index($agent))))
                | map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]
            ' "$CONVERSATION_LOG" 2>/dev/null || echo ""
            ;;
        conversation://search*)
            # Search messages by keyword (with URL decoding support)
            local query=$(echo "$uri" | sed -n 's/.*q=\([^&]*\).*/\1/p')
            if [ -z "$query" ]; then
                echo '{"error":"Missing query parameter"}'
                return 1
            fi
            # Basic URL decode for common characters
            query=$(printf '%b' "${query//%/\\x}")
            grep -i "$query" "$CONVERSATION_LOG" 2>/dev/null | jq -s -r '
                map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]' 2>/dev/null || echo ""
            ;;
        conversation://between/*/*)
            # Get conversations between two specific agents
            # URI format: conversation://between/agent1/agent2
            local path="${uri##conversation://between/}"
            local agent1=$(echo "$path" | cut -d'/' -f1)
            local agent2=$(echo "$path" | cut -d'/' -f2)
            if [ -z "$agent1" ] || [ -z "$agent2" ]; then
                echo '{"error":"Both agent names required. Format: conversation://between/agent1/agent2"}'
                return 1
            fi
            jq -s -r --arg a1 "$agent1" --arg a2 "$agent2" '
                map(select(
                    (.from == $a1 and (.to | index($a2))) or
                    (.from == $a2 and (.to | index($a1)))
                ))
                | map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]
            ' "$CONVERSATION_LOG" 2>/dev/null || echo ""
            ;;
        conversation://time/*/*)
            # Get conversations within a time range
            # URI format: conversation://time/start_timestamp/end_timestamp
            # Timestamps in ISO 8601 format: 2025-01-15T10:00:00
            local path="${uri##conversation://time/}"
            local start_time=$(echo "$path" | cut -d'/' -f1)
            local end_time=$(echo "$path" | cut -d'/' -f2)
            if [ -z "$start_time" ] || [ -z "$end_time" ]; then
                echo '{"error":"Both start and end timestamps required. Format: conversation://time/2025-01-15T10:00:00/2025-01-15T12:00:00"}'
                return 1
            fi
            # URL decode timestamps
            start_time=$(printf '%b' "${start_time//%/\\x}")
            end_time=$(printf '%b' "${end_time//%/\\x}")
            jq -s -r --arg start "$start_time" --arg end "$end_time" '
                map(select(.timestamp >= $start and .timestamp <= $end))
                | map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]
            ' "$CONVERSATION_LOG" 2>/dev/null || echo ""
            ;;
        conversation://pattern/*)
            # Search messages by regex pattern
            # URI format: conversation://pattern/regex_pattern
            local pattern="${uri##conversation://pattern/}"
            if [ -z "$pattern" ]; then
                echo '{"error":"Missing pattern parameter"}'
                return 1
            fi
            # URL decode pattern
            pattern=$(printf '%b' "${pattern//%/\\x}")
            jq -s -r --arg pattern "$pattern" '
                map(select(.message | test($pattern; "i")))
                | map("\(.timestamp) [\(.from) → \(.to|join(","))]: \(.message)") | .[]
            ' "$CONVERSATION_LOG" 2>/dev/null || echo ""
            ;;
        *)
            echo "{\"error\":\"Unsupported URI: $uri\"}"
            return 1
            ;;
    esac
}

# Start the MCP server
run_mcp_server "$@"
