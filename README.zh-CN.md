# agent.nvim

在 Neovim 中运行本机 Claude Code、Codex 或自定义交互式 CLI。插件管理终端窗口和单会话生命周期，CLI 自己负责登录、对话、工具调用和测试执行。

[English](README.md) · [反馈问题](https://github.com/WYJRichhhhh/agent.nvim/issues)

**实验性插件**。终端核心使用 Lua、无强制插件依赖，Codex/Claude 修改跟踪可选使用 Node.js helper，要求 Neovim 0.11+；当前在 macOS、Neovim 0.12 测试。Linux、Windows 和不同 CLI 版本的完整体验尚未逐一验证，欢迎反馈。插件独立安装，不要求作者的个人配置、tmux、Ghostty、主题插件或 zsh。

## 解决什么问题，谁能用

将本机交互 CLI 放在 Neovim 的常驻终端中，通过快捷键显示、聚焦和隐藏。隐藏不会关闭进程、清空未提交输入或另开会话，实际 AI 能力由 CLI 自己实现。

任何已有可用 `codex`、`claude` 或其他交互 CLI 的 Neovim 用户都能使用。至少一个后端可执行文件必须存在于 **Neovim 的 PATH** 中。正常使用无需 Python；Python 3 只用于开发测试。

默认使用参数数组直接启动 CLI，**不启动系统 shell，也不依赖 zsh**。bash、fish 等用户无需更换 shell，但 shell alias、函数和未传入 Neovim 的环境设置不能自动继承。GUI 启动 Neovim 与登录 shell 的 PATH 也可能不同，详见后面的配置和排查说明。

插件没有第二套密钥、登录或模型设置；沿用 CLI 从继承环境和本机配置读取的设置。如果你覆盖 HOME、CODEX_HOME 等环境变量，CLI 自己的配置解析结果也会相应改变。

### 在终端里查看帮助、隐藏和切换

执行 `:Agent help` 或 `:help agent.nvim` 查看操作指南。在 CLI 输入状态下，先依次按 **Ctrl-\、Ctrl-n** 进入终端普通模式：`q` 隐藏窗口，`?` 打开帮助，`i` 返回 CLI 输入。帮助窗口用 `:q` 关闭，再 `:Agent open` 回到会话。这两个局部按键不会拦截 CLI 输入状态中的 q 和 ?。

**隐藏**用配置好的 `Alt-a`、普通模式的 `q` 或 `:Agent hide`，任务与未提交输入继续保留；**停止**用 `:Agent stop`，会结束进程。**切换后端**用 `:Agent select`，或终端普通模式下使用示例配置的 `<leader>as`；选择另一个后端并确认后才会停止旧进程。首次成功启动会显示一次操作提示，可用 `terminal.show_hint = false` 关闭。

## 快速体验

下面的 lazy.nvim 安装示例提供这些快捷键；插件自身不创建全局映射：

| 入口 | 行为 |
| --- | --- |
| `<leader>aa` 或 `Alt-a` | 未启动时启动；隐藏时显示；在代码区时聚焦；已在 Agent 内时隐藏 |
| `<leader>as` | 打开后端菜单；选择其他后端后确认停止旧会话并切换 |
| `:Agent start claude` | 明确启动 Claude Code |
| `:Agent start codex` | 明确启动 Codex |
| `:Agent resume codex` | 在 CLI 正常退出后，打开 Codex 历史对话列表恢复会话 |
| `:Agent hide` | 隐藏界面，进程继续运行 |
| `:Agent open` | 显示现有会话；没有会话时启动 |
| `:Agent stop` | 停止会话并清理终端 buffer |
| `:Agent status` | 查看后端、启动目录、进程编号和显示状态 |
| `:Agent health` | 检查版本和后端可执行文件 |

`<leader>` 使用你自己的 Neovim 配置。终端内 `Alt-a` 仍可隐藏，Esc、Ctrl-C 保持原生 CLI 的用途。按 `Ctrl-\` 再按 `Ctrl-n` 可以进入终端普通模式，之后按 `q` 隐藏，或按 `i` 返回终端输入。

首次自动发现到多个后端时弹出选择列表，选择在本次 Neovim 进程中保留。只有一个后端时直接启动；未发现可执行文件时提示检查 PATH。插件不检查或读取认证文件。

`:Agent health` 会先通过 lazy 加载插件，再执行标准健康检查；插件已加载后也可以直接使用 `:checkhealth agent`。

## Codex 实时修改跟踪（可选开启）

保留 **Codex 原生 TUI**，同时在 Neovim 查看它的修改。需要 **Node.js 22+**、macOS/Linux，以及支持 `--remote`、App Server 和 capability-token 的 Codex；已在 **macOS / Codex 0.163.0** 实测。Windows 可以使用原来的纯终端模式。无需安装 npm 包、SDK，也无需额外密钥或登录。Claude 和自定义后端仍使用原来的终端方式。

```lua
opts = {
    codex = { enabled = true },
    window = { layout = "right", width = 0.42 },
    review = { follow = true },
    terminal = { hide_key = "<M-a>" },
}
```

可将这些映射加入 lazy.nvim 的 `keys` 表。它们使用普通模式，CLI 输入状态下先按 **Ctrl-\、Ctrl-n**：

| 示例快捷键 | 命令 | 行为 |
| --- | --- | --- |
| `<leader>ar` | `:Agent changes` | 修改文件列表，选择后打开文件 |
| `<leader>ad` | `:Agent diff` | 整轮红绿差异，只读 |
| `<leader>ag` | `:Agent gitdiff` | 选择 worktree 查看当前 Git 差异（含已有修改） |
| `<leader>aD` | `:Agent filediff` | 最近选择文件的差异 |
| `<leader>af` | `:Agent follow` | 开启/暂停自动跟随 |
| `<leader>ae` | `:Agent code` | 聚焦最近选择/修改的源文件 |
| `<leader>ah` | `:Agent turns` | 选择当前插件会话内的历史轮次 |
| `<leader>an` / `<leader>ap` | `:Agent next` / `:Agent prev` | 在源文件中跳到下一处/上一处修改 |

成功修改文件后，原编辑窗口打开该文件：新增行使用 `DiffAdd` 绿色背景，删除内容以 `DiffDelete` 红色虚拟行显示，不写入源文件。批量事件只打开最后一个目标，完整清单仍保留；焦点留在 Codex，方便继续输入。建议使用右侧分屏；浮窗可能遮住代码。

`Agent changes`（示例键 `<leader>ar`）列出当前 Agent 会话保留轮次内的所有修改文件，按路径去重、使用最近记录；默认保留最近 20 轮。已安装 Telescope 时提供模糊搜索和红绿补丁预览，回车选择；未安装则使用 `vim.ui.select`，可用 `review.picker = "ui_select"` 强制使用后者。选择当前轮文件后在代码窗口显示真实文件和跟随时相同的红绿标记，并暂停自动跳转；历史/已删除文件打开只读补丁，避免把旧行号标在新文件上。取消选择不改变跟随状态。`Agent turns` 仍只列所选轮次的文件。

切换到代码窗口或隐藏 Agent 不会关闭跟随：阅读时保留当前文件、光标和滚动位置，后台继续记录修改；回到 Agent 后自动跟到最新修改。开始编辑才会**自动暂停跟随**；回到 Agent 不会取消编辑或手动触发的暂停。`:Agent follow` 切换跟随状态；`:Agent pause` 明确暂停。任何未保存的 buffer 都不会被自动替换或重新加载；保存后再恢复跟随。未修改的已打开文件可以自动重新加载，保留原有 `autoread` 配置。

差异窗口是只读 unified diff，按 `q` 返回原 buffer，按 `gf` 打开 diff 光标所在的源文件；不会停止 CLI。历史轮次和已删除文件优先显示补丁，避免把旧行号标到当前版本上。历史默认保留最近 20 轮，范围是本次插件会话；**不等于 Git 提交历史，也不是跨进程的聊天记录库**。

### 数据来源与范围

直接消费官方 App Server 的 `fileChange` 和 `turn/diff/updated` 事件，不解析 TUI 文本。列表只记录成功的文件修改，尚未批准、失败和被拒绝的修改不会混入。对比基准由 Codex 该轮记录的修改决定，不直接对比 Git HEAD，因此不会自动把开始任务前已有的全部改动算进去。

Git 项目默认启用 `review.git_fallback`：在任务开始时记录本地工作内容，在工具完成和整轮结束后检查差异，补上 Ruby/Python/shell/格式化器等未产生原生事件的写入，列表标记 `[Git]`。保存任务前已有未提交/未跟踪内容，干净文件使用固定提交基线，不逐个复制进快照，避免直接混入已有修改；任务中新建 worktree 则以其提交内容建立初始基线。它无法证明具体是谁写入文件：并发保存的其他编辑也可能被收集。忽略文件、二进制文件、超大文件和超出快照预算的文件不在兜底范围；提交前仍应检查 `git diff`。超过 `review.max_diff_bytes` 的大补丁会跳过并提示。默认只打开启动目录及同一 Git 项目已注册的 worktree 中的文件；`review.worktrees = false` 可关闭跨 worktree 支持，任意外部路径和符号链接目标仍会检查。

协议参考：[Codex App Server](https://learn.chatgpt.com/docs/app-server)、[CLI 命令](https://learn.chatgpt.com/docs/developer-commands?surface=cli)。

### tmux zoom、滚轮与已有 worktree

终端/tmux zoom 改变尺寸后，浮窗和右侧/底部分屏会在 Neovim 布局稳定后重算尺寸，并同步 PTY。比例配置跟随新尺寸，固定行列配置在可用空间内保持固定；不重启进程、不抢焦点、不清空未提交输入。

默认 `terminal.capture_mouse = true`：**仅在 Agent buffer 获得焦点时**临时启用 Neovim 鼠标，让 tmux 把滚轮转发给内层应用，而非进入自己的 copy-mode。离开、隐藏或停止时恢复原 `mouse` 设置，也保留你期间的显式修改。可设为 `false` 关闭。若 tmux 已处于 copy-mode，请先退出该模式。原生 TUI 历史由 CLI 滚动；查看 Neovim 保留的终端输出可先按 **Ctrl-\、Ctrl-n**，再 **Ctrl-b / Ctrl-f** 翻页，`i` 返回输入。

`:Agent gitdiff` 可以选择当前项目的 worktree，查看其相对 HEAD 的已跟踪文件差异。它**包含任务开始前已有的修改和暂存修改，不包含未跟踪文件**，用于检查当前工作区，不宣称都是 Agent 所改。刚才已经完成、未被旧版捕获的任务也能这样查看。diff 中 `gf` 打开光标所在文件。

自动兜底的快照总预算为 `review.max_snapshot_bytes`（默认 32 MiB），单文件/补丁上限 `review.max_diff_bytes`（2 MiB）。快照仅在本机使用，生成补丁用的私有临时文件会在对比后删除。检测串行合并执行，不逐按键扫描。自动会话差异从后续任务开始采集，不能凭空重建旧任务开始前的基线；旧任务可用 `gitdiff` 检查当前工作区。`git_fallback` 和 `worktrees` 可以分别关闭。

### 进程、登录与清理

插件启动一个本机会话专属的 App Server，原生 TUI 和观察连接共同连接它。Node helper 只使用标准库，无 npm 依赖。服务仅监听 loopback，并使用每次生成的随机 capability token；该 token 通过进程管道和环境传递，不由插件写入配置或历史。它只是本地传输鉴权，不是 OpenAI API Key。Codex 仍读取普通 shell 中那套用户配置、环境和登录；观察连接不发起任务、不回答审批。

会过滤 Codex 自动生成标题和子 Agent 的线程。新 TUI 会话尚未落盘时持续等待订阅；订阅成功后读取最近一轮文件条目，补回启动期间错过的修改。旧服务若不支持分页读取，仍可处理实时事件。

隐藏保留 TUI、helper 和服务；停止、确认切换后端、删除终端 buffer、退出原生 TUI 或退出 Neovim 时会清理它们。连接异常会停止当前 CLI 并报告，不会悄悄另开第二个会话。CLI 自然退出后仍可检查已收到的差异，直到显式停止/重启时清理；resume 沿用原生恢复流程，不会完整重建以前所有轮次。

`backends.codex.command[1]` 必须是 Codex 可执行文件，或能原样转发 `app-server` 参数的 wrapper。服务使用 `{ executable, "app-server", ... }` 启动，不会把额外 TUI 参数复制给服务；公共设置请放在普通 Codex 配置/环境中。`{ "zsh", "-ic", "codex" }` 这样的 shell 参数数组仅适用于关闭跟踪时的纯终端模式。

设置 `codex.enabled = false` 可退回原来的直接终端模式。`:Agent health` 检查依赖，`:Agent status` 查看连接、轮次和跟随状态。此集成仍属实验功能；Linux 尚未用真实 CLI 验证，后续 Codex 协议变化可能需要调整适配。

## Claude Code 修改跟踪（可选开启）

Claude 保留原生交互 TUI，使用**当前会话专用的命令 Hooks**接入，不使用 Codex App Server：

```lua
opts = {
    claude = { enabled = true },
    codex = { enabled = true }, -- 可选；两个后端各有适配器
    window = { layout = "right", width = 0.42 },
    review = { follow = true, picker = "auto" },
}
```

要求 **macOS/Linux、Node.js 22+、Git**，以及支持 `--settings` 和生命周期/工具 Hooks 的 Claude Code。非 Git 目录也需要 Git，用 `git diff --no-index` 生成文本补丁。已在 **macOS、Claude Code 2.1.210** 上验证真实工具修改、Hook 回传、Neovim 红绿标记及自然退出。Linux 尚未用真实 Claude 会话验证；Windows 目前使用纯终端模式。

通过 `SessionStart`、`UserPromptSubmit`、`PreToolUse`、`PostToolUse`、`PostToolUseFailure`、`Stop`、`SessionEnd` 接收事件。提交问题开始新一轮；`Edit`、`Write`、`MultiEdit`、`NotebookEdit` 执行前保存有大小限制的文件原文，执行后按磁盘实际内容生成相对本轮首次记录的累计补丁。Git 项目在 `review.git_fallback=true` 时另用任务前基线检测脚本及已注册 worktree 的修改。

Claude 复用与 Codex 相同的文件清单、Telescope 搜索/补丁预览、红绿标记、跟随及阅读保持逻辑。`changes / diff / filediff / follow / code / turns / next / prev / gitdiff` 均可使用。CLI 退出后可用 `:Agent resume claude` 打开 Claude 原生历史选择器；不会重建旧对话的补丁。

插件只在自己启动的 CLI 参数中增加临时 `--settings` JSON，保留普通用户/项目设置；若 `backends.claude.command` 已有一个 JSON 或文件形式的 `--settings`，在内存中合并其选项和 Hooks，不改写原文件。该文件只在启动时读取，后续变更需重启会话。`command[1]` 应是 CLI 或原样转发追加参数的 wrapper；吞掉参数的 shell 包装命令不支持跟踪模式。命令 Hook 使用配置的 Node 可执行文件和 POSIX shell 转义，不依赖交互式 zsh/fish 的初始化文件。

Hook 向仅监听本机、随机令牌鉴权的 HTTP 服务发送精简事件，不传输提示词、工具返回正文、文件内容或认证凭证；本地适配器自行读取允许范围内的文件生成补丁。令牌通过管道/环境传递，不写入 CLI 参数设置或持久配置。插件不调用 Anthropic SDK/API，不改模型、登录或审批。Hook 客户端保持静默，即使观察通道失败也成功返回，不阻止 Claude 工具执行；快照处理会短暂等待，客户端最长等待 `claude.hook_timeout`（默认 10 秒），超时可能漏掉基线或更新，服务能检测到时会警告。隐藏保留 helper，停止/切换/删终端/退出 Neovim 会清理；自然退出后已收到的修改可继续查看，直到显式停止或重启。

### Claude 的限制与排查

- **必须允许 Hooks**：未接受目录信任、`disableAllHooks`、组织策略、`--bare`、`--safe-mode` 等可能使跟踪失效。显式冲突的启动设置会报错；全局/策略限制可能只表现为 `:Agent status` 的 `bridge.state="waiting"`，等待后会提示检查 Claude `/hooks`。插件不会绕过策略或强行启用 Hooks。设置 `claude.enabled=false` 可退回原始终端模式。
- **无法追溯或旁接任意已有 CLI**：只跟踪由插件启动的会话及后续捕获的修改，恢复历史对话也不会重建此前补丁。旧任务可用 `:Agent gitdiff` 查看当前相对 HEAD 的已跟踪文件差异，但它含任务前已有修改。
- **非 Git 目录仅覆盖已接入的文件工具**：Shell、自定义/MCP 工具、任意后台进程、未经过已支持文件工具的移动/删除、缺失有效修改前 Hook 的写入，需要 Git 兜底，否则无法捕获。暂未消费 Claude 专属 `bashEditDiff`、文件系统 `FileChanged` 或对话日志。Notebook 显示 JSON 文本补丁，不提供单元格级专用界面。
- **磁盘变化不等于精确归因**：并发写入、失败工具已造成的部分修改可能被收集。与父会话 ID 相同的子 Agent 工具修改归入父轮次，不同会话 ID 被忽略；没有独立的子 Agent 审查窗。跨轮次的后台写入可能归到后续扫描。
- **大小及范围限制仍适用**：二进制、超大、范围外或符号链接目标会跳过。Git 兜底不含忽略文件，但范围内的文本文件即使被 Git 忽略，仍可由直接文件工具 Hooks 捕获。原生修改前缓存和 Git 快照各自受 `review.max_snapshot_bytes` 限制；单文件/补丁受 `review.max_diff_bytes` 限制。默认保留最近 20 轮，历史/删除文件显示只读补丁。
- 真实模型实测覆盖 macOS 文件工具修改；本地自动化额外覆盖累计编辑/撤销、失败工具、设置合并、Hook 鉴权、会话隔离、Git 脚本/worktree 修改、隐藏/显示及清理。其他 CLI 版本、组织策略或平台可能不同，反馈时可附版本和 `:Agent status`，勿附凭证。

官方参考：[Claude Code Hooks](https://code.claude.com/docs/en/hooks)、[CLI 配置参数](https://code.claude.com/docs/en/cli-reference)。

## 让 Agent 打开并讲解代码

开启任一 `codex.enabled=true` / `claude.enabled=true` 适配器后，默认 `code.enabled=true` 会为**本次 CLI 会话**接入名为 `agent_nvim_editor` 的 stdio MCP 服务，提供 `show_code` 和 `clear_code`。不修改全局 MCP 文件、登录、模型或审批策略，也不增加 SDK 依赖。自定义后端和纯终端模式不会注入这些工具。

可以直接问：

> 找到订单校验的核心实现，使用 show_code 在左侧打开文件，标出关键代码并加简短说明。先不要修改文件。

Agent 正常搜索/读文件后提交路径和行号。左侧打开真实文件、定位关键范围并显示行尾说明；讲解高亮使用 `AgentCodeHighlight`（默认链接 `Visual`），与修改 diff 的红绿标记区分。默认焦点及终端输入模式留在 Agent，只有第一个文件会加载；其他位置从列表选择。工具也可显式请求 `focus=true`。参数示例：

```json
{
  "title": "订单校验",
  "locations": [
    {
      "file": "src/orders.py",
      "ranges": [
        { "start": 42, "end": 58, "label": "派发前校验" }
      ]
    }
  ],
  "focus": false
}
```

| 命令 / 建议键位 | 用途 |
| --- | --- |
| `:Agent locations` / `<leader>al` | 选择讲解文件/位置 |
| `:Agent code` / `<leader>ae` | 聚焦当前讲解；没有讲解时聚焦所选/最近修改文件 |
| `:Agent next` / `prev` / `<leader>an` / `ap` | 有讲解时切换关键范围/文件，否则跳转修改块 |
| `:Agent clear` / `<leader>ac` | 清除讲解标记和位置列表 |
| `:Agent follow` / `<leader>af` | 清除讲解并切换修改跟随 |

插件不创建全局键位，按需加入 lazy.nvim 的 `keys`：

```lua
{ "<leader>al", "<cmd>Agent locations<cr>", desc = "Agent 讲解位置" },
{ "<leader>ac", "<cmd>Agent clear<cr>", desc = "清除 Agent 讲解高亮" },
```

讲解会暂停修改跟随，避免接下来的修改立即把视图跳走。主动打开修改文件或 diff 会替换讲解。清除标记不会偷偷恢复跟随；按 `af` 可恢复。标记文件开始编辑或重新加载后会清除失效高亮；重新选择位置时再次校验。隐藏/显示保留讲解，停止/切换后端清理；CLI 自然退出后仍可查看，直到显式停止或重启。

文件必须存在，默认限于启动目录和已发现的同项目注册 worktree。展示前校验文件及范围；源窗口或目标 buffer 有未保存内容时拒绝切换/重载，保留原文。目录失效、二进制/超大文件、行号越界、源窗口不可用都会返回工具错误。每个范围可提供 `expected_text`，与该范围全文精确比对（换行规范化），帮助检测读取后又变化的代码；后续位置切换也按捕获的文本验证。本机随机令牌鉴权的中继需收到 Neovim 实际响应才返回成功；会话停止、过期或无响应会返回错误。工具不暴露 shell 或写文件操作。

配置：

```lua
code = {
    enabled = true, -- 需要开启 Codex/Claude 适配器；false 不注入 MCP
    max_locations = 20,
    max_ranges = 50, -- 每个位置
    max_highlight_lines = 1000, -- 每个位置
    max_file_bytes = 2 * 1024 * 1024,
}
```

限制：Agent 自行决定是否调用工具，需要时明确要求 `show_code`。已运行的 CLI 须正常停止后重新启动才能发现新工具；原生 MCP 权限和组织策略仍生效，出现审批时在 CLI 内处理。Claude 启动参数已有的 `--mcp-config` JSON/文件会在内存合并，不改原文件；`agent_nvim_editor` 是保留名称。Codex 使用本次 App Server 的临时配置，并向 stdio 服务透传中继环境变量。这是展示能力，不保证 Agent 判断的业务语义正确；支持普通 UTF-8 文本和从 1 开始、含末行的范围，不做 AST 位置跟踪或持久化代码导览。编辑后行号/片段可能过时；尚未实现自动发送未保存 buffer 或可视选区。

验证：macOS 上真实 Claude 已完成模型调用工具、打开源文件与高亮；真实 Codex App Server 已发现两个 MCP 工具（该检查未调用模型）。两个后端的本地端到端测试覆盖 stdio/中继/UI 回执、焦点、toggle、清除、无效行号、旧片段、未保存内容及清理；真实 Neovim UI 验证了终端输入模式保持。其他 CLI/平台/策略组合仍需反馈验证。

## 单会话规则

一个 Neovim 实例同时维护一个 Agent 会话。显示和隐藏复用同一终端 buffer 与进程，不会清空未提交的输入。CLI 在隐藏时仍可以继续运行任务。

启动时确定工作目录，之后 Neovim 的 `:cd` 或 mini.files 的 `g=` 不会改变现有会话的目录。标题显示后端及完整启动目录。

切换后端可以随时按 `<leader>as` 或执行 `:Agent select`：当前后端会带有标记，选回它只聚焦；选择另一个后端后会询问是否停止旧进程。取消保留进程与未提交输入，确认才切换。`Alt-a` 和 `<leader>aa` 只负责显示/聚焦/隐藏。

单会话表示确认切换后会替换旧进程，不会替每个后端各保留一个运行进程，也不会自动恢复各自历史对话。历史仍由原生 CLI 管理。

需要换工作目录，或希望明确地新建会话时，可以停止后重新启动：

```vim
:Agent stop
:cd ~/projects/my-app
:Agent start codex
```

异常退出后保留终端输出。`:Agent open` 用于查看退出信息，`:Agent start` 明确创建新会话。插件不会自动恢复历史对话，也不在退出 Neovim 后保持原进程运行。

需要重新启动 CLI 来刷新配色时，先在 Codex 中 `/quit`，再用 `:Agent resume codex` 打开 `codex resume` 的历史选择器。它拒绝替换仍在运行的进程，退出会话优先沿用原启动目录。其他后端可配置 `resume_command` 参数数组；未配置时不会猜测恢复命令。

## 独立使用和 lazy.nvim

安装示例：

```lua
{
    "WYJRichhhhh/agent.nvim",
    main = "agent",
    cmd = { "Agent" },
    keys = {
        {
            "<leader>aa",
            function() require("agent").focus() end,
            desc = "打开或聚焦 AI Agent",
        },
        {
            "<M-a>",
            function() require("agent").focus() end,
            mode = { "n", "t" },
            desc = "唤起/隐藏 AI Agent",
        },
        { "<leader>as", "<cmd>Agent select<cr>", desc = "切换 AI Agent 后端" },
    },
    opts = {
        backend = "auto",
        terminal = { hide_key = "<M-a>" },
    },
}
```

普通运行时安装也可以使用，只需将插件加入 runtimepath，再调用 `require("agent").setup(opts)`。`plugin/agent.lua` 注册 `:Agent`；加载模块和执行 `setup()` 不启动 CLI，也不联网。

插件默认不创建全局按键，使用者在自己的配置中定义。`terminal.hide_key` 只在 Agent buffer 内注册；默认 `false` 表示不创建该局部映射。全局和局部映射建议使用同一个键。

## 配置

```lua
require("agent").setup({
    backend = "auto", -- auto / claude / codex / 已注册名称
    cwd = function() return vim.fn.getcwd() end,
    env = {}, -- 继承父进程环境，在这里覆盖个别字符串变量
    window = {
        layout = "float", -- float / right / bottom
        width = 0.85,     -- 不大于 1 时为比例，大于 1 时为列数
        height = 0.85,    -- 不大于 1 时为比例，大于 1 时为行数
        border = "rounded",
    },
    terminal = {
        start_insert = true,
        hide_key = false,
        show_hint = true,
        capture_mouse = true,
    },
    codex = { enabled = false, node = "node", startup_timeout = 15000 },
    claude = { enabled = false, node = "node", startup_timeout = 15000, hook_timeout = 10000 },
    review = { follow = true, history_limit = 20, max_diff_bytes = 2 * 1024 * 1024, restrict_to_cwd = true,
        git_fallback = true, worktrees = true, max_snapshot_bytes = 32 * 1024 * 1024 },
    backends = {
        claude = { label = "Claude Code", command = { "claude" }, resume_command = { "claude", "--resume" }, env = {} },
        codex = { label = "Codex", command = { "codex" }, resume_command = { "codex", "resume" }, env = {} },
    },
})
```

环境覆盖顺序为：Neovim 的环境、全局 `env`、后端 `env`。PATH、代理和 CLI 的本地登录配置沿用相同用户的运行环境；插件不创建第二套 API Key 设置，也不自动安装或登录 CLI。

默认用参数数组启动可执行文件，不经过 shell。shell alias、函数和仅在交互 shell 启动脚本中设置的变量，不一定存在于 Neovim 的环境中。需要它们时可以指定包装脚本，或者显式指定 shell，例如 `command = { "zsh", "-ic", "exec codex" }`。这个 shell 示例是显式选择，不是插件默认行为。shell 命令字符串由用户自己配置，插件不拼接文件路径或用户输入。

修改配置不会重启已有会话；停止并重新启动后，才会使用新的启动参数、环境和目录。

## 配色

Agent 窗口使用 `AgentNormal`、`AgentBorder` 和 `AgentTitle` 高亮组。前景与背景优先取当前主题；透明主题缺少底色时，终端窗口根据 `background` 使用明确的浅色或深色底色。编辑区可以继续透明。

`window.winhighlight` 可以覆盖窗口高亮映射。主题的 `background` 选项应与实际明暗一致，Neovim 会据此回答 CLI 的背景色查询。CLI 自己显式输出的 RGB 颜色仍由 CLI 控制，窗口高亮不能改写这些颜色；Codex 的 `/theme` 主要控制代码块和 diff 的语法主题。

## 注册自定义后端

```lua
require("agent").register_backend("local_agent", {
    label = "本地 Agent",
    command = { "my-agent", "--interactive" },
    env = {},
})
```

注册后可以执行 `:Agent start local_agent`。自动发现只检查 `command[1]` 是否为可执行文件，不启动进程或探测账号状态。

Lua API 包括 `setup`、`register_backend`、`open`、`hide`、`toggle`、`focus`、`start`、`resume`、`stop`、`select`、`status`、`help`、`changes`、`diff`、`filediff`、`follow`、`pause`、`code`、`turns`、`next`、`prev` 和 `gitdiff`。`toggle()` 是按可见性切换；`focus()` 在其他代码窗口中优先聚焦 Agent，已经聚焦时才隐藏。

## 验证

在插件根目录执行，需要 Python 3 作为模拟交互进程：

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/review.lua
nvim --headless -u NONE -l tests/explain.lua
nvim --headless -u NONE -l tests/editor-bridge.lua
nvim --headless -u NONE -l tests/bridge.lua
nvim --headless -u NONE -l tests/claude.lua
nvim --headless -u NONE -l tests/git-bridge.lua
nvim --headless -u NONE -l tests/mouse.lua
node --test tests/websocket.mjs tests/git-review.mjs tests/claude-review.mjs tests/claude-transport.mjs tests/editor.mjs
python3 tests/ui_resize.py # 仅开发测试需要 Python msgpack 包
```

测试使用真实 PTY，但不调用模型或读取认证文件。bridge/传输测试仅启动临时 loopback 服务；还覆盖订阅重试、标题线程过滤、审批不被观察连接代答、未保存内容保护、历史/重命名/删除、红绿渲染和服务清理。覆盖单进程复用、隐藏时交互、未提交输入、工作目录、环境变量、退出处理、分屏、窗口手动关闭和异步后端选择。

真实 CLI 的中文输入法和 TUI 重绘体验仍应在用户自己的终端内验证。

内嵌终端的 ANSI 色板在创建时初始化；CLI 也可能缓存颜色。隐藏、显示不重启进程，因此更换主题后，旧会话可能需要显式退出并恢复才能完整适配。

## 与 tmux 的区别

显示/隐藏相当于在编辑器里切换终端视图，但它不是脱离编辑器运行的 tmux server：关闭 Neovim 会结束插件启动的 CLI 进程。要在编辑器退出后继续执行任务，应使用独立的终端/进程管理方式。

工作目录只在启动时绑定，后续 `:cd`、`:lcd`、`:tcd` 不会改变已运行的进程。首次启动使用当时 `getcwd()` 解析到的有效目录。插件不会自动切到 LSP 根目录，也不会在已有 CLI 中注入 `cd`。

## 常见问题

- **shell 中能运行，插件里找不到 CLI**：用 `:echo exepath('codex')`、`:echo $PATH` 或 `:Agent health` 检查 Neovim 的环境。让 GUI/编辑器继承正确 PATH，或配置可执行文件绝对路径；依赖 alias/函数时使用你自己维护的 wrapper。
- **Alt-a 不起作用**：检查终端是否发送 Alt/Meta。可先使用 `:Agent` 或普通模式下的 `<leader>aa`。插件不会修改终端、tmux 或操作系统快捷键。
- **切换主题后 CLI 内部颜色未更新**：外层高亮会跟随 ColorScheme，但应用的固定 RGB 与启动时缓存不由窗口高亮控制。完成工作后正常退出，再显式 resume；不会自动中断任务。
- **换目录后仍在旧项目**：这是已有进程的启动目录，可用 `:Agent status` 查看。需要新目录时显式停止并启动新会话。
- **另一个 Neovim 也开了一个会话**：单会话范围是每个 Neovim 进程，不是整台电脑。
- **中文输入法、复制粘贴或重绘差异**：这些仍受 Neovim 内嵌终端、外层终端、平台和 CLI 版本共同影响，不能保证与直接在 tmux 中运行完全一致。

## 卸载与反馈

先用 `:Agent stop` 停止任务，然后删除插件声明。插件不写 shell 配置、不安装 CLI、不保存认证文件，也不维护自己的跨进程聊天历史；原 CLI 的历史由它自己管理。

反馈请附操作系统、Neovim 和 CLI 版本、窗口布局、复现步骤和必要的健康检查信息。不要提交认证文件或密钥。代码使用 [MIT](LICENSE)。
