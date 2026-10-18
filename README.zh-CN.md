# agent.nvim

在 Neovim 中运行本机 Claude Code、Codex 或自定义交互式 CLI。插件管理终端窗口和单会话生命周期，CLI 自己负责登录、对话、工具调用和测试执行。

[English](README.md) · [反馈问题](https://github.com/WYJRichhhhh/agent.nvim/issues)

**实验性插件**。终端核心使用 Lua、无强制插件依赖，Codex 修改跟踪可选使用 Node.js helper，要求 Neovim 0.11+；当前在 macOS、Neovim 0.12 测试。Linux、Windows 和不同 CLI 版本的完整体验尚未逐一验证，欢迎反馈。插件独立安装，不要求作者的个人配置、tmux、Ghostty、主题插件或 zsh。

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
| `<leader>aD` | `:Agent filediff` | 最近选择文件的差异 |
| `<leader>af` | `:Agent follow` | 开启/暂停自动跟随 |
| `<leader>ae` | `:Agent code` | 聚焦最近选择/修改的源文件 |
| `<leader>ah` | `:Agent turns` | 选择当前插件会话内的历史轮次 |
| `<leader>an` / `<leader>ap` | `:Agent next` / `:Agent prev` | 在源文件中跳到下一处/上一处修改 |

成功修改文件后，原编辑窗口打开该文件：新增行使用 `DiffAdd` 绿色背景，删除内容以 `DiffDelete` 红色虚拟行显示，不写入源文件。焦点留在 Codex，方便继续输入。建议使用右侧分屏；浮窗可能遮住代码。

进入代码窗口、切换文件或开始编辑时会**自动暂停跟随**，避免抢走你的操作。`:Agent follow` 切换跟随状态；`:Agent pause` 明确暂停。任何未保存的 buffer 都不会被自动替换或重新加载；保存后再恢复跟随。未修改的已打开文件可以自动重新加载，保留原有 `autoread` 配置。

差异窗口是只读 unified diff，按 `q` 返回原 buffer，按 `gf` 打开最近选择的源文件；不会停止 CLI。历史轮次和已删除文件优先显示补丁，避免把旧行号标到当前版本上。历史默认保留最近 20 轮，范围是本次插件会话；**不等于 Git 提交历史，也不是跨进程的聊天记录库**。

### 数据来源与范围

直接消费官方 App Server 的 `fileChange` 和 `turn/diff/updated` 事件，不解析 TUI 文本。列表只记录成功的文件修改，尚未批准、失败和被拒绝的修改不会混入。对比基准由 Codex 该轮记录的修改决定，不直接对比 Git HEAD，因此不会自动把开始任务前已有的全部改动算进去。

通过 shell、格式化器或其他工具写入、但未产生文件修改事件的内容可能不在列表中；提交前仍应检查 `git diff`。超过 `review.max_diff_bytes` 的大补丁会跳过并提示。默认不打开启动目录之外的文件，符号链接的实际目标也会检查。

协议参考：[Codex App Server](https://learn.chatgpt.com/docs/app-server)、[CLI 命令](https://learn.chatgpt.com/docs/developer-commands?surface=cli)。

### 进程、登录与清理

插件启动一个本机会话专属的 App Server，原生 TUI 和观察连接共同连接它。Node helper 只使用标准库，无 npm 依赖。服务仅监听 loopback，并使用每次生成的随机 capability token；该 token 通过进程管道和环境传递，不由插件写入配置或历史。它只是本地传输鉴权，不是 OpenAI API Key。Codex 仍读取普通 shell 中那套用户配置、环境和登录；观察连接不发起任务、不回答审批。

会过滤 Codex 自动生成标题和子 Agent 的线程。新 TUI 会话尚未落盘时持续等待订阅；订阅成功后读取最近一轮文件条目，补回启动期间错过的修改。旧服务若不支持分页读取，仍可处理实时事件。

隐藏保留 TUI、helper 和服务；停止、确认切换后端、删除终端 buffer、退出原生 TUI 或退出 Neovim 时会清理它们。连接异常会停止当前 CLI 并报告，不会悄悄另开第二个会话。CLI 自然退出后仍可检查已收到的差异，直到显式停止/重启时清理；resume 沿用原生恢复流程，不会完整重建以前所有轮次。

`backends.codex.command[1]` 必须是 Codex 可执行文件，或能原样转发 `app-server` 参数的 wrapper。服务使用 `{ executable, "app-server", ... }` 启动，不会把额外 TUI 参数复制给服务；公共设置请放在普通 Codex 配置/环境中。`{ "zsh", "-ic", "codex" }` 这样的 shell 参数数组仅适用于关闭跟踪时的纯终端模式。

设置 `codex.enabled = false` 可退回原来的直接终端模式。`:Agent health` 检查依赖，`:Agent status` 查看连接、轮次和跟随状态。此集成仍属实验功能；Linux 尚未用真实 CLI 验证，后续 Codex 协议变化可能需要调整适配。

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
    },
    codex = { enabled = false, node = "node", startup_timeout = 15000 },
    review = { follow = true, history_limit = 20, max_diff_bytes = 2 * 1024 * 1024, restrict_to_cwd = true },
    backends = {
        claude = { label = "Claude Code", command = { "claude" }, env = {} },
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

Lua API 包括 `setup`、`register_backend`、`open`、`hide`、`toggle`、`focus`、`start`、`resume`、`stop`、`select`、`status`、`help`、`changes`、`diff`、`filediff`、`follow`、`pause`、`code`、`turns`、`next` 和 `prev`。`toggle()` 是按可见性切换；`focus()` 在其他代码窗口中优先聚焦 Agent，已经聚焦时才隐藏。

## 验证

在插件根目录执行，需要 Python 3 作为模拟交互进程：

```sh
nvim --headless -u NONE -l tests/run.lua
nvim --headless -u NONE -l tests/review.lua
nvim --headless -u NONE -l tests/bridge.lua
node --test tests/websocket.mjs
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
