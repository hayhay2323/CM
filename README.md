# CM

CM (Codex Manager) - MCP Server for managing and communicating with AI agent terminals.

## Features

- **List Agent Terminals**: Find all Terminal windows running AI agents (codex, aider, gemini, qwen, iflow, etc.)
- **Send Messages**: Send messages to agent terminals for multi-agent communication
- **AppleScript Integration**: Native macOS Terminal control

## Installation

Add to Claude Code:
```bash
codex mcp add CM bash /path/to/cm_server.sh
```

## Usage

The CM MCP server provides two main tools:

1. `list_agent_terminals` - List all terminals running agents
2. `send_to_agent` - Send messages to specific agents

## Requirements

- macOS (uses AppleScript for Terminal control)
- Bash
- jq (optional, but recommended)

## Multi-Agent Communication

Enable AI agents to communicate with each other through Terminal windows, facilitating collaborative problem-solving and task coordination.
