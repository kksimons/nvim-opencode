#!/bin/bash

# Installation script for nvim-opencode plugin

set -e

PLUGIN_NAME="nvim-opencode"
NVIM_CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nvim"
PLUGIN_DIR="$NVIM_CONFIG_DIR/lua/plugins"

echo "🚀 Installing $PLUGIN_NAME..."

# Check if Neovim is installed
if ! command -v nvim &> /dev/null; then
    echo "❌ Neovim is not installed. Please install Neovim first."
    exit 1
fi

# Check if opencode is installed
if ! command -v opencode &> /dev/null; then
    echo "⚠️  Warning: opencode is not found in PATH. Please install opencode first."
    echo "   Visit https://opencode.ai for installation instructions."
fi

# Create plugins directory if it doesn't exist
mkdir -p "$PLUGIN_DIR"

# Create the plugin configuration file
cat > "$PLUGIN_DIR/opencode.lua" << 'EOF'
-- nvim-opencode plugin configuration
return {
  {
    dir = vim.fn.stdpath("config") .. "/nvim-opencode",
    name = "nvim-opencode",
    event = "VeryLazy",
    config = function()
      require("opencode").setup({
        keybind = "<leader>a",  -- Use <leader>a to toggle opencode
        terminal_size = 0.8,    -- 80% of screen size
        position = "float",     -- Floating window
      })
    end,
    keys = {
      { "<leader>a", function() require("opencode").toggle() end, desc = "Toggle opencode" },
    },
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
echo "🎯 Usage:"
echo "   - Press <leader>a to toggle opencode"
echo "   - Use :OpencodeToggle, :OpencodeOpen, :OpencodeClose commands"
echo ""
echo "🔄 Next steps:"
echo "   1. Restart Neovim"
echo "   2. The plugin will be automatically loaded by LazyVim"
echo "   3. Press <leader>a to start using opencode!"