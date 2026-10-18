# agent.nvim

在 Neovim 中运行本机 Claude Code、Codex 或自定义交互式 CLI。插件管理终端窗口和单会话生命周期，CLI 自己负责登录、对话、工具调用和测试执行。

[English](README.md) · [反馈问题](https://github.com/WYJRichhhhh/agent.nvim/issues)

**实验性的第一版**。纯 Lua、无强制插件依赖，要求 Neovim 0.11+；当前在 macOS、Neovim 0.12 测试。Linux、Windows 和不同 CLI 版本的完整体验尚未逐一验证，欢迎反馈。插件独立安装，不要求作者的个人配置、tmux、Ghostty、主题插件或 zsh。

## 解决什么问题，谁能用

将本机交互 CLI 放在 Neovim 的常驻终端中，通过快捷键显示、聚焦和隐藏。隐藏不会关闭进程、清空未提交输入或另开会话，实际 AI 能力由 CLI 自己实现。

任何已有可用 `codex`、`claude` 或其他交互 CLI 的 Neovim 用户都能使用。至少一个后端可执行文件必须存在于 **Neovim 的 PATH** 中。正常使用无需 Python；Python 3 只用于开发测试。

默认使用参数数组直接启动 CLI，**不启动系统 shell，也不依赖 zsh**。bash、fish 等用户无需更换 shell，但 shell alias、函数和未传入 Neovim 的环境设置不能自动继承。GUI 启动 Neovim 与登录 shell 的 PATH 也可能不同，详见后面的配置和排查说明。

插件没有第二套密钥、登录或模型设置；沿用 CLI 从继承环境和本机配置读取的设置。如果你覆盖 HOME、CODEX_HOME 等环境变量，CLI 自己的配置解析结果也会相应改变。

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
    },
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

Lua API 包括 `setup`、`register_backend`、`open`、`hide`、`toggle`、`focus`、`start`、`resume`、`stop`、`select` 和 `status`。`toggle()` 是按可见性切换；`focus()` 在其他代码窗口中优先聚焦 Agent，已经聚焦时才隐藏。

## 验证

在插件根目录执行，需要 Python 3 作为模拟交互进程：

```sh
nvim --headless -u NONE -l tests/run.lua
```

测试使用真实 PTY，但不调用模型或读取认证文件。覆盖单进程复用、隐藏时交互、未提交输入、工作目录、环境变量、退出处理、分屏、窗口手动关闭和异步后端选择。

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
