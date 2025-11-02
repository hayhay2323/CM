# CM - Codex Manager

CM 是一个纯 Bash 实现的 MCP (Model Context Protocol) server，为多 AI Agent 协作提供发现（Discover）、通信（Communicate）和学习（Learn）能力。

## 功能

### 🔍 发现能力（Discover）
- 列出所有运行 agent CLI 的 Terminal 窗口
- 显示 agent 状态（online/idle/busy）
- 发现其他 agents 的可用命令
- 支持动态命令注册

### 💬 通信能力（Communicate）
- 单播：向指定 agent 发送消息
- 群播：向多个 agents 同时发送消息
- 自动记录所有对话历史

### 📊 学习能力（Learn）
- 查询对话历史（最近N条、与特定agent、搜索、时间范围等）
- 协作统计分析（消息数量、活跃协作对、命令使用等）
- 识别协作模式和优化任务分配

### ⚡ 技术特点
- 零依赖（除了 jq，macOS 通常已安装）
- 纯 Bash + AppleScript 实现
- 遵循第一性原理：保持"dumb pipe"设计，不含业务逻辑

## 技术栈

- **Bash**: 主要逻辑
- **AppleScript**: Terminal 窗口信息获取
- **mcp-server-bash-sdk**: MCP 协议处理
- **jq**: JSON 处理（必需）

## 安装

### 1. 检查依赖

确保 jq 已安装：
```bash
which jq || brew install jq
```

### 2. 配置 Claude Code

CM 已经配置在当前项目的 `~/.claude.json` 中：
```json
{
  "mcpServers": {
    "CM": {
      "type": "stdio",
      "command": "/Users/hayhay2323/Desktop/agent-bridge/CM/cm_server.sh",
      "args": [],
      "env": {}
    }
  }
}
```

### 3. 重启 Claude Code

配置更改后需要重启 Claude Code 才能生效。

## 使用方法

### 在 Claude Code 中

1. 启动 Claude Code
2. 运行 `/mcp` 命令查看所有 MCP servers
3. 确认 CM 显示在列表中
4. 使用 `list_agent_terminals` 工具

### 工具说明

#### 1. `list_agent_terminals`

列出所有正在运行指定 agent CLI 的 Terminal 窗口，包含 agent 状态。

**输入参数：**
- `agentNames` (可选): string[] - 要查找的 agent 名称列表，默认 `["codex", "aider"]`

**返回格式：**
```json
{
  "terminals": [
    {
      "windowId": 12345,
      "windowName": "Terminal — codex",
      "tty": "ttys001",
      "agent": {
        "pid": 98765,
        "name": "codex",
        "command": "codex",
        "status": "online"
      }
    }
  ]
}
```

**状态说明：**
- `busy`: 5分钟内有活动
- `idle`: 30分钟内有活动
- `online`: 无近期活动或无历史记录

#### 2. `send_to_agent`

向一个或多个 agent 发送消息（单播/群播）。

**输入参数：**
- `from` (可选): string - 发送者名称
- `agentName`: string | string[] - 目标 agent 名称或名称数组
- `message`: string - 消息内容

**示例：**
```json
// 单播
{"from": "claude", "agentName": "codex", "message": "/help"}

// 群播
{"from": "claude", "agentName": ["codex", "gemini"], "message": "test"}
```

#### 3. `list_agent_commands`

列出 agent 的可用斜杠命令（静态 + 动态注册）。

**输入参数：**
- `agentName` (可选): string - agent 名称，不提供则返回所有 agents

**返回格式：**
```json
{
  "agent": "codex",
  "info": {
    "description": "OpenAI Codex - AI coding assistant",
    "commands": [
      {"name": "/help", "description": "显示所有可用命令"},
      {"name": "/commit", "description": "创建 git commit"}
    ]
  }
}
```

#### 4. `get_collaboration_stats`

获取协作统计数据，分析 agents 之间的协作模式。

**输入参数：**
- `agentName` (可选): string - 特定 agent 名称，不提供则返回整体统计

**返回格式：**
```json
{
  "totalMessages": 42,
  "totalAgents": 4,
  "messagesByAgent": [
    {"agent": "claude", "sent": 20},
    {"agent": "codex", "sent": 15}
  ],
  "mostActiveCollaborations": [
    {"pair": "claude-codex", "count": 25}
  ],
  "commandUsage": [
    {"command": "/help", "count": 5}
  ],
  "timeRange": {
    "earliest": "2025-01-15T10:00:00Z",
    "latest": "2025-01-15T12:00:00Z"
  }
}
```

#### 5. `register_commands`

允许 agent 动态注册自己的命令（运行时扩展能力）。

**输入参数：**
- `agentName`: string - agent 名称
- `commands`: array - 命令列表
  - `name`: string - 命令名称（如 "/analyze"）
  - `description`: string - 命令描述

**示例：**
```json
{
  "agentName": "custom_agent",
  "commands": [
    {"name": "/analyze", "description": "分析代码"},
    {"name": "/optimize", "description": "优化性能"}
  ]
}
```

### Resources（对话历史查询）

CM 提供多种对话历史查询方式，支持 MCP Resources API。

#### 可用的 Resource URIs

| URI 格式 | 描述 | 示例 |
|---------|------|------|
| `conversation://latest/{N}` | 最近 N 条消息 | `conversation://latest/10` |
| `conversation://with/{agent}` | 与特定 agent 相关的消息 | `conversation://with/codex` |
| `conversation://search?q={query}` | 搜索消息内容 | `conversation://search?q=help` |
| `conversation://between/{a1}/{a2}` | 两个 agents 之间的对话 | `conversation://between/claude/codex` |
| `conversation://time/{start}/{end}` | 时间范围内的消息 | `conversation://time/2025-01-15T10:00:00/2025-01-15T12:00:00` |
| `conversation://pattern/{regex}` | 匹配正则表达式的消息 | `conversation://pattern/commit` |

**查询示例：**
```bash
# 查询 claude 和 codex 之间的所有对话
echo '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"conversation://between/claude/codex"}}' | ./cm_server.sh

# 查询最近1小时的消息
echo '{"jsonrpc":"2.0","id":1,"method":"resources/read","params":{"uri":"conversation://time/2025-01-15T10:00:00/2025-01-15T11:00:00"}}' | ./cm_server.sh
```

### 本地测试

可以直接通过 JSON-RPC 测试：

```bash
# 初始化
echo '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}' | ./cm_server.sh

# 获取工具列表
echo '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}' | ./cm_server.sh

# 测试 list_agent_terminals
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_agent_terminals","arguments":{}},"id":3}' | ./cm_server.sh

# 测试 send_to_agent（单播）
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"send_to_agent","arguments":{"from":"claude","agentName":"codex","message":"/help"}},"id":4}' | ./cm_server.sh

# 测试 list_agent_commands
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_agent_commands","arguments":{"agentName":"codex"}},"id":5}' | ./cm_server.sh

# 测试 get_collaboration_stats
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"get_collaboration_stats","arguments":{}},"id":6}' | ./cm_server.sh
```

## 项目结构

```
CM/
├── cm_server.sh                      # 主服务器脚本（5个工具实现）
├── mcpserver_core.sh                 # MCP SDK 核心（协议处理）
├── assets/
│   ├── tools_list.json               # 工具定义（5个工具）
│   ├── mcpserverconfig.json          # 服务器配置
│   └── agent_commands.json           # 静态命令目录（68个命令）
├── conversations/
│   ├── history.jsonl                 # 对话历史（JSONL格式）
│   └── agent_commands_dynamic.json   # 动态注册的命令
├── mcpserver.log                     # 日志文件（运行时生成）
└── README.md                         # 本文件
```

## 工作原理

1. **AppleScript 获取窗口信息**: 使用 AppleScript 查询 Terminal.app 的所有窗口和标签页，获取窗口 ID、名称和 TTY
2. **进程检测**: 使用 `ps -t <tty>` 命令检测每个 TTY 上运行的进程
3. **Agent 匹配**: 通过 grep 匹配进程名称，识别指定的 agent CLI
4. **JSON 构建**: 使用 jq 或手动拼接构建 JSON 响应

## 核心设计原则

CM 遵循第一性原理设计：

1. **Discover（发现）**: 提供 agent 发现能力，不做选择
2. **Communicate（通信）**: 提供消息路由，不管内容
3. **Learn（学习）**: 提供数据访问，不做推理

CM 是"dumb pipe"（傻瓜管道），不包含任何业务逻辑，所有决策由 agents 自己完成。

## 限制

- 目前仅支持 macOS Terminal.app（不支持 iTerm2）
- 需要授予 Terminal.app 自动化权限
- 依赖 jq 进行 JSON 处理
- 对话历史存储在本地 JSONL 文件中（无持久化数据库）

## 协作场景示例

### 场景 1: 代码审查流程
```javascript
// Claude 发现 Codex 有 /review 命令
list_agent_commands({"agentName": "codex"})

// Claude 让 Codex 审查代码
send_to_agent({"from": "claude", "agentName": "codex", "message": "/review"})

// 审查完成后让 Codex 提交
send_to_agent({"from": "claude", "agentName": "codex", "message": "/commit"})
```

### 场景 2: 多 Agent 并行分析
```javascript
// Gemini 协调多个 agents 分析不同方面
send_to_agent({"from": "gemini", "agentName": "qwen", "message": "/analyze"})
send_to_agent({"from": "gemini", "agentName": "codex", "message": "/diff"})
send_to_agent({"from": "gemini", "agentName": "claude", "message": "/review"})

// 分析协作统计，优化任务分配
get_collaboration_stats({})
```

详细示例请参考 `/tmp/agent_collaboration_examples.md`。

## 故障排查

### CM 没有出现在 `/mcp` 列表中

1. 检查 `~/.claude.json` 配置是否正确
2. 确认脚本路径正确且有执行权限: `ls -l CM/cm_server.sh`
3. 重启 Claude Code

### 工具调用返回空数组

- 确认是否有 Terminal 窗口正在运行
- 确认窗口中是否运行了指定的 agent（默认 codex 或 aider）
- 尝试自定义 `agentNames` 参数

### Permission denied

```bash
chmod +x CM/cm_server.sh CM/mcpserver_core.sh
```

## 许可

MIT License
