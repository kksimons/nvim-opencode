#!/bin/bash

# Installation script for nvim-opencode plugin

set -e

PLUGIN_NAME="nvim-opencode"
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
PLUGIN_DIR="$NVIM_CONFIG_DIR/lua/plugins"

echo "🚀 Installing $PLUGIN_NAME..."

# Check if Neovim is installed
if ! command -v nvim &>/dev/null; then
  echo "❌ Neovim is not installed. Please install Neovim first."
  exit 1
fi

# Check if opencode is installed
if ! command -v opencode &>/dev/null; then
  echo "⚠️  Warning: opencode is not found in PATH. Please install opencode first."
  echo "   Visit https://opencode.ai for installation instructions."
fi

# Create plugins directory if it doesn't exist
mkdir -p "$PLUGIN_DIR"

# Create the plugin configuration file
cat >"$PLUGIN_DIR/opencode.lua" <<'EOF'
-- nvim-opencode plugin configuration
return {
  {
    dir = vim.fn.stdpath("config") .. "/nvim-opencode",
    name = "nvim-opencode",
    event = "VeryLazy",
    config = function()
      require("opencode").setup({
        auto_start = true,                          -- Auto-start terminal on plugin load
        terminal_cmd = nil,                         -- Custom opencode command (nil = auto-detect)
        terminal = {
          split_side = "right",                     -- "left" or "right"
          split_width_percentage = 0.30,            -- 30% of screen width
        },
      })
    end,
  },
}
EOF

# Copy plugin files to Neovim config directory
cp -r . "$NVIM_CONFIG_DIR/$PLUGIN_NAME"

echo "✅ Plugin installed successfully!"
echo ""
echo "📝 Configuration:"
echo "   - Plugin files: $NVIM_CONFIG_DIR/$PLUGIN_NAME"
echo "   - Config file: $PLUGIN_DIR/opencode.lua"
echo ""
echo "🎯 Key Mappings:"
echo "   - <leader>A: Toggle OpenCode terminal"
echo "   - a (visual mode): Send selected text to OpenCode"
echo "   - a (normal mode): Send clipboard to OpenCode"
echo "   - <leader>+: Add current file to OpenCode context"
echo "   - <leader>-: Remove current file from OpenCode context"
echo "   - <leader>=: Toggle current file context"
echo "   - Double ESC: Clear OpenCode input line"
echo "   - Ctrl + U: Clear OpenCode input"
echo "   - 1/9 (in terminal): Switch focus between editor/chat"
echo ""
echo "🔄 Next steps:"
echo "   1. Restart Neovim"
echo "   2. The plugin will be automatically loaded"
echo "   3. Press <leader>A to start using OpenCode!"
echo "   4. See README.md for detailed usage instructions"
