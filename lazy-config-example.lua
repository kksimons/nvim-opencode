-- Example LazyVim configuration for nvim-opencode
-- Add this to your ~/.config/nvim/lua/plugins/opencode.lua

return {
	{
		"ksimons/nvim-opencode", -- Replace with your fork if needed
		event = "VeryLazy", -- Load when needed
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
	},
}

-- Key mappings are automatically configured:
-- <leader>A - Toggle OpenCode terminal
-- a (visual mode) - Send selected text to OpenCode
-- a (normal mode) - Send clipboard to OpenCode
-- <leader>+ - Add current file to OpenCode context
-- <leader>- - Remove current file from OpenCode context
-- <leader>= - Toggle current file context
-- Double ESC - Clear OpenCode input line
-- 1/9 (in terminal) - Switch focus between editor/chat

-- Alternative configurations:

-- For left side terminal:
-- split_side = "left",

-- For wider terminal:
-- split_width_percentage = 0.40,  -- 40% of screen width

-- Custom OpenCode command:
-- terminal_cmd = "/path/to/your/opencode",

-- Disable auto-start:
-- auto_start = false,

