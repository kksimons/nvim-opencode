---@brief [[
--- OpenCode Neovim Integration
---@brief ]]

local M = {}

--- @class OpenCode.Config
--- @field port_range {min: integer, max: integer}
--- @field auto_start boolean
--- @field terminal_cmd string|nil
--- @field log_level "trace"|"debug"|"info"|"warn"|"error"
--- @field track_selection boolean Enable sending selection updates to OpenCode.
--- @field terminal { split_side: "left"|"right", split_width_percentage: number, provider: "auto"|"native", auto_close: boolean }
--- @field file_watcher { enabled: boolean, show_diffs: boolean, auto_reload: boolean }
--- @field keymaps { send_selection: string, toggle_focus: string }

--- @type OpenCode.Config
local default_config = {
	port_range = { min = 10000, max = 65535 },
	auto_start = true,
	terminal_cmd = nil,
	log_level = "info",
	track_selection = true,
	terminal = {
		split_side = "right",
		split_width_percentage = 0.30,
		provider = "auto",
		auto_close = true,
	},
	file_watcher = {
		enabled = true,
		show_diffs = true,
		auto_reload = false,
	},
	keymaps = {
		send_selection = "a",
		toggle_focus = "<C-w>a",
	},
}

--- @class OpenCode.State
--- @field config OpenCode.Config
--- @field server table|nil
--- @field port number|nil
--- @field auth_token string|nil
--- @field initialized boolean
--- @field terminal_buf number|nil
--- @field terminal_win number|nil
--- @field file_watchers table<string, number>
--- @field session_file string|nil
--- @field last_esc_time number|nil
--- @field pending_diffs table<string, table>
--- @field last_focus "nvim"|"opencode"

--- @type OpenCode.State
M.state = {
	config = vim.deepcopy(default_config),
	server = nil,
	port = nil,
	auth_token = nil,
	initialized = false,
	terminal_buf = nil,
	terminal_win = nil,
	file_watchers = {},
	session_file = nil,
	last_esc_time = nil,
	pending_diffs = {},
	last_focus = "nvim",
}

-- Simple logger
local logger = {
	info = function(context, msg)
		print("[OpenCode:" .. context .. "] " .. msg)
	end,
	warn = function(context, msg)
		print("[OpenCode:" .. context .. "] WARN: " .. msg)
	end,
	error = function(context, msg)
		print("[OpenCode:" .. context .. "] ERROR: " .. msg)
	end,
	debug = function(context, msg)
		if M.state.config.log_level == "debug" then
			print("[OpenCode:" .. context .. "] DEBUG: " .. msg)
		end
	end,
}

-- Get the opencode command
local function get_opencode_cmd()
	if M.state.config.terminal_cmd then
		return M.state.config.terminal_cmd
	end

	-- Try to find opencode in PATH first
	if vim.fn.executable("opencode") == 1 then
		return "opencode"
	end

	-- Try common installation paths
	local paths = {
		vim.fn.expand("~/.local/bin/opencode"),
		"/usr/local/bin/opencode",
		"/opt/homebrew/bin/opencode",
	}

	for _, path in ipairs(paths) do
		if vim.fn.executable(path) == 1 then
			return path
		end
	end

	return "opencode"
end

-- Simple WebSocket server implementation
local function create_websocket_server(port, auth_token)
	local server = {}
	local clients = {}

	-- Mock server for now - in a real implementation this would be a proper WebSocket server
	server.start = function()
		logger.debug("server", "Starting WebSocket server on port " .. port)
		return true
	end

	server.stop = function()
		logger.debug("server", "Stopping WebSocket server")
		clients = {}
		return true
	end

	server.broadcast = function(event, data)
		logger.debug("server", "Broadcasting event: " .. event)
		-- In a real implementation, this would send data to connected clients
		return true
	end

	server.get_client_count = function()
		return #clients
	end

	return server
end

-- Create lock file for opencode to discover
local function create_lock_file(port, auth_token)
	local opencode_dir = vim.fn.expand("~/.opencode")
	local ide_dir = opencode_dir .. "/ide"

	-- Create directories if they don't exist
	vim.fn.mkdir(ide_dir, "p")

	local lock_file = ide_dir .. "/" .. port .. ".lock"
	local lock_data = {
		port = port,
		auth_token = auth_token,
		pid = vim.fn.getpid(),
		editor = "neovim",
		version = "1.0.0",
	}

	local file = io.open(lock_file, "w")
	if not file then
		return false, "Failed to create lock file"
	end

	file:write(vim.json.encode(lock_data))
	file:close()

	logger.debug("lockfile", "Created lock file: " .. lock_file)
	return true, lock_file
end

-- Remove lock file
local function remove_lock_file(port)
	if not port then
		return true
	end

	local lock_file = vim.fn.expand("~/.opencode/ide/" .. port .. ".lock")
	if vim.fn.filereadable(lock_file) == 1 then
		vim.fn.delete(lock_file)
		logger.debug("lockfile", "Removed lock file: " .. lock_file)
	end
	return true
end

-- Generate auth token
local function generate_auth_token()
	local chars = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789"
	local token = ""
	for i = 1, 32 do
		local rand = math.random(1, #chars)
		token = token .. chars:sub(rand, rand)
	end
	return token
end

-- File watcher functionality
local function setup_file_watcher(file_path)
	if not M.state.config.file_watcher.enabled then
		return
	end

	local buf = vim.fn.bufnr(file_path)
	if buf == -1 then
		return
	end

	-- Remove existing watcher if any
	if M.state.file_watchers[file_path] then
		vim.api.nvim_del_autocmd(M.state.file_watchers[file_path])
	end

	-- Create new watcher
	local autocmd_id = vim.api.nvim_create_autocmd({ "BufWritePost" }, {
		buffer = buf,
		callback = function()
			if M.state.config.file_watcher.show_diffs then
				-- Use the new inline diff system
				M.show_inline_diffs(file_path)
			end
			-- Notify opencode of file change
			if M.state.server then
				M.state.server.broadcast("file_changed", {
					filePath = file_path,
					timestamp = os.time(),
				})
			end
		end,
		desc = "OpenCode file watcher for " .. file_path,
	})

	M.state.file_watchers[file_path] = autocmd_id
end

-- Show diff for a file
function show_file_diff(file_path)
	-- Get git diff for the file
	local diff_cmd = string.format("git diff HEAD -- %s", vim.fn.shellescape(file_path))
	local diff_output = vim.fn.system(diff_cmd)

	if vim.v.shell_error == 0 and diff_output ~= "" then
		-- Create a floating window to show the diff
		local buf = vim.api.nvim_create_buf(false, true)
		local lines = vim.split(diff_output, "\n")
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		vim.api.nvim_buf_set_option(buf, "filetype", "diff")
		vim.api.nvim_buf_set_option(buf, "modifiable", false)

		local width = math.floor(vim.o.columns * 0.8)
		local height = math.min(#lines + 2, math.floor(vim.o.lines * 0.6))
		local row = math.floor((vim.o.lines - height) / 2)
		local col = math.floor((vim.o.columns - width) / 2)

		local win = vim.api.nvim_open_win(buf, false, {
			relative = "editor",
			width = width,
			height = height,
			row = row,
			col = col,
			style = "minimal",
			border = "rounded",
			title = " Git Diff: " .. vim.fn.fnamemodify(file_path, ":t") .. " ",
			title_pos = "center",
		})

		-- Auto-close after 5 seconds or on any key press
		vim.defer_fn(function()
			if vim.api.nvim_win_is_valid(win) then
				vim.api.nvim_win_close(win, true)
			end
		end, 5000)

		-- Close on any key press
		vim.api.nvim_buf_set_keymap(buf, "n", "<Esc>", "<cmd>close<cr>", { noremap = true, silent = true })
		vim.api.nvim_buf_set_keymap(buf, "n", "q", "<cmd>close<cr>", { noremap = true, silent = true })
	end
end

-- Enhanced diff system with accept/reject functionality
local diff_namespace = vim.api.nvim_create_namespace("opencode_diffs")

-- Parse git diff output into structured format
local function parse_diff(diff_output)
	local hunks = {}
	local current_hunk = nil
	local lines = vim.split(diff_output, "\n")
	
	for _, line in ipairs(lines) do
		-- Match hunk header: @@ -old_start,old_count +new_start,new_count @@
		local old_start, old_count, new_start, new_count = line:match("^@@ %-(%d+),?(%d*) %+(%d+),?(%d*) @@")
		if old_start then
			if current_hunk then
				table.insert(hunks, current_hunk)
			end
			current_hunk = {
				old_start = tonumber(old_start),
				old_count = tonumber(old_count) or 1,
				new_start = tonumber(new_start),
				new_count = tonumber(new_count) or 1,
				lines = {}
			}
		elseif current_hunk then
			-- Parse diff lines
			local prefix = line:sub(1, 1)
			local content = line:sub(2)
			if prefix == "+" or prefix == "-" or prefix == " " then
				table.insert(current_hunk.lines, {
					type = prefix == "+" and "add" or (prefix == "-" and "remove" or "context"),
					content = content
				})
			end
		end
	end
	
	if current_hunk then
		table.insert(hunks, current_hunk)
	end
	
	return hunks
end

-- Show inline diffs with virtual text and signs
function M.show_inline_diffs(file_path)
	-- Get the buffer for this file
	local bufnr = nil
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_is_valid(buf) and vim.api.nvim_buf_get_name(buf) == file_path then
			bufnr = buf
			break
		end
	end
	
	if not bufnr then
		logger.warn("diff", "Buffer not found for file: " .. file_path)
		return
	end
	
	-- Get git diff
	local diff_cmd = string.format("git diff HEAD -- %s", vim.fn.shellescape(file_path))
	local diff_output = vim.fn.system(diff_cmd)
	
	if vim.v.shell_error ~= 0 or diff_output == "" then
		logger.debug("diff", "No diff found for file: " .. file_path)
		return
	end
	
	-- Parse the diff
	local hunks = parse_diff(diff_output)
	if #hunks == 0 then
		return
	end
	
	-- Store pending diffs for this file
	M.state.pending_diffs[file_path] = {
		bufnr = bufnr,
		hunks = hunks,
		original_content = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	}
	
	-- Clear existing diff highlights
	vim.api.nvim_buf_clear_namespace(bufnr, diff_namespace, 0, -1)
	
	-- Apply diff highlights and virtual text
	for hunk_idx, hunk in ipairs(hunks) do
		local line_num = hunk.new_start - 1 -- Convert to 0-based
		
		-- Add signs and highlights for changed lines
		for i, diff_line in ipairs(hunk.lines) do
			if diff_line.type == "add" then
				-- Highlight added lines
				vim.api.nvim_buf_add_highlight(bufnr, diff_namespace, "DiffAdd", line_num, 0, -1)
				-- Add sign
				vim.fn.sign_place(0, "opencode_diff", "OpenCodeDiffAdd", bufnr, {lnum = line_num + 1})
				line_num = line_num + 1
			elseif diff_line.type == "remove" then
				-- Show removed lines as virtual text
				vim.api.nvim_buf_set_extmark(bufnr, diff_namespace, line_num, 0, {
					virt_lines = {{{"- " .. diff_line.content, "DiffDelete"}}},
					virt_lines_above = true,
				})
			else -- context
				line_num = line_num + 1
			end
		end
		
		-- Add virtual text with accept/reject instructions
		vim.api.nvim_buf_set_extmark(bufnr, diff_namespace, hunk.new_start - 1, 0, {
			virt_text = {{string.format(" [Hunk %d] <leader>da: accept, <leader>dr: reject, <leader>dd: accept all", hunk_idx), "Comment"}},
			virt_text_pos = "eol",
		})
	end
	
	logger.info("diff", string.format("Showing %d diff hunks for %s", #hunks, vim.fn.fnamemodify(file_path, ":t")))
end

-- Accept a specific diff hunk
function M.accept_diff_hunk(file_path, hunk_idx)
	local pending = M.state.pending_diffs[file_path]
	if not pending or not pending.hunks[hunk_idx] then
		logger.error("diff", "No pending diff hunk found")
		return
	end
	
	-- Remove the hunk from pending diffs
	table.remove(pending.hunks, hunk_idx)
	
	-- If no more hunks, clear all diff highlights
	if #pending.hunks == 0 then
		M.clear_diff_highlights(file_path)
		M.state.pending_diffs[file_path] = nil
	else
		-- Refresh the diff display
		M.show_inline_diffs(file_path)
	end
	
	logger.info("diff", "Accepted diff hunk " .. hunk_idx)
end

-- Reject a specific diff hunk
function M.reject_diff_hunk(file_path, hunk_idx)
	local pending = M.state.pending_diffs[file_path]
	if not pending or not pending.hunks[hunk_idx] then
		logger.error("diff", "No pending diff hunk found")
		return
	end
	
	local hunk = pending.hunks[hunk_idx]
	local bufnr = pending.bufnr
	
	-- Revert the changes for this hunk
	-- This is a simplified approach - in practice, you'd want more sophisticated merging
	local start_line = hunk.new_start - 1
	local end_line = start_line + hunk.new_count
	
	-- Get the original lines for this hunk
	local original_lines = {}
	for i = hunk.old_start, hunk.old_start + hunk.old_count - 1 do
		if pending.original_content[i] then
			table.insert(original_lines, pending.original_content[i])
		end
	end
	
	-- Replace the lines in the buffer
	vim.api.nvim_buf_set_lines(bufnr, start_line, end_line, false, original_lines)
	
	-- Remove the hunk from pending diffs
	table.remove(pending.hunks, hunk_idx)
	
	-- If no more hunks, clear all diff highlights
	if #pending.hunks == 0 then
		M.clear_diff_highlights(file_path)
		M.state.pending_diffs[file_path] = nil
	else
		-- Refresh the diff display
		M.show_inline_diffs(file_path)
	end
	
	logger.info("diff", "Rejected diff hunk " .. hunk_idx)
end

-- Accept all diff hunks for a file
function M.accept_all_diffs(file_path)
	local pending = M.state.pending_diffs[file_path]
	if not pending then
		logger.error("diff", "No pending diffs found")
		return
	end
	
	M.clear_diff_highlights(file_path)
	M.state.pending_diffs[file_path] = nil
	
	logger.info("diff", "Accepted all diffs for " .. vim.fn.fnamemodify(file_path, ":t"))
end

-- Reject all diff hunks for a file
function M.reject_all_diffs(file_path)
	local pending = M.state.pending_diffs[file_path]
	if not pending then
		logger.error("diff", "No pending diffs found")
		return
	end
	
	local bufnr = pending.bufnr
	
	-- Revert entire file to original content
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, pending.original_content)
	
	M.clear_diff_highlights(file_path)
	M.state.pending_diffs[file_path] = nil
	
	logger.info("diff", "Rejected all diffs for " .. vim.fn.fnamemodify(file_path, ":t"))
end

-- Clear diff highlights for a file
function M.clear_diff_highlights(file_path)
	local pending = M.state.pending_diffs[file_path]
	if not pending then
		return
	end
	
	local bufnr = pending.bufnr
	vim.api.nvim_buf_clear_namespace(bufnr, diff_namespace, 0, -1)
	vim.fn.sign_unplace("opencode_diff", {buffer = bufnr})
end

-- Session management
local function get_session_file()
	local cwd = vim.fn.getcwd()
	local session_dir = vim.fn.expand("~/.opencode/sessions")
	vim.fn.mkdir(session_dir, "p")
	local session_name = string.gsub(cwd, "/", "_")
	return session_dir .. "/" .. session_name .. ".json"
end

local function save_session()
	if not M.state.port or not M.state.auth_token then
		return
	end

	local session_data = {
		port = M.state.port,
		auth_token = M.state.auth_token,
		cwd = vim.fn.getcwd(),
		timestamp = os.time(),
	}

	local session_file = get_session_file()
	local file = io.open(session_file, "w")
	if file then
		file:write(vim.json.encode(session_data))
		file:close()
		M.state.session_file = session_file
		logger.debug("session", "Session saved to " .. session_file)
	end
end

local function load_session()
	local session_file = get_session_file()
	local file = io.open(session_file, "r")
	if not file then
		return nil
	end

	local content = file:read("*all")
	file:close()

	local ok, session_data = pcall(vim.json.decode, content)
	if not ok or not session_data then
		return nil
	end

	-- Check if session is recent (within 24 hours)
	if os.time() - session_data.timestamp > 86400 then
		return nil
	end

	return session_data
end

-- Find available port
local function find_available_port()
	for port = M.state.config.port_range.min, M.state.config.port_range.max do
		-- Simple check - in a real implementation you'd actually test the port
		return port
	end
	return nil
end

-- Terminal management
local function create_terminal()
	local opencode_cmd = get_opencode_cmd()
	local cwd = vim.fn.getcwd()

	-- Save current window
	local current_win = vim.api.nvim_get_current_win()

	-- Create terminal split on the right
	if M.state.config.terminal.split_side == "right" then
		vim.cmd("botright vsplit")
	else
		vim.cmd("topleft vsplit")
	end

	-- Get the new window and set width
	local term_win = vim.api.nvim_get_current_win()
	local width = math.floor(vim.o.columns * M.state.config.terminal.split_width_percentage)
	vim.api.nvim_win_set_width(term_win, width)

	-- Create terminal buffer
	local term_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(term_win, term_buf)

	-- Get terminal dimensions for proper sizing
	local term_height = vim.api.nvim_win_get_height(term_win)
	local term_width = vim.api.nvim_win_get_width(term_win)

	-- Set environment variables for opencode to find our server AND proper terminal sizing
	local env = vim.tbl_extend("force", vim.fn.environ(), {
		OPENCODE_IDE_PORT = tostring(M.state.port),
		OPENCODE_IDE_AUTH = M.state.auth_token,
		COLUMNS = tostring(term_width),
		LINES = tostring(term_height),
		TERM = "xterm-256color",
		FORCE_COLOR = "1",
		COLORTERM = "truecolor",
		-- Force system theme for embedded terminals (fixes layout issues)
		OPENCODE_THEME = "system",
		-- Mark as embedded terminal for potential future detection
		OPENCODE_EMBEDDED = "1",
		OPENCODE_CALLER = "nvim",
	})

	-- Create simple terminal initialization script with proper environment
	local init_script = string.format(
		[[
    # Set up terminal environment for opencode
    export TERM=xterm-256color
    export COLUMNS=%d
    export LINES=%d
    export FORCE_COLOR=1
    export COLORTERM=truecolor
    
    # Force system theme for embedded terminals (fixes layout issues)
    export OPENCODE_THEME=system
    export OPENCODE_EMBEDDED=1
    export OPENCODE_CALLER=nvim
    
    # Disable any terminal detection that might interfere
    unset TERM_PROGRAM
    unset VSCODE_INJECTION
    unset NVIM
    unset NVIM_LISTEN_ADDRESS
    
    # Set proper terminal size
    stty rows %d cols %d 2>/dev/null || true
    
    # Force terminal to be in a clean state
    printf '\033c'  # Reset terminal
    printf '\033[?1049h'  # Enable alternate screen
    printf '\033[2J\033[H'  # Clear screen and home cursor
    
    # Start opencode with proper size from the beginning
    exec %s %s
  ]],
		term_width,
		term_height,
		term_height,
		term_width,
		opencode_cmd,
		cwd
	)

	-- Start opencode with proper terminal initialization
	local job_id = vim.fn.termopen({ "bash", "-c", init_script }, {
		cwd = cwd,
		env = env,
		on_exit = function()
			M.close_terminal()
		end,
	})

	if job_id <= 0 then
		logger.error("terminal", "Failed to start opencode terminal")
		return false
	end

	M.state.terminal_buf = term_buf
	M.state.terminal_win = term_win

	-- Set terminal window options
	vim.wo[term_win].number = false
	vim.wo[term_win].relativenumber = false
	vim.wo[term_win].signcolumn = "no"
	vim.wo[term_win].wrap = false
	vim.wo[term_win].cursorline = false
	vim.wo[term_win].cursorcolumn = false
	vim.wo[term_win].colorcolumn = ""
	vim.wo[term_win].foldcolumn = "0"

	-- Set buffer options
	vim.bo[term_buf].bufhidden = "hide"
	vim.bo[term_buf].swapfile = false

	-- Set up terminal-specific keymaps
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"<leader>a",
		'<C-\\><C-n>:lua require("opencode").toggle_terminal()<CR>',
		{ noremap = true, silent = true, desc = "Toggle OpenCode terminal" }
	)
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"<C-w>a",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim from OpenCode terminal" }
	)
	-- Add '0' and '1' keymaps for focus switching
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"0",
		'<C-\\><C-n>:lua require("opencode").focus_opencode()<CR>',
		{ noremap = true, silent = true, desc = "Focus OpenCode terminal" }
	)
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"1",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim from OpenCode terminal" }
	)

	-- Set up autocmd to handle window resizing
	vim.api.nvim_create_autocmd("VimResized", {
		callback = function()
			if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) and M.state.terminal_buf then
				local new_width = vim.api.nvim_win_get_width(M.state.terminal_win)
				local new_height = vim.api.nvim_win_get_height(M.state.terminal_win)
				local job_id = vim.b[M.state.terminal_buf].terminal_job_id
				if job_id then
					-- Send SIGWINCH to notify opencode of size change
					vim.fn.jobsend(job_id, "") -- This triggers a SIGWINCH
				end
			end
		end,
	})

	-- Focus the terminal and enter insert mode
	vim.api.nvim_set_current_win(term_win)
	vim.cmd("startinsert")

	logger.info("terminal", "OpenCode terminal started")
	return true
end

-- Close terminal
function M.close_terminal()
	if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) then
		vim.api.nvim_win_close(M.state.terminal_win, true)
	end

	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		vim.api.nvim_buf_delete(M.state.terminal_buf, { force = true })
	end

	M.state.terminal_buf = nil
	M.state.terminal_win = nil

	logger.debug("terminal", "Terminal closed")
end

-- Toggle terminal
function M.toggle_terminal()
	if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) then
		-- Don't close terminal, just hide the window but keep the session
		vim.api.nvim_win_hide(M.state.terminal_win)
		M.state.terminal_win = nil
		M.focus_nvim()
	else
		if not M.state.server then
			-- Try to start with existing session
			local started = M.start()
			if not started then
				logger.error("terminal", "Failed to start OpenCode integration")
				return
			end
		end

		if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
			-- Reopen existing terminal buffer
			reopen_terminal()
		else
			-- Create new terminal
			create_terminal()
		end
	end
end

-- Reopen existing terminal buffer
function reopen_terminal()
	-- Save current window
	local current_win = vim.api.nvim_get_current_win()

	-- Create terminal split on the right
	if M.state.config.terminal.split_side == "right" then
		vim.cmd("botright vsplit")
	else
		vim.cmd("topleft vsplit")
	end

	-- Get the new window and set width
	local term_win = vim.api.nvim_get_current_win()
	local width = math.floor(vim.o.columns * M.state.config.terminal.split_width_percentage)
	vim.api.nvim_win_set_width(term_win, width)

	-- Set the existing terminal buffer
	vim.api.nvim_win_set_buf(term_win, M.state.terminal_buf)
	M.state.terminal_win = term_win

	-- Set terminal window options
	vim.wo[term_win].number = false
	vim.wo[term_win].relativenumber = false
	vim.wo[term_win].signcolumn = "no"
	vim.wo[term_win].wrap = false
	vim.wo[term_win].cursorline = false
	vim.wo[term_win].cursorcolumn = false
	vim.wo[term_win].colorcolumn = ""
	vim.wo[term_win].foldcolumn = "0"

	-- Set up terminal-specific keymaps for reopened terminal
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"<leader>a",
		'<C-\\><C-n>:lua require("opencode").toggle_terminal()<CR>',
		{ noremap = true, silent = true, desc = "Toggle OpenCode terminal" }
	)
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"<C-w>a",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim from OpenCode terminal" }
	)
	-- Add '0' and '1' keymaps for focus switching
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"0",
		'<C-\\><C-n>:lua require("opencode").focus_opencode()<CR>',
		{ noremap = true, silent = true, desc = "Focus OpenCode terminal" }
	)
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"1",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim from OpenCode terminal" }
	)

	-- Focus the terminal and enter insert mode
	vim.api.nvim_set_current_win(term_win)
	vim.cmd("startinsert")

	logger.info("terminal", "OpenCode terminal reopened")
end

-- Start the OpenCode integration
function M.start()
	if M.state.server then
		logger.warn("init", "OpenCode integration is already running on port " .. tostring(M.state.port))
		return false, "Already running"
	end

	-- Try to load existing session first
	local session_data = load_session()
	local auth_token, port

	if session_data then
		auth_token = session_data.auth_token
		port = session_data.port
		logger.info("init", "Restored session on port " .. tostring(port))
	else
		-- Generate new auth token
		auth_token = generate_auth_token()
		if not auth_token then
			logger.error("init", "Failed to generate authentication token")
			return false, "Failed to generate auth token"
		end

		-- Find available port
		port = find_available_port()
		if not port then
			logger.error("init", "No available ports in range")
			return false, "No available ports"
		end
	end

	-- Create WebSocket server
	local server = create_websocket_server(port, auth_token)
	local success = server.start()

	if not success then
		logger.error("init", "Failed to start WebSocket server")
		return false, "Failed to start server"
	end

	-- Create lock file
	local lock_success, lock_result = create_lock_file(port, auth_token)
	if not lock_success then
		server.stop()
		logger.error("init", "Failed to create lock file: " .. lock_result)
		return false, lock_result
	end

	M.state.server = server
	M.state.port = port
	M.state.auth_token = auth_token

	-- Save session
	save_session()

	logger.info("init", "OpenCode integration started on port " .. tostring(port))
	return true, port
end

-- Stop the OpenCode integration
function M.stop(preserve_session)
	if not M.state.server then
		logger.warn("init", "OpenCode integration is not running")
		return false, "Not running"
	end

	-- Close terminal if open
	M.close_terminal()

	-- Clear file watchers
	for file_path, autocmd_id in pairs(M.state.file_watchers) do
		vim.api.nvim_del_autocmd(autocmd_id)
	end
	M.state.file_watchers = {}

	-- Remove lock file
	remove_lock_file(M.state.port)

	-- Stop server
	local success = M.state.server.stop()
	if not success then
		logger.error("init", "Failed to stop server")
		return false, "Failed to stop server"
	end

	-- Clean up session if not preserving
	if not preserve_session and M.state.session_file then
		vim.fn.delete(M.state.session_file)
		M.state.session_file = nil
	end

	M.state.server = nil
	M.state.port = nil
	M.state.auth_token = nil

	logger.info("init", "OpenCode integration stopped")
	return true
end

-- Send file to opencode
function M.send_file(file_path, start_line, end_line)
	if not M.state.server then
		logger.error("command", "OpenCode integration is not running")
		return false, "Integration not running"
	end

	-- Format file path
	local formatted_path = file_path
	local cwd = vim.fn.getcwd()
	if string.find(file_path, cwd, 1, true) == 1 then
		formatted_path = string.sub(file_path, #cwd + 2)
	end

	-- Send to opencode
	local params = {
		filePath = formatted_path,
		lineStart = start_line,
		lineEnd = end_line,
	}

	local success = M.state.server.broadcast("file_mentioned", params)
	if success then
		logger.debug("command", "Sent file to OpenCode: " .. formatted_path)
		-- Set up file watcher for this file
		setup_file_watcher(file_path)
		return true
	else
		logger.error("command", "Failed to send file to OpenCode: " .. formatted_path)
		return false, "Failed to send file"
	end
end

-- Send selected text to opencode
function M.send_selection()
	if not M.state.server then
		logger.error("command", "OpenCode integration is not running")
		return false, "Integration not running"
	end

	-- Get visual selection using a simpler, more reliable method
	-- Use the yank register approach which always works
	local selected_lines
	
	-- Save current register content
	local save_reg = vim.fn.getreg('"')
	local save_regtype = vim.fn.getregtype('"')
	
	-- Yank the visual selection to get the text
	vim.cmd('normal! gv"zy')
	local selected_text = vim.fn.getreg('z')
	
	-- Restore the register
	vim.fn.setreg('"', save_reg, save_regtype)
	
	if selected_text == "" then
		logger.error("command", "No text selected")
		return false, "No selection"
	end
	
	-- Split into lines for consistency with other methods
	selected_lines = vim.split(selected_text, '\n', {plain = true})

	if #selected_lines == 0 or (selected_lines[1] == "" and #selected_lines == 1) then
		logger.error("command", "No text selected")
		return false, "No selection"
	end

	local text_content = table.concat(selected_lines, "\n")
	local file_path = vim.api.nvim_buf_get_name(0)

	-- Debug logging
	logger.debug("command", "Selected text: " .. text_content)
	logger.debug("command", "Selection length: " .. string.len(text_content) .. " characters")

	-- Send to opencode terminal directly by typing the text
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			-- Send the selected text to the terminal
			vim.fn.jobsend(job_id, text_content)
			logger.info("command", "Sent selection to OpenCode terminal: " .. string.len(text_content) .. " characters")

			-- Focus the opencode terminal
			M.focus_opencode()
			return true
		end
	end

	-- Fallback: broadcast to server
	-- Get line numbers for the server params
	local start_pos = vim.fn.getpos("'<")
	local end_pos = vim.fn.getpos("'>")
	local params = {
		text = text_content,
		filePath = file_path,
		lineStart = start_pos[2] - 1, -- Convert to 0-based
		lineEnd = end_pos[2] - 1,
		context = "selection",
	}

	local success = M.state.server.broadcast("text_selected", params)
	if success then
		logger.debug("command", "Sent selection to OpenCode via server")
		M.focus_opencode()
		return true
	else
		logger.error("command", "Failed to send selection to OpenCode")
		return false, "Failed to send selection"
	end
end

-- Focus management
function M.focus_opencode()
	if M.state.terminal_win and vim.api.nvim_win_is_valid(M.state.terminal_win) then
		vim.api.nvim_set_current_win(M.state.terminal_win)
		vim.cmd("startinsert")
		M.state.last_focus = "opencode"
		logger.debug("focus", "Focused OpenCode terminal")
	else
		logger.warn("focus", "OpenCode terminal not available")
	end
end

-- Send clipboard content to opencode
function M.send_clipboard()
	if not M.state.server then
		logger.error("command", "OpenCode integration is not running")
		return false, "Integration not running"
	end

	-- Get clipboard content (yank register)
	local clipboard_text = vim.fn.getreg('"')
	
	if clipboard_text == "" then
		logger.error("command", "No text in clipboard")
		return false, "No clipboard content"
	end

	-- Send to opencode terminal directly by typing the text
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			-- Send the clipboard text to the terminal
			vim.fn.jobsend(job_id, clipboard_text)
			logger.info("command", "Sent clipboard to OpenCode terminal: " .. string.len(clipboard_text) .. " characters")

			-- Focus the opencode terminal
			M.focus_opencode()
			return true
		end
	end

	logger.error("command", "Failed to send clipboard content")
	return false, "Failed to send"
end

-- Clear the OpenCode input box
function M.clear_input()
	if not M.state.server then
		logger.error("command", "OpenCode integration is not running")
		return false, "Integration not running"
	end

	-- Send command to clear the input box in opencode terminal
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			-- Send Ctrl+U to clear the current input line
			vim.fn.jobsend(job_id, "\x15")
			logger.info("command", "Cleared OpenCode input box")
			return true
		end
	end

	logger.error("command", "Failed to clear input")
	return false, "Failed to clear"
end

-- Handle ESC key press for double ESC detection
function M.handle_esc()
	local current_time = vim.loop.hrtime() / 1000000 -- Convert to milliseconds
	
	if M.state.last_esc_time and (current_time - M.state.last_esc_time) < 500 then
		-- Double ESC detected within 500ms
		M.state.last_esc_time = nil
		M.clear_input()
		return true -- Consume the ESC
	else
		-- First ESC or too much time passed
		M.state.last_esc_time = current_time
		return false -- Let ESC work normally
	end
end

function M.focus_nvim()
	-- Find the main editing window (skip terminal, explorer, and other special buffers)
	local windows = vim.api.nvim_list_wins()
	local main_win = nil
	
	for _, win in ipairs(windows) do
		if win ~= M.state.terminal_win and vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			local buf_type = vim.api.nvim_buf_get_option(buf, "buftype")
			local buf_name = vim.api.nvim_buf_get_name(buf)
			local filetype = vim.api.nvim_buf_get_option(buf, "filetype")
			
			-- Skip terminal, explorer, and other special buffers
			if buf_type == "" and filetype ~= "NvimTree" and filetype ~= "neo-tree" and 
			   filetype ~= "oil" and filetype ~= "dirvish" and filetype ~= "netrw" and
			   not buf_name:match("NvimTree") and not buf_name:match("neo%-tree") then
				main_win = win
				break
			end
		end
	end
	
	if main_win then
		vim.api.nvim_set_current_win(main_win)
		M.state.last_focus = "nvim"
		logger.debug("focus", "Focused main editing window")
	else
		logger.warn("focus", "No suitable main editing window found")
	end
end

function M.toggle_focus()
	if M.state.last_focus == "nvim" then
		M.focus_opencode()
	else
		M.focus_nvim()
	end
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Merge config
	M.state.config = vim.tbl_deep_extend("force", default_config, opts)

	-- Create commands
	vim.api.nvim_create_user_command("OpenCodeStart", function()
		M.start()
	end, { desc = "Start OpenCode integration" })

	vim.api.nvim_create_user_command("OpenCodeStop", function()
		M.stop()
	end, { desc = "Stop OpenCode integration" })

	vim.api.nvim_create_user_command("OpenCodeStatus", function()
		if M.state.server and M.state.port then
			logger.info("command", "OpenCode integration is running on port " .. tostring(M.state.port))
		else
			logger.info("command", "OpenCode integration is not running")
		end
	end, { desc = "Show OpenCode integration status" })

	vim.api.nvim_create_user_command("OpenCode", function()
		M.toggle_terminal()
	end, { desc = "Toggle OpenCode terminal" })

	vim.api.nvim_create_user_command("OpenCodeSend", function(cmd_opts)
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end

		local start_line, end_line = nil, nil
		if cmd_opts.range > 0 then
			start_line = cmd_opts.line1 - 1 -- Convert to 0-based
			end_line = cmd_opts.line2 - 1
		end

		M.send_file(file_path, start_line, end_line)
	end, { range = true, desc = "Send current file/selection to OpenCode" })

	vim.api.nvim_create_user_command("OpenCodeSendSelection", function()
		M.send_selection()
	end, { desc = "Send visual selection to OpenCode" })

	vim.api.nvim_create_user_command("OpenCodeFocus", function()
		M.focus_opencode()
	end, { desc = "Focus OpenCode terminal" })

	vim.api.nvim_create_user_command("OpenCodeToggleFocus", function()
		M.toggle_focus()
	end, { desc = "Toggle focus between Neovim and OpenCode" })

	vim.api.nvim_create_user_command("OpenCodeShowDiff", function()
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end
		M.show_inline_diffs(file_path)
	end, { desc = "Show inline diffs for current file" })

	vim.api.nvim_create_user_command("OpenCodeAcceptDiff", function(opts)
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end
		local hunk_idx = tonumber(opts.args) or 1
		M.accept_diff_hunk(file_path, hunk_idx)
	end, { nargs = "?", desc = "Accept diff hunk (default: first hunk)" })

	vim.api.nvim_create_user_command("OpenCodeRejectDiff", function(opts)
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end
		local hunk_idx = tonumber(opts.args) or 1
		M.reject_diff_hunk(file_path, hunk_idx)
	end, { nargs = "?", desc = "Reject diff hunk (default: first hunk)" })

	vim.api.nvim_create_user_command("OpenCodeAcceptAllDiffs", function()
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end
		M.accept_all_diffs(file_path)
	end, { desc = "Accept all diffs in current file" })

	vim.api.nvim_create_user_command("OpenCodeRejectAllDiffs", function()
		local file_path = vim.api.nvim_buf_get_name(0)
		if file_path == "" then
			logger.error("command", "No file in current buffer")
			return
		end
		M.reject_all_diffs(file_path)
	end, { desc = "Reject all diffs in current file" })

	vim.api.nvim_create_user_command("OpenCodeTestSelection", function()
		-- Test function to debug selection using the yank method
		print("Testing selection capture...")
		
		-- Save current register content
		local save_reg = vim.fn.getreg('"')
		local save_regtype = vim.fn.getregtype('"')
		
		-- Yank the visual selection to get the text
		vim.cmd('normal! gv"zy')
		local selected_text = vim.fn.getreg('z')
		
		-- Restore the register
		vim.fn.setreg('"', save_reg, save_regtype)
		
		if selected_text == "" then
			print("No text selected")
		else
			print("Selected text: '" .. selected_text .. "'")
			print("Length: " .. string.len(selected_text) .. " characters")
			local lines = vim.split(selected_text, '\n', {plain = true})
			print("Lines: " .. #lines)
		end
	end, { desc = "Test selection capture" })

	-- Set up diff signs
	vim.fn.sign_define("OpenCodeDiffAdd", {
		text = "+",
		texthl = "DiffAdd",
		linehl = "",
		numhl = "DiffAdd"
	})
	
	vim.fn.sign_define("OpenCodeDiffChange", {
		text = "~",
		texthl = "DiffChange",
		linehl = "",
		numhl = "DiffChange"
	})
	
	vim.fn.sign_define("OpenCodeDiffDelete", {
		text = "-",
		texthl = "DiffDelete",
		linehl = "",
		numhl = "DiffDelete"
	})

	-- Auto-start if configured
	if M.state.config.auto_start then
		M.start()
	end

	-- Cleanup on exit
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = vim.api.nvim_create_augroup("OpenCodeShutdown", { clear = true }),
		callback = function()
			if M.state.server then
				M.stop()
			end
		end,
		desc = "Automatically stop OpenCode integration when exiting Neovim",
	})

	M.state.initialized = true
	return M
end

return M
