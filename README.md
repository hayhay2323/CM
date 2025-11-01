# CM

CM (Codex Manager) - MCP Server for managing and communicating with AI agent terminals.

## Features

- **List Agent Terminals**: Find all Terminal windows running AI agents (codex, aider, gemini, qwen, iflow, etc.)
- **Send Messages with Source Identity**: Send messages to agent terminals with clear sender identification
- **Natural Conversation Flow**: Agents know who's talking to them and can reply accordingly
- **AppleScript Integration**: Native macOS Terminal control

## Philosophy

Based on first principles thinking, CM is designed as a simple "walkie-talkie" system for AI agents:
- No complex message queues (Terminal already has input buffers)
- No elaborate orchestration (agents are smart enough to coordinate)
- Just clear **message source identification** and **simple routing**

Like @mentions in Slack - agents know who's talking and can reply back naturally.

## Installation

Add to Claude Code:
```bash
codex mcp add CM bash /path/to/cm_server.sh
```

## Usage

The CM MCP server provides two main tools:

### 1. `list_agent_terminals`
Find all terminals running AI agents.

```javascript
{
  "agentNames": ["codex", "claude", "gemini"]  // optional
}
```

### 2. `send_to_agent`
Send messages to specific agents with sender identification.

```javascript
{
  "from": "claude",        // sender name (optional, defaults to "unknown")
  "agentName": "codex",    // target agent
  "message": "Can you help review this code?"
}
```

**Message Format in Terminal:**
```
[claude → codex]: Can you help review this code?
```

The receiving agent sees who sent the message and can reply:
```javascript
{
  "from": "codex",
  "agentName": "claude",
  "message": "Sure! The code looks good, just one suggestion..."
}
```

## Example: Multi-Agent Conversation

**Claude to Codex:**
```
[claude → codex]: 帮我优化这段 Python 代码的性能
```

**Codex to Claude:**
```
[codex → claude]: 已经分析完成，建议使用列表推导式替代循环
```

**Claude to Gemini:**
```
[claude → gemini]: Codex 建议用列表推导式，你觉得呢？
```

**Gemini to Claude:**
```
[gemini → claude]: 同意！而且可以考虑用 NumPy 进一步优化
```

## Requirements

- macOS (uses AppleScript for Terminal control)
- Bash
- jq (recommended for JSON parsing)

## Multi-Agent Communication

Enable AI agents to communicate with each other through Terminal windows, facilitating collaborative problem-solving and task coordination. Each agent understands who's talking to them through natural language, no complex protocols needed.
