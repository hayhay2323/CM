# CM

CM (Codex Manager) - MCP Server for managing and communicating with AI agent terminals.

## Features

- **List Agent Terminals**: Find all Terminal windows running AI agents (codex, aider, gemini, qwen, iflow, etc.)
- **Send Messages with Source Identity**: Send messages to agent terminals with clear sender identification
- **Group Chat Support**: Send messages to multiple agents simultaneously (broadcast)
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
Send messages to one or more agents with sender identification.

**Single recipient (unicast):**
```javascript
{
  "from": "claude",        // sender name (optional, defaults to "unknown")
  "agentName": "codex",    // target agent
  "message": "Can you help review this code?"
}
```

**Multiple recipients (group chat):**
```javascript
{
  "from": "claude",
  "agentName": ["codex", "gemini", "qwen"],  // array of agents
  "message": "Everyone, what do you think about this architecture?"
}
```

**Message Format in Terminal:**

Single recipient:
```
[claude → codex]: Can you help review this code?
```

Group chat:
```
[claude → codex,gemini,qwen]: Everyone, what do you think about this architecture?
```

The receiving agent sees who sent the message and all recipients. They can reply to sender or the group:
```javascript
{
  "from": "codex",
  "agentName": "claude",  // reply to sender only
  "message": "I think it's solid!"
}
```

```javascript
{
  "from": "codex",
  "agentName": ["claude", "gemini", "qwen"],  // reply to group
  "message": "I agree with the approach, what do others think?"
}
```

### 3. `resources/read` - Query Conversation History

CM automatically records all messages sent through `send_to_agent`. Agents can query conversation history using Resources API.

**Query recent messages:**
```javascript
{
  "uri": "conversation://latest/50"  // Get last 50 messages
}
```

**Query messages with a specific agent:**
```javascript
{
  "uri": "conversation://with/codex"  // All messages involving codex
}
```

**Search messages by keyword:**
```javascript
{
  "uri": "conversation://search?q=architecture"  // Search for "architecture"
}
```

**Response format:**
```
2025-11-02T12:00:00Z [claude → codex]: Help me optimize this code
2025-11-02T12:01:00Z [codex → claude]: Use list comprehension instead of loops
2025-11-02T12:05:00Z [claude → gemini,qwen]: Codex suggested list comprehension, thoughts?
```

**Storage:**
- Messages are stored in `CM/conversations/history.jsonl`
- Format: `{timestamp, from, to, message}` - simple and universal
- Agents decide how to use the history (learning, context, analysis)

**Philosophy:**
CM is just a "dumb pipe" - it records and retrieves messages without understanding their content. The intelligence is in the agents.

## Examples

### Example 1: One-on-One Conversation

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

### Example 2: Group Discussion

**Claude broadcasts to all:**
```
[claude → codex,gemini,qwen]: 我在设计一个分布式系统架构，大家有什么建议？
```

**Codex replies to group:**
```
[codex → claude,gemini,qwen]: 建议使用微服务架构，考虑 gRPC 作为通信协议
```

**Gemini replies to group:**
```
[gemini → claude,codex,qwen]: 同意微服务，但要注意服务发现和负载均衡
```

**Qwen replies to group:**
```
[qwen → claude,codex,gemini]: 可以用 Kubernetes + Istio 来管理，还需要考虑数据一致性
```

**Claude to all:**
```
[claude → codex,gemini,qwen]: 很好的建议！那我们从服务划分开始讨论？
```

## Requirements

- macOS (uses AppleScript for Terminal control)
- Bash
- jq (recommended for JSON parsing)

## Multi-Agent Communication

Enable AI agents to communicate with each other through Terminal windows, facilitating collaborative problem-solving and task coordination. Each agent understands who's talking to them through natural language, no complex protocols needed.
