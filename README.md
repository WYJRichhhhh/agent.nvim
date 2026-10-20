# agent.nvim

A persistent, single-session terminal for **Claude Code, Codex and other interactive CLIs inside Neovim**. Open, focus, hide and return to the same running process without losing your unfinished input.

[中文说明](README.zh-CN.md) · [Report an issue](https://github.com/WYJRichhhhh/agent.nvim/issues)

**Experimental.** This plugin was extracted from a personal Neovim configuration. It is independent of that configuration, tmux, Ghostty, zsh and any theme plugin. The actual AI features remain in your chosen CLI.

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

Requirements: **Neovim 0.11+**, and at least one CLI executable visible in **Neovim's PATH**. The terminal host is Lua; optional Codex/Claude review adds a Node.js 22+ helper. Python 3 is needed only for development tests.

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

## Codex live changes (opt in)

Keep Codex's native TUI while viewing its edits in Neovim. Requires **Node.js 22+**, macOS/Linux, and a Codex CLI with `--remote`, App Server and capability-token support; validated with **Codex 0.163.0 on macOS**. Windows can use terminal-only mode. No npm packages, SDK, API keys or extra login are required. Claude has its own opt-in Hook adapter below; custom backends stay terminal-only.

```lua
opts = {
    codex = { enabled = true },
    window = { layout = "right", width = 0.42 },
    review = { follow = true },
    terminal = { hide_key = "<M-a>" },
}
```

Add any of these mappings to the lazy.nvim `keys` table (Normal mode; inside the TUI press **Ctrl-\, Ctrl-n** first):

```lua
{ "<leader>ar", "<cmd>Agent changes<cr>", desc = "Agent changed files" },
{ "<leader>ad", "<cmd>Agent diff<cr>", desc = "Agent turn diff" },
{ "<leader>ag", "<cmd>Agent gitdiff<cr>", desc = "Review a Git worktree" },
{ "<leader>aD", "<cmd>Agent filediff<cr>", desc = "Agent selected file diff" },
{ "<leader>af", "<cmd>Agent follow<cr>", desc = "Toggle following Agent edits" },
{ "<leader>ae", "<cmd>Agent code<cr>", desc = "Focus changed source file" },
{ "<leader>ah", "<cmd>Agent turns<cr>", desc = "Agent turn history" },
{ "<leader>an", "<cmd>Agent next<cr>", desc = "Next changed hunk" },
{ "<leader>ap", "<cmd>Agent prev<cr>", desc = "Previous changed hunk" },
```

- On a successful file change, the original editor window opens/reloads the unmodified file, highlights additions with `DiffAdd`, and displays deleted text as `DiffDelete` virtual lines. A batch opens only its last target; all changed files remain in the list. The TUI keeps keyboard focus. A right split lets you see both; a float can cover the editor.
- Switching to code or hiding the Agent keeps following enabled but holds your file, cursor and scroll position while you read. Changes continue to accumulate; returning to the Agent catches up to the latest edit. Starting to edit **pauses following**; returning does not override editing or an explicit pause. `:Agent follow` toggles it; `:Agent pause` explicitly pauses. Unsaved buffers are never replaced or reloaded. Save them and use `:Agent follow` to resume.
- `:Agent changes` lists successful edits across the retained turns in the current session. Select a file to inspect it. `:Agent code` focuses the selected/latest source file; `:Agent next` / `prev` navigate its hunks.
- `:Agent diff` opens the turn's aggregate unified diff; `:Agent filediff` shows the selected file's patch. Diff buffers are read-only, with red/green backgrounds. `q` returns to the previous buffer; `gf` opens the source file under the diff cursor. Neither closes the CLI.
- `:Agent turns` selects an earlier turn from this running plugin session (up to 20 by default). Historical/deleted entries open their patch, not old line highlights on today's source. This is **turn history**, not Git commit history or a persistent chat database.

### What gets tracked

`Agent changes` lists unique files across the retained turns of the current Agent session (latest 20 turns by default). If Telescope is installed, it provides fuzzy search and a diff preview; otherwise it uses `vim.ui.select`. Set `review.picker = "ui_select"` to opt out. Selecting a current-turn file opens the source with the same red/green marks as following and pauses automatic jumping; historical/deleted files open a read-only patch. Canceling the picker keeps following unchanged. `Agent turns` still scopes its list to the selected turn.

The plugin consumes official App Server `fileChange` items and `turn/diff/updated` notifications. Proposed/failed/rejected edits do not enter the successful-files list. The diff baseline comes from Codex's recorded edits for that turn, not Git HEAD, so pre-existing working-tree changes are not automatically included. In Git projects, `review.git_fallback = true` also compares local snapshots after tool completions and at turn end, catching shell/Ruby/Python/formatter writes without native file-change events. Entries reconstructed this way are marked `[Git]`. Snapshots preserve pre-turn dirty/untracked contents; clean tracked files use a frozen commit baseline without copying every file, so unrelated pre-existing changes are excluded; newly created worktrees use committed contents as their initial baseline. This cannot prove which process wrote a file: concurrent saved edits may also appear. Git-ignored, binary, oversized or snapshot-budget-excluded files are not covered; check `git diff` before committing. Very large patches above `review.max_diff_bytes` are skipped with a notice. Files outside the initial directory are omitted unless they belong to registered worktrees of the same Git project (`review.worktrees = true`). Arbitrary external/symlink targets remain excluded.

Protocol references: [Codex App Server](https://learn.chatgpt.com/docs/app-server) and [CLI commands](https://learn.chatgpt.com/docs/developer-commands?surface=cli).

### tmux zoom, scrolling and inspecting an existing worktree

Floating windows and right/bottom splits adapt to terminal/tmux zoom changes after layout settles. Fractional sizes follow the new editor dimensions; fixed cell sizes stay fixed where space allows. The existing PTY is resized without restarting the CLI, moving focus or clearing unfinished input.

By default `terminal.capture_mouse = true` temporarily enables Neovim mouse capture **only while the Agent buffer is focused**, so tmux forwards the wheel instead of entering copy-mode. Leaving/hiding/stopping restores the previous `mouse` value; explicit user changes are preserved. Set it to `false` to opt out. If tmux is already in copy-mode, leave that mode first. Native TUI scrolling remains owned by the CLI. For Neovim's retained terminal output, use **Ctrl-\, Ctrl-n**, then **Ctrl-b / Ctrl-f**; `i` returns to CLI input.

Use `:Agent gitdiff` to choose a registered worktree and inspect its current tracked-file diff against HEAD, including modifications made before this plugin session. This explicitly includes pre-existing/staged changes and omits untracked files; it is workspace review, not attribution to this Agent. It can inspect already completed tasks. `gf` opens the file under the diff cursor. Unlike `changes`, it does not require a captured file-change event.

Git fallback snapshots are bounded by `review.max_snapshot_bytes` (32 MiB total) and `review.max_diff_bytes` (2 MiB per text file/patch). Snapshots are local; patch generation uses private temporary files that are removed after diffing. Scans are serialized and coalesced rather than run on every keystroke. Turn-local automatic review starts with future tasks; it does not reconstruct an unknown pre-turn baseline for old tasks. Disable `review.git_fallback` or `review.worktrees` independently if desired.

### Ownership and lifecycle

```text
agent.nvim → Node helper → private, token-protected local Codex App Server
                │                         ├── native TUI (input + approvals)
                └── observer connection ───┘
                          ↓
                changed files / source highlights / diff
```

The helper uses built-in Node modules only. Each session gets a dedicated loopback endpoint and random capability token; the token travels over private process pipes/environment and is not written into config/history by the plugin. This token is local transport authentication, not an OpenAI API key. App Server uses your normal Codex environment, settings and login. The observer never starts turns or answers approvals. It ignores title-generation and child-agent threads, and retries subscription while a new TUI thread has not yet been persisted. Latest-turn file items are fetched after subscribing to recover edits missed during startup; older servers without pagination still provide live events.

Hide/show retains the TUI, helper and server. Stop, backend replacement, terminal-buffer deletion, native TUI exit or Neovim exit shuts down the owned helper/server. A bridge failure stops that CLI session and reports the error instead of silently launching a second CLI. Existing review data stays inspectable after native CLI exit until the session is discarded. Restore with the normal CLI resume flow; old-turn history is not reconstructed in full.

Keep `backends.codex.command[1]` as a Codex executable (or a wrapper that forwards `app-server` arguments). The server is launched as `{ executable, "app-server", ... }`; extra TUI command arguments are not copied into the server invocation. Put shared configuration in normal Codex configuration/environment. Shell argv wrappers such as `{ "zsh", "-ic", "codex" }` are for terminal-only mode. Update/restart explicitly to change settings; no task is restarted for colors or review toggles.

Set `codex.enabled = false` to return to the original direct terminal mode. `:Agent health` checks Node/CLI availability; `:Agent status` includes bridge connection and review/follow state. This integration is experimental; Linux is intended but not yet validated with a real CLI, and CLI protocol changes may need adapter updates.

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

## Claude Code live changes (opt in)

Claude uses its **native interactive CLI plus session-scoped command Hooks**, not the Codex App Server protocol. Enable it independently:

```lua
opts = {
    claude = { enabled = true },
    codex = { enabled = true }, -- optional; each backend has its own adapter
    window = { layout = "right", width = 0.42 },
    review = { follow = true, picker = "auto" },
}
```

Requirements: **macOS/Linux, Node.js 22+, Git**, and a Claude Code CLI supporting `--settings` and the lifecycle/tool Hooks. Git is required even outside repositories to generate text patches with `git diff --no-index`. A real tool edit, hook roundtrip, Neovim red/green marks and natural CLI exit were validated on **macOS with Claude Code 2.1.210**. Linux is intended but has not been tested with a real Claude session; Windows currently supports terminal-only mode.

The adapter uses `SessionStart`, `UserPromptSubmit`, `PreToolUse`, `PostToolUse`, `PostToolUseFailure`, `Stop` and `SessionEnd`. `UserPromptSubmit` starts a review turn. Before `Edit`, `Write`, `MultiEdit` or `NotebookEdit`, the adapter records the bounded file contents; afterward it compares the actual disk contents against the first captured version in that turn. In Git projects, the existing task baseline comparison also detects shell/script and registered-worktree writes when `review.git_fallback=true`. This feeds the **same** `changes`, `diff`, `filediff`, `follow`, `code`, `turns`, `next`, `prev` and `gitdiff` interfaces as Codex, including optional Telescope search/patch preview and reading without losing follow state. `:Agent resume claude` opens Claude's native history selector after the CLI has exited.

The plugin appends an inline `--settings` object only to its own CLI launch. It preserves ordinary user/project settings; if `backends.claude.command` already supplies one JSON/file `--settings`, its options and Hooks are merged in memory. That supplied file is read at launch, so later changes to it require restarting the session. User settings and project files are never rewritten by the adapter. `command[1]` must be the CLI or a wrapper that forwards the added arguments; shell wrappers that discard appended arguments are unsupported in tracking mode. The command Hook runs the configured Node executable using POSIX shell quoting, independently of interactive zsh/fish startup files.

Hooks send a minimal event to a random authenticated loopback HTTP endpoint owned by this Neovim session. They do not send prompt text, tool response text, file content or credentials over this channel; the local adapter reads allowed files itself to compute patches. Transport tokens stay in process pipes/environment, not in command-line settings or saved config. The adapter does not use an Anthropic SDK/API, change models, answer approvals or replace CLI login. Hook clients print nothing and return success even if tracking is unavailable; observation errors cannot veto a Claude tool action. Snapshot work briefly delays the corresponding Hook. `claude.hook_timeout` bounds the Hook client wait (default 10 seconds); timeouts can miss a baseline or update and are reported when detectable. Hiding retains the helper; stopping, switching, wiping the terminal or leaving Neovim terminates it. Received changes remain inspectable after a natural CLI exit until explicit stop/restart.

### Claude limitations and troubleshooting

- **Hooks must be allowed.** Workspace trust, `disableAllHooks`, managed policy restrictions, `--bare` or `--safe-mode` can prevent observation. Explicit incompatible launch settings produce an error; global/policy restrictions may instead leave `:Agent status` at `bridge.state="waiting"`. A delayed warning suggests checking Claude's `/hooks`. The plugin does not override policy or force Hooks on. Set `claude.enabled=false` for the original terminal-only behavior.
- **No retroactive attachment.** Tracking only covers this plugin-launched CLI and future captured edits. Starting/resuming Claude does not reconstruct old conversation patches or attach to an unrelated terminal session. Use `:Agent gitdiff` for the current tracked-file diff against HEAD, which also includes pre-existing changes.
- **Non-Git coverage is limited to supported file tools.** Shell, custom/MCP tools, arbitrary background processes, file moves/deletions without a supported file tool, and writes without a usable pre-edit Hook require Git fallback or remain unobserved. The adapter does not currently consume Claude-specific `bashEditDiff`, filesystem `FileChanged`, or transcript logs. Notebook edits show the notebook JSON patch, not a cell-aware notebook view.
- **Observed disk changes are not proof of authorship.** Concurrent editor/agent writes and partial writes from failed tools may appear. Subagent tool events with the parent session ID contribute to the parent turn; separate session IDs are ignored. There are no separate subagent review panes. Background writes crossing turn boundaries can be attributed to the later scan.
- **Bounds remain in force.** Binary, oversized, out-of-scope or symlink-target files are skipped. Git fallback omits ignored files; supported direct file-tool Hooks can still capture an ignored text file within scope. Native before-images and Git snapshots are bounded separately by `review.max_snapshot_bytes`; single files/patches use `review.max_diff_bytes`. Normal history retention (20 turns by default) and historical/deleted-file read-only patches apply to Claude too.
- Real-model validation covers a file-tool edit on macOS. Local automated fixtures additionally cover cumulative edits/reverts, failed tools, settings merging, hook authentication, session isolation, Git script/worktree changes, hide/show and cleanup. CLI versions, organizational policies and other platforms may differ; report the Claude version and `:Agent status` without credentials.

Reference: [Claude Code Hooks](https://code.claude.com/docs/en/hooks) and [CLI settings](https://code.claude.com/docs/en/cli-reference).

## Ask the Agent to show and explain code

With either `codex.enabled=true` or `claude.enabled=true`, `code.enabled=true` (default) registers a **session-only stdio MCP server** named `agent_nvim_editor`. It exposes `show_code` and `clear_code` to the native CLI. No global MCP files, SDKs, credentials, models or approval policies are changed. Custom/direct-terminal backends do not receive these tools.

Try asking the Agent:

> Find the core implementation of order validation. Use show_code to open it in the left Neovim editor and highlight the key lines with short explanations. Do not modify files.

The Agent reads/searches normally, then calls `show_code` with locations, 1-based inclusive ranges, and optional labels. The first file opens in the original source window, with `AgentCodeHighlight` (linked to `Visual`) and line-end labels; edit diffs keep their separate red/green styling. Default focus stays in the terminal and preserves terminal input mode. Only the first file loads; the other locations are available in a list. A tool can explicitly request `focus=true`. Example arguments:

```json
{
  "title": "Order validation",
  "locations": [
    {
      "file": "src/orders.py",
      "ranges": [
        { "start": 42, "end": 58, "label": "Validate before dispatch" }
      ]
    }
  ],
  "focus": false
}
```

| Command / suggested key | Action |
| --- | --- |
| `:Agent locations` / `<leader>al` | Pick an explanation file/location |
| `:Agent code` / `<leader>ae` | Focus the active explanation; otherwise the selected/latest edited file |
| `:Agent next` / `prev` / `<leader>an` / `ap` | Navigate explanation ranges/files while an explanation is active; otherwise navigate edit hunks |
| `:Agent clear` / `<leader>ac` | Clear explanation marks and its location list |
| `:Agent follow` / `<leader>af` | Clear the explanation and toggle edit following |

Suggested mappings (the plugin creates no global mappings):

```lua
{ "<leader>al", "<cmd>Agent locations<cr>", desc = "Agent code locations" },
{ "<leader>ac", "<cmd>Agent clear<cr>", desc = "Clear Agent explanation" },
```

Showing code pauses edit following so later edits cannot immediately replace the explanation. Explicitly opening an edit diff or changed source replaces the explanation. Clearing marks does not silently resume following. Editing/reloading a marked buffer invalidates its marks; selecting an old location validates it again. Hide/show preserves the explanation; stop/switch clears it. CLI natural exit leaves the explanation available until explicit stop/restart.

Files must exist within the configured review scope (launch directory and discovered registered worktrees by default). All requested file/range metadata is validated before presentation. Unsaved source-window or target buffers are refused; the user keeps their contents. Missing/binary/oversized files, invalid line numbers, unavailable source windows and stale code return tool errors. An optional `expected_text` on each range must exactly match that range (newlines normalized); it helps detect code that changed since the Agent read it. Later navigation uses captured text checks too. A local authenticated loopback relay waits for Neovim's actual response before reporting success; stopped/expired/unresponsive sessions return errors. No shell execution or file-write operation is exposed by these tools.

Configuration:

```lua
code = {
    enabled = true, -- requires an enabled Codex/Claude adapter; false disables MCP injection
    max_locations = 20,
    max_ranges = 50, -- per location
    max_highlight_lines = 1000, -- per location
    max_file_bytes = 2 * 1024 * 1024,
}
```

Limitations: the Agent chooses whether to call a tool; ask explicitly for `show_code` when needed. Existing running CLI sessions need a normal stop/restart to discover the tools. Native CLI MCP permissions/organization policies still apply; approve through the CLI when prompted. Claude's launch-time `--mcp-config` JSON/files are merged in memory without changing them; the name `agent_nvim_editor` is reserved. Codex receives temporary App Server config overrides and forwards only the relay environment variables to its stdio server. This is editor presentation, not semantic proof that the chosen code implements the behavior. Ordinary UTF-8 text and 1-based line ranges are supported; no AST-aware range tracking or persistent code tours. Locations can become stale while the Agent/user edits. No automatic transfer of an unsaved buffer or visual selection is implemented.

Validation: real Claude discovery and model-triggered display/highlights passed on macOS; real Codex App Server discovered both MCP tools without inference. Local end-to-end fixtures exercise both backends, the stdio/relay/UI acknowledgement, focus, toggle, clear, invalid ranges, stale text, unsaved buffers and cleanup. A real attached Neovim UI test also verified terminal input mode is retained. These are distinct from validating every CLI/platform/policy combination.

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
        show_hint = true,
        capture_mouse = true,
    },
    codex = { enabled = false, node = "node", startup_timeout = 15000 },
    claude = { enabled = false, node = "node", startup_timeout = 15000, hook_timeout = 10000 },
    review = { follow = true, history_limit = 20, max_diff_bytes = 2 * 1024 * 1024, restrict_to_cwd = true,
        git_fallback = true, worktrees = true, max_snapshot_bytes = 32 * 1024 * 1024 },
    backends = {
        claude = { label = "Claude Code", command = { "claude" }, resume_command = { "claude", "--resume" }, env = {} },
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

Lua API: `setup`, `register_backend`, `open`, `hide`, `toggle`, `focus`, `start`, `resume`, `stop`, `select`, `status`, `help`, `changes`, `diff`, `filediff`, `follow`, `pause`, `code`, `turns`, `next`, `prev`, `gitdiff`, `locations`, `clear`.

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
nvim --headless -u NONE -l tests/review.lua
nvim --headless -u NONE -l tests/explain.lua
nvim --headless -u NONE -l tests/editor-bridge.lua
nvim --headless -u NONE -l tests/bridge.lua
nvim --headless -u NONE -l tests/claude.lua
nvim --headless -u NONE -l tests/git-bridge.lua
nvim --headless -u NONE -l tests/mouse.lua
node --test tests/websocket.mjs tests/git-review.mjs tests/claude-review.mjs tests/claude-transport.mjs tests/editor.mjs
python3 tests/ui_resize.py # development-only Python msgpack dependency
```

Tests use a real PTY and a local Python fixture. They do not call a model or read authentication files. Bridge/transport tests open only temporary loopback listeners. They exercise singleton reuse, hidden interaction, unfinished input, directories, environment overrides, exits, explicit resume, window layouts and asynchronous selection. They also check that an invalid shell setting does not prevent direct executable launch and that window colors refresh without changing the process.

This release is intentionally small. Please report your OS, Neovim/CLI versions, layout, relevant health output and reproduction steps. Do not upload credentials or unrelated private configuration.

To uninstall, stop the Agent and remove the plugin spec. There are no plugin-owned login files, shell config edits or chat databases to delete; native CLI history remains managed by the CLI.

## License

[MIT](LICENSE).

Use `:Agent editor` to return focus to the existing code window without hiding the Agent or changing the code view. Map it in both normal and terminal mode, for example `{ "<M-e>", "<cmd>Agent editor<CR>", mode = { "n", "t" }, desc = "Focus editor" }`.

Code explanations use a proactive MCP instruction: for repository-specific implementation, location, and behavior questions (including follow-ups), the agent is asked to read source, call `show_code`, then explain it, without requiring the user to name the tool. This is model guidance, not an enforced hook: the model may still skip the call or require permission under its normal MCP policy. Existing sessions need to restart to receive the updated tool instructions.

For Codex, agent.nvim additionally appends the presentation workflow to `developer_instructions` on its private App Server, where native TUI sessions are created. Codex resolves the existing instructions through `config/read` (including explicit `-c` config overrides), then the plugin preserves that text and appends its own rules for this session. No global or project instruction files are modified. Restart Neovim and start a new Agent session after updating; an already running process does not receive new launch rules. Project tours such as “帮我来了解 manor-server的项目代码 从入口开始” are explicitly covered. Claude currently receives the MCP tool/server guidance, without this Codex-specific session override.

Codex App Server does not accept the CLI `--profile` flag; this instruction merge preserves the configuration resolved by App Server and forwarded `-c` overrides, not a separate TUI-only profile.
