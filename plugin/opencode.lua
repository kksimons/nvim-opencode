-- nvim-opencode plugin entry point
if vim.g.loaded_opencode then
	return
end
vim.g.loaded_opencode = 1

-- Set up the plugin with default configuration
require("opencode").setup()

-- Set up the default keybindings
vim.keymap.set("n", "<leader>A", function()
	require("opencode").toggle_terminal()
end, { desc = "Toggle OpenCode terminal" })

-- Focus switching with '0' and '1' keys
vim.keymap.set("n", "0", function()
	require("opencode").focus_opencode()
end, { desc = "Focus OpenCode terminal" })

vim.keymap.set("n", "1", function()
	require("opencode").focus_nvim()
end, { desc = "Focus Neovim editor" })

-- Also add terminal mode keymaps
vim.keymap.set("t", "0", function()
	require("opencode").focus_opencode()
end, { desc = "Focus OpenCode terminal" })

vim.keymap.set("t", "1", function()
	require("opencode").focus_nvim()
end, { desc = "Focus Neovim editor" })

-- Keep the original toggle focus for backwards compatibility
vim.keymap.set("n", "<C-w>a", function()
	require("opencode").toggle_focus()
end, { desc = "Toggle focus between Neovim and OpenCode" })

vim.keymap.set("t", "<C-w>a", function()
	require("opencode").focus_nvim()
end, { desc = "Focus Neovim from OpenCode terminal" })

-- Send selection in visual mode with 'a'
vim.keymap.set("v", "a", function()
	require("opencode").send_selection()
end, { desc = "Send visual selection to OpenCode" })

-- Send clipboard content in normal mode with 'a'
vim.keymap.set("n", "a", function()
	require("opencode").send_clipboard()
end, { desc = "Send clipboard content to OpenCode" })

-- Double ESC to clear OpenCode input box (works from anywhere)
vim.keymap.set("n", "<Esc>", function()
	local opencode = require("opencode")
	if not opencode.handle_esc() then
		-- If not consumed by double ESC, let ESC work normally
		return "<Esc>"
	end
end, { expr = true, desc = "Double ESC to clear OpenCode input" })

vim.keymap.set("t", "<Esc>", function()
	local opencode = require("opencode")
	if not opencode.handle_esc() then
		-- If not consumed by double ESC, let ESC work normally
		return "<Esc>"
	end
end, { expr = true, desc = "Double ESC to clear OpenCode input" })

-- Diff management keybindings
vim.keymap.set("n", "<leader>da", function()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path ~= "" then
		-- For now, accept the first hunk - could be enhanced to detect cursor position
		require("opencode").accept_diff_hunk(file_path, 1)
	end
end, { desc = "Accept current diff hunk" })

vim.keymap.set("n", "<leader>dr", function()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path ~= "" then
		-- For now, reject the first hunk - could be enhanced to detect cursor position
		require("opencode").reject_diff_hunk(file_path, 1)
	end
end, { desc = "Reject current diff hunk" })

vim.keymap.set("n", "<leader>dd", function()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path ~= "" then
		require("opencode").accept_all_diffs(file_path)
	end
end, { desc = "Accept all diffs in current file" })

vim.keymap.set("n", "<leader>dR", function()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path ~= "" then
		require("opencode").reject_all_diffs(file_path)
	end
end, { desc = "Reject all diffs in current file" })

