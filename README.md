# nvim-opencode

A Neovim plugin that integrates [opencode](https://opencode.ai) directly into your editor.

## Features

- Toggle opencode terminal with `<leader>A`
- Send visual selections to opencode with `a` in visual mode
- Send clipboard content to opencode with `a` in normal mode
- Clear opencode input with double `ESC` (works from anywhere)
- Quick focus switching with `0` (opencode) and `1` (editor)
- File change detection with automatic diff display
- Persistent session management (maintains connection when window is closed)
- Multiple window positions: floating, bottom split, right split
- Configurable terminal size and behavior
- Automatic cleanup when terminal exits
- LazyVim compatible

## Installation

### Prerequisites

- Neovim >= 0.8
- [opencode](https://opencode.ai) installed and available in your PATH

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "ksimons/nvim-opencode", -- or your fork
  config = function()
    require("opencode").setup({
      -- Default configuration (all optional)
      terminal = {
        split_side = "right",           -- "left", "right", "top", "bottom"
        split_width_percentage = 0.30,  -- 30% of screen width/height
        provider = "auto",              -- "auto", "native"
        auto_close = true,              -- Close terminal when opencode exits
      },
      file_watcher = {
        enabled = true,        -- Enable file change detection
        show_diffs = true,     -- Show diffs when files change
        auto_reload = false,   -- Auto-reload changed files
      },
    })
  end,
}
```

### Using [packer.nvim](https://github.com/wbthomason/packer.nvim)

```lua
use {
  "ksimons/nvim-opencode", -- or your fork
  config = function()
    require("opencode").setup()
  end
}
```

### Manual Installation

1. Clone this repository to your Neovim plugin directory:

   ```bash
   git clone https://github.com/ksimons/nvim-opencode.git ~/.config/nvim/pack/plugins/start/nvim-opencode
   ```

2. Add to your `init.lua`:

   ```lua
   require("opencode").setup()
   ```

## Usage

### Key Mappings

#### Focus Control

- `0` - Focus opencode terminal
- `1` - Focus Neovim editor (skips file explorers, focuses main editing window)

#### Sending Content to OpenCode

- `a` (visual mode) - Send selected text to opencode
- `a` (normal mode) - Send clipboard/yank register content to opencode
- `ESC ESC` (double ESC) - Clear opencode input box (works from anywhere)

#### Terminal Management

- `<leader>A` - Toggle opencode terminal
- `<C-w>a` - Toggle focus between nvim and opencode (legacy keybinding)

#### Diff Management

- `<leader>da` - Accept current diff hunk
- `<leader>dr` - Reject current diff hunk
- `<leader>dd` - Accept all diffs in current file
- `<leader>dR` - Reject all diffs in current file

### Commands

#### Core Commands

- `:OpenCode` - Toggle opencode terminal
- `:OpenCodeStart` - Start opencode integration
- `:OpenCodeStop` - Stop opencode integration
- `:OpenCodeStatus` - Show integration status

#### Content Sending

- `:OpenCodeSend` - Send current file/selection to opencode
- `:OpenCodeSendSelection` - Send visual selection to opencode

#### Focus Management

- `:OpenCodeFocus` - Focus opencode terminal
- `:OpenCodeToggleFocus` - Toggle focus between nvim and opencode

#### File Operations

- `:OpenCodeShowDiff` - Show inline diffs for current file
- `:OpenCodeAcceptDiff [hunk_number]` - Accept specific diff hunk (default: first)
- `:OpenCodeRejectDiff [hunk_number]` - Reject specific diff hunk (default: first)
- `:OpenCodeAcceptAllDiffs` - Accept all diffs in current file
- `:OpenCodeRejectAllDiffs` - Reject all diffs in current file

### Terminal Mode Keybindings

When inside the opencode terminal:

- `0` - Focus opencode terminal (stay in terminal)
- `1` - Switch focus back to nvim editor
- `ESC ESC` - Clear line in OpenCode input box only
- Terminal session persists even when window is closed

## Configuration

### Full Configuration Example

```lua
require("opencode").setup({
  -- Connection settings
  port_range = { min = 10000, max = 65535 },  -- Port range for opencode server
  auto_start = true,                          -- Auto-start integration on plugin load
  terminal_cmd = nil,                         -- Custom opencode command (nil = auto-detect)
  log_level = "info",                         -- "trace", "debug", "info", "warn", "error"
  track_selection = true,                     -- Send selection updates to opencode

  -- Terminal configuration
  terminal = {
    split_side = "right",                     -- "left", "right", "top", "bottom"
    split_width_percentage = 0.30,            -- 30% of screen width/height
    provider = "auto",                        -- "auto", "native"
    auto_close = true,                        -- Close terminal when opencode exits
  },

  -- File watching and diff integration
  file_watcher = {
    enabled = true,                           -- Enable file change detection
    show_diffs = true,                        -- Show diffs when files change
    auto_reload = false,                      -- Auto-reload changed files
  },

  -- Legacy keymap configuration (most keymaps are now hardcoded)
  keymaps = {
    send_selection = "a",                     -- Key to send selection in visual mode
    toggle_focus = "<C-w>a",                  -- Key to toggle focus
  },
})
```

### Terminal Position Options

- **`"right"`** - Vertical split on right side (default, like file explorer)
- **`"left"`** - Vertical split on left side
- **`"top"`** - Horizontal split at top
- **`"bottom"`** - Horizontal split at bottom (like integrated terminal)

### Size Recommendations

- **Vertical splits** (`"left"`, `"right"`): `0.30` (30% of screen width)
- **Horizontal splits** (`"top"`, `"bottom"`): `0.40` (40% of screen height)

## Workflow Examples

### Basic Usage

1. Open a file in Neovim
2. Press `<leader>a` to open opencode terminal
3. Select some code and press `a` to send it to opencode
4. Use `0` and `1` to quickly switch focus between opencode and editor

### Clipboard Integration

1. Yank some code with `y` (or copy from anywhere)
2. Press `a` in normal mode to paste it into opencode chat
3. Double-tap `ESC` to clear the opencode input if needed (line at a time just in case)

### File Explorer Integration

- The `1` key intelligently focuses the main editing window, skipping file explorers like NvimTree, neo-tree, oil, etc.
- This ensures you always land in the actual file content, not the tree view

### Diff Management Workflow

When OpenCode makes changes to your files, the plugin automatically detects them and shows inline diffs:

1. **Automatic Detection**: File changes are detected via git diff when files are modified
2. **Inline Display**:
   - Added lines are highlighted in green with `+` signs
   - Removed lines appear as virtual text above the changes in red
   - Each diff hunk shows instructions: `[Hunk 1] <leader>da: accept, <leader>dr: reject, <leader>dd: accept all`
3. **Accept/Reject**: Use the keybindings to selectively accept or reject changes
4. **Batch Operations**: Accept or reject all changes at once with `<leader>dd` or `<leader>dR`

**Example workflow:**

1. Ask OpenCode to refactor a function
2. OpenCode modifies the file
3. Plugin shows inline diffs with highlights and virtual text
4. Review changes and press `<leader>da` to accept good changes, `<leader>dr` to reject unwanted ones
5. Use `<leader>dd` to accept all remaining changes when satisfied
