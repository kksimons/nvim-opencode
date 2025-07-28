-- Example LazyVim configuration for nvim-opencode
-- Add this to your ~/.config/nvim/lua/plugins/opencode.lua

return {
  {
    "your-username/nvim-opencode",
    event = "VeryLazy", -- Load when needed
    config = function()
      require("opencode").setup({
        keybind = "<leader>a",  -- Use <leader>a to toggle opencode
        terminal_size = 0.8,    -- 80% of screen size for float, 40% for splits
        position = "float",     -- Options: "float", "bottom", "right"
      })
    end,
    keys = {
      { "<leader>a", function() require("opencode").toggle() end, desc = "Toggle opencode" },
    },
  },
}

-- Alternative configurations:

-- For horizontal split at bottom (like Ctrl+/ terminal):
-- position = "bottom",
-- terminal_size = 0.4,  -- 40% of screen height

-- For vertical split on right (like file explorer):
-- position = "right", 
-- terminal_size = 0.4,  -- 40% of screen width