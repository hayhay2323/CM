# CM - Codex Manager

CM 是一个纯 Bash 实现的 MCP (Model Context Protocol) server，用于列出所有正在运行 agent CLI 的 Terminal 窗口。

## 功能

- 🔍 列出所有运行 agent CLI（如 codex、aider 等）的 Terminal 窗口
- 📊 显示窗口 ID、名称、TTY 和进程信息
- ⚡ 零依赖（除了 jq，macOS 通常已安装）
- 🛠️ 纯 Bash + AppleScript 实现

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

**`list_agent_terminals`**

列出所有正在运行指定 agent CLI 的 Terminal 窗口。

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
        "command": "codex"
      }
    }
  ]
}
```

### 本地测试

可以直接通过 JSON-RPC 测试：

```bash
# 初始化
echo '{"jsonrpc":"2.0","method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}},"id":1}' | ./cm_server.sh

# 获取工具列表
echo '{"jsonrpc":"2.0","method":"tools/list","params":{},"id":2}' | ./cm_server.sh

# 调用工具
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_agent_terminals","arguments":{}},"id":3}' | ./cm_server.sh

# 自定义 agent 名称
echo '{"jsonrpc":"2.0","method":"tools/call","params":{"name":"list_agent_terminals","arguments":{"agentNames":["codex","aider","cursor"]}},"id":4}' | ./cm_server.sh
```

## 项目结构

```
CM/
├── cm_server.sh              # 主服务器脚本
├── mcpserver_core.sh         # MCP SDK 核心
├── assets/
│   ├── tools_list.json       # 工具定义
│   └── mcpserverconfig.json  # 服务器配置
├── mcpserver.log             # 日志文件（运行时生成）
└── README.md                 # 本文件
```

## 工作原理

1. **AppleScript 获取窗口信息**: 使用 AppleScript 查询 Terminal.app 的所有窗口和标签页，获取窗口 ID、名称和 TTY
2. **进程检测**: 使用 `ps -t <tty>` 命令检测每个 TTY 上运行的进程
3. **Agent 匹配**: 通过 grep 匹配进程名称，识别指定的 agent CLI
4. **JSON 构建**: 使用 jq 或手动拼接构建 JSON 响应

## 限制

- 目前仅支持 macOS Terminal.app（不支持 iTerm2）
- 需要授予 Terminal.app 自动化权限
- 依赖 jq 进行 JSON 处理

## 扩展

可以考虑添加以下功能：

- 支持 iTerm2
- `send_to_terminal`: 发送命令到指定 Terminal 窗口
- `get_terminal_status`: 获取 Terminal 的当前状态
- 实时监控功能

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
