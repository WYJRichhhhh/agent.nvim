# agent.nvim

A persistent, single-session terminal for **Claude Code, Codex and other interactive CLIs inside Neovim**. Open, focus, hide and return to the same running process without losing your unfinished input.

[中文说明](README.zh-CN.md) · [Report an issue](https://github.com/WYJRichhhhh/agent.nvim/issues)

**Experimental first release.** This plugin was extracted from a personal Neovim configuration. It is independent of that configuration, tmux, Ghostty, zsh and any theme plugin. The actual AI features remain in your chosen CLI.

## What problem does it solve?

Repeatedly opening terminal windows can scatter CLI sessions or accidentally terminate a conversation. agent.nvim keeps one CLI process and terminal buffer per Neovim instance, provides a predictable show/hide/focus workflow, and makes starting or stopping a session explicit.

It is a terminal host, not an AI API client. It does not choose models, implement agent tools, install CLIs or create another authentication system.

### In-terminal help and closing

Run `:Agent help` (or `:help agent.nvim`) for the operation guide. While typing into the CLI, press **Ctrl-\ then Ctrl-n** first to enter terminal Normal mode: `q` hides the window, `?` opens help, and `i` returns to CLI input. Close the help window with `:q` and use `:Agent open` to return. These local `q` / `?` mappings do not intercept CLI input.

**Hide** with `Alt-a` (when configured), `q`, or `:Agent hide` to keep the task and unfinished input. **Stop** with `:Agent stop` to terminate the process. To switch, use `:Agent select`; in terminal Normal mode the example `<leader>as` mapping also works. Choosing another backend requires confirmation and ends the old process. The first successful launch shows a brief hint once per Neovim; set `terminal.show_hint = false` to disable it.

## Who can use it?

- Neovim users who already have a working `claude`, `codex` or another interactive CLI.
- Users of bash, fish, zsh or other shells: **the default launcher does not invoke a shell**.
- Users of other Neovim configurations and plugin managers. There are no mandatory plugin dependencies.

Requirements: **Neovim 0.11+**, and at least one CLI executable visible in **Neovim's PATH**. Runtime code is pure Lua. Python 3 is needed only to run the development tests.

Locally tested on macOS with Neovim 0.12. Linux, Windows, different terminal emulators and CLI versions have not all been validated end to end; executable discovery and TUI rendering may differ. Please report problems rather than assuming identical terminal behavior everywhere.

## Install with lazy.nvim

```lua
{
    "WYJRichhhhh/agent.nvim",
    main = "agent",
    cmd = { "Agent" },
    keys = {
        {
            "<leader>aa",
            function() require("agent").focus() end,
            desc = "Open or focus AI Agent",
        },
        {
            "<M-a>",
            function() require("agent").focus() end,
            mode = { "n", "t" },
            desc = "Toggle AI Agent focus",
        },
        { "<leader>as", "<cmd>Agent select<cr>", desc = "Choose AI Agent backend" },
    },
    opts = {
        backend = "auto",
        terminal = { hide_key = "<M-a>" },
    },
}
```

The mappings above are examples, not plugin defaults. `<leader>` is whatever your config defines. `terminal.hide_key` is a buffer-local mapping inside Agent terminals; the global mapping and local hide key should normally agree.

For another plugin manager, add this repository to runtimepath and call `require("agent").setup(opts)`. `plugin/agent.lua` registers the `:Agent` command. Loading/setup does not launch a CLI or make network requests.

## Use

| Command | Behavior |
| --- | --- |
| `:Agent` / `:Agent focus` | Start if absent; otherwise focus; hide if already focused |
| `:Agent start codex` | Explicitly start Codex; refuse to replace a running process |
| `:Agent start claude` | Explicitly start Claude Code |
| `:Agent open` | Show an existing session; start only if none exists |
| `:Agent hide` | Hide all views of this session, keeping the process alive |
| `:Agent toggle` | Hide if visible, otherwise show |
| `:Agent select` | Open the backend menu; confirm before stopping a running session to switch |
| `:Agent resume codex` | Launch `codex resume` after the old CLI has exited |
| `:Agent stop` | Stop the process and discard its terminal buffer |
| `:Agent status` | Show backend, bound directory, job, exit state and visibility |
| `:Agent health` | Load the plugin, then run `:checkhealth agent` |

**Switching backends:** use `<leader>as` from the example mapping or `:Agent select`. The menu marks the current backend. Choosing it focuses the existing session. Choosing another backend asks for confirmation before stopping the old CLI; cancel keeps the process and unfinished input. Confirmed switches create one replacement process, not one retained process per backend. Native history remains managed by each CLI; switching does not automatically resume an old conversation.

`Alt-a` / `<leader>aa` are show/focus/hide controls, not backend selectors.

Auto discovery checks only whether each backend's `command[1]` is executable. If several are available, choose one; it is remembered in this Neovim process. Discovery does not inspect login state or run the CLI.

Inside the terminal, CLI keys such as Esc and Ctrl-C keep their native meanings. Enter terminal-normal mode with **Ctrl-\ then Ctrl-n**, then `q` hides the Agent or `i` returns to input. Alt/Meta mappings depend on your terminal forwarding those keys; `:Agent` remains available if they are intercepted.

## Session and directory lifecycle

There is **one session per Neovim process**, not one global session per computer.

- Hide/show/focus reuse the same process and buffer, including unfinished input. Hidden tasks keep running.
- Closing the Agent window normally does not stop the process; reopening reuses it.
- An exited CLI keeps its output. `open` shows that output; `start` explicitly launches another process.
- Deleting the terminal buffer or calling `stop` ends the process.
- **Quitting Neovim ends the CLI.** This is not a detached tmux server and does not keep jobs alive after editor exit.

The default directory is `vim.fn.getcwd()` **when the process starts**. This is the effective current Neovim directory, including applicable local-directory scope. It is not automatically the LSP/project root.

Later `:cd`, `:lcd`, `:tcd` or file navigation does not change a running CLI's directory. The plugin does not inject `cd` into its input or silently restart it. To start in another project:

```vim
:Agent stop
:cd ~/projects/my-app
:Agent start codex
```

Resuming a stopped/exited session of the same backend prefers its original start directory. `:Agent resume codex` opens the CLI's own history picker; select the conversation you want. It refuses to replace a running CLI. For another backend, configure `resume_command` explicitly rather than expecting guessed arguments.

## Shell, environment and authentication

Default commands are argv arrays, for example `{ "codex" }`. Neovim launches the executable directly with a PTY. **No system shell is selected or started**, so there is no zsh requirement and no shell startup file is sourced by the plugin.

Environment precedence is:

```text
Neovim's inherited environment → global env overrides → backend env overrides
```

Your CLI resolves its usual login, keys and local settings from that environment and its own files. The plugin does not read authentication files, store API keys or implement a separate login. Overriding variables such as HOME or CODEX_HOME can naturally change what the CLI itself loads.

Shell aliases/functions are not executables. Environment variables set only in an interactive shell may not exist in Neovim, especially when the editor was launched from a GUI. An installed CLI script can also require a runtime such as Node.js to be present on PATH.

If a command works in your shell but not in the plugin, inspect `:echo exepath('codex')`, `:echo $PATH` and `:Agent health`. Fix the environment that launches Neovim, configure an absolute executable path, or provide your own executable wrapper. You can explicitly configure a shell argv if you need one, but its arguments and startup behavior are your choice; the plugin does not guess a portable login-shell invocation or concatenate user input into shell commands.

## Configuration

```lua
require("agent").setup({
    backend = "auto", -- auto, claude, codex, or a registered name
    cwd = function() return vim.fn.getcwd() end,
    env = {},
    window = {
        layout = "float", -- float, right, bottom
        width = 0.85,     -- <=1: fraction; >1: columns
        height = 0.85,    -- <=1: fraction; >1: rows
        border = "rounded",
        winhighlight = "Normal:AgentNormal,NormalNC:AgentNormal,NormalFloat:AgentNormal,FloatBorder:AgentBorder,FloatTitle:AgentTitle",
    },
    terminal = {
        start_insert = true,
        hide_key = false, -- no buffer-local toggle key by default
    },
    backends = {
        claude = { label = "Claude Code", command = { "claude" }, env = {} },
        codex = {
            label = "Codex",
            command = { "codex" },
            resume_command = { "codex", "resume" },
            env = {},
        },
    },
})
```

`cwd` can also be a fixed path. Configuration changes affect future launches; they do not restart or reconfigure an existing process.

## Register a backend

```lua
require("agent").register_backend("local_agent", {
    label = "My local Agent",
    command = { "my-agent", "--interactive" },
    -- resume_command = { "my-agent", "its-documented-resume-argument" },
    env = {},
})
```

Then run `:Agent start local_agent`. Commands and resume commands must be nonempty argv lists. A backend may be another interactive executable; its TUI compatibility should be checked in your environment.

Lua API: `setup`, `register_backend`, `open`, `hide`, `toggle`, `focus`, `start`, `resume`, `stop`, `select`, `status`.

User events: `AgentStart` and `AgentExit`, with backend, directory, buffer and exit-code information in event data. Editor lifecycle is managed independently of the CLI's conversation history.

## Colors and terminal behavior

The host window follows Neovim's `NormalFloat`/`Normal` colors via `AgentNormal`, `AgentBorder` and `AgentTitle`. Colors refresh after `ColorScheme` without restarting the process. A transparent theme without a concrete background falls back to an explicit light/dark terminal background for readability; `window.winhighlight` is configurable.

This does not override RGB colors painted by the CLI. Neovim terminal ANSI palettes are initialized when the terminal is created, and CLIs can cache startup colors. A running CLI may therefore need a normal exit and explicit resume after a light/dark theme change. The plugin never restarts a task merely to refresh colors.

Actual Chinese input, clipboard handling, redraw behavior and keyboard forwarding depend on Neovim's terminal, the outer terminal, platform and CLI version. This is the same CLI executable and inherited user environment, but it is not a promise of pixel-for-pixel or lifecycle equivalence with tmux.

[dev-theme.nvim](https://github.com/WYJRichhhhh/dev-theme.nvim) can synchronize editor/terminal palettes separately; it is optional, not a dependency.

## Development and feedback

From the repository root, run:

```sh
nvim --headless -u NONE -l tests/run.lua
```

Tests use a real PTY and a local Python fixture. They do not call a model, use the network or read authentication files. They exercise singleton reuse, hidden interaction, unfinished input, directories, environment overrides, exits, explicit resume, window layouts and asynchronous selection. They also check that an invalid shell setting does not prevent direct executable launch and that window colors refresh without changing the process.

This release is intentionally small. Please report your OS, Neovim/CLI versions, layout, relevant health output and reproduction steps. Do not upload credentials or unrelated private configuration.

To uninstall, stop the Agent and remove the plugin spec. There are no plugin-owned login files, shell config edits or chat databases to delete; native CLI history remains managed by the CLI.

## License

[MIT](LICENSE).
