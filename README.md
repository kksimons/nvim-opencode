# nvim-opencode

A Neovim plugin that integrates [OpenCode](https://opencode.ai) directly into your editor.

## Features

- **Terminal Management**: Toggle OpenCode terminal with `\<leader\>A`
- **Text Sharing**: Send selections and clipboard content with accurate line counting
- **File Context Management**: Add/remove entire files from OpenCode context
- **Session Persistence**: Maintains connection when window is closed/reopened

## Installation

### Prerequisites

- Neovim \>= 0.8
- [OpenCode](https://opencode.ai) installed and available in your PATH

### Using [lazy.nvim](https://github.com/folke/lazy.nvim) (recommended)

```lua
{
  "ksimons/nvim-opencode", -- or your fork
  config = function()
    require("opencode").setup({
      -- Default configuration (all optional)
      auto_start = true,                          -- Auto-start terminal on plugin load
      terminal_cmd = nil,                         -- Custom opencode command (nil = auto-detect)
      terminal = {
        split_side = "right",                     -- "left" or "right"
        split_width_percentage = 0.30,            -- 30% of screen width
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

## Key Mappings

### Terminal Management

- `\<leader\>A` - Toggle OpenCode terminal (show/hide while preserving session)

### Text Sharing

- `a` (visual mode) - Send selected text to OpenCode with accurate line counting
- `a` (normal mode) - Send clipboard/yank register content to OpenCode
- Double `ESC` - Clear current input line in OpenCode
- Ctrl+U - Clear entire input in OpenCode

### File Context Management

- `\<leader\>+` - Add current file to OpenCode context (prevents duplicates)
- `\<leader\>-` - Remove current file from OpenCode context
- `\<leader\>=` - Toggle current file context in OpenCode

### Focus Control (in OpenCode terminal)

- `1` - Focus on Neovim editor (skips file explorers, focuses main editing window)
- `9` - Focus on OpenCode terminal

## Basic Usage

1. Open a file in Neovim
2. Press `\<leader\>A` to open OpenCode terminal
3. Select some code in visual mode and press `a` to send it
4. See `[PASTED X lines]` feedback for accurate line count
5. Use `1` and `9` to switch focus between editor and chat

### File Context Management

1. Press `\<leader\>+` to add current file to chat context
2. OpenCode now knows about the entire file for better responses
3. Press `\<leader\>-` to remove file from context when done or /new for new session
4. Use `\<leader\>=` to quickly toggle file context on/off

## Configuration

### Default Configuration

```lua
require("opencode").setup({
  auto_start = true,                          -- Auto-start terminal on plugin load
  terminal_cmd = nil,                         -- Custom opencode command (nil = auto-detect)
  terminal = {
    split_side = "right",                     -- "left" or "right"
    split_width_percentage = 0.30,            -- 30% of screen width
  },
})
```

### Configuration Options

- **`auto_start`** (boolean, default: `true`) - Automatically start OpenCode terminal when plugin loads
- **`terminal_cmd`** (string, default: `nil`) - Custom OpenCode command. If `nil`, auto-detects from PATH or common install locations
- **`terminal.split_side`** (string, default: `"right"`) - Terminal position: `"left"` or `"right"`
- **`terminal.split_width_percentage`** (number, default: `0.30`) - Terminal width as percentage of screen width

### OpenCode Command Detection

The plugin automatically detects OpenCode installation in the following order:

1. `opencode` in PATH
2. `~/.local/bin/opencode`
3. `/usr/local/bin/opencode`
4. `/opt/homebrew/bin/opencode`

You can override this by setting `terminal_cmd` to a custom path.

## Notes

- Terminal session persists even when window is closed - you can reopen with `\<leader\>A` without losing your chat history
- The `1` key intelligently skips file explorers (NvimTree, neo-tree, oil) and focuses the main editing window
- All text sharing shows accurate line counts: `[PASTED 5 lines]` instead of generic "1+ lines"
