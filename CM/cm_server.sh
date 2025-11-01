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

            # Escape special characters in strings for JSON
            window_name=$(echo "$window_name" | sed 's/"/\\"/g' | sed "s/'/\\'/g")
            full_command=$(echo "$full_command" | sed 's/"/\\"/g' | sed 's/\\/\\\\/g')

            # Build JSON object for this terminal
            if [ "$first" = true ]; then
                first=false
            else
                results+=","
            fi

            results+="{\"windowId\":$window_id,\"windowName\":\"$window_name\",\"tty\":\"$tty\",\"agent\":{\"pid\":$pid,\"name\":\"$agent_name\",\"command\":\"$full_command\"}}"
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
        # Array of agents (group chat)
        mapfile -t agent_names < <(echo "$agent_name_raw" | jq -r '.[]')
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

    # Build final response
    if [ "$HAS_JQ" = true ]; then
        echo "{\"success\":true,\"sent\":$success_count,\"total\":$total_count,\"results\":$results}" | jq -c .
    else
        echo "{\"success\":true,\"sent\":$success_count,\"total\":$total_count,\"results\":$results}"
    fi

    return 0
}

# Start the MCP server
run_mcp_server "$@"
