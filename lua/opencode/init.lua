---@brief [[
--- OpenCode Neovim Integration
---@brief ]]

local M = {}

--- @class OpenCode.Config
--- @field auto_start boolean
--- @field terminal_cmd string|nil
--- @field terminal { split_side: "left"|"right", split_width_percentage: number }

--- @type OpenCode.Config
local default_config = {
	auto_start = true,
	terminal_cmd = nil,
	terminal = {
		split_side = "right",
		split_width_percentage = 0.30,
	},
}

--- @class OpenCode.State
--- @field config OpenCode.Config
--- @field initialized boolean
--- @field terminal_buf number|nil
--- @field terminal_win number|nil
--- @field last_esc_time number|nil
--- @field last_focus "nvim"|"opencode"

--- @type OpenCode.State
M.state = {
	config = vim.deepcopy(default_config),
	initialized = false,
	terminal_buf = nil,
	terminal_win = nil, 
	last_esc_time = nil,
	last_focus = "nvim",
	port = nil,
	current_session = nil,
	file_context_added = false,
	file_context_path = nil,
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
		print("[OpenCode:" .. context .. "] DEBUG: " .. msg)
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







-- HTTP client for OpenCode server
local function http_request(port, endpoint, method, data)
	if not port then
		logger.error("http", "No port specified for HTTP request")
		return false, "No port"
	end

	method = method or "GET"
	local cmd
	if method == "POST" and data then
		cmd = string.format(
			'curl -s -X POST -H "Content-Type: application/json" -d %s "http://localhost:%d%s"',
			vim.fn.shellescape(vim.json.encode(data)),
			port,
			endpoint
		)
	elseif method == "DELETE" then
		cmd = string.format('curl -s -X DELETE "http://localhost:%d%s"', port, endpoint)
	else
		cmd = string.format('curl -s "http://localhost:%d%s"', port, endpoint)
	end
	
	local result = vim.fn.system(cmd)
	local success = vim.v.shell_error == 0
	if success and result ~= "" then
		local ok, decoded = pcall(vim.json.decode, result)
		if ok then
			return true, decoded
		end
	end
	return success, result
end

-- Wait for OpenCode server to be ready
local function wait_for_server(port, max_tries)
	max_tries = max_tries or 50
	local tries = 0
	
	while tries < max_tries do
		local success = http_request(port, "/app")
		if success then
			return true
		end
		
		tries = tries + 1
		vim.wait(200) -- Wait 200ms between tries
	end
	
	return false
end

-- Send text to OpenCode server
local function send_to_opencode(port, text)
	local success, result = http_request(port, "/tui/paste", "POST", { text = text })
	if success then
		local lines_count = 0
		if type(text) == "string" then
			for _ in text:gmatch("\n") do
				lines_count = lines_count + 1
			end
			lines_count = lines_count + 1
			local summary = string.format("[PASTED %d lines]", lines_count)
			-- Show summary in prompt
			http_request(port, "/tui/replace-prompt", "POST", { text = summary })
		else
			http_request(port, "/tui/replace-prompt", "POST", { text = "[PASTED MULTI-LINE TEXT]" })
		end
		logger.info("server", "Sent to OpenCode using paste endpoint")
		return true
	else
		logger.error("server", "Failed to send paste to OpenCode: " .. (result or "unknown error"))
		return false
	end
end

-- Generate a random port for OpenCode server
local function generate_port()
	return math.random(16384, 65535)
end

-- Terminal management
local function create_terminal()
	local opencode_cmd = get_opencode_cmd()
	local cwd = vim.fn.getcwd()

	-- Generate a random port for the server
	local port = generate_port()
	M.state.port = port -- Store port for API calls
	
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

	-- Start OpenCode in server mode (like VSCode does)
	local opencode_command = string.format(
		"OPENCODE_THEME=system OPENCODE_CALLER=nvim %s --port %d %s",
		opencode_cmd,
		port,
		cwd
	)

	-- Start opencode with server mode
	local job_id = vim.fn.termopen(opencode_command, {
		cwd = cwd,
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

	-- Set terminal window options - disable ALL visual elements
	vim.wo[term_win].number = false
	vim.wo[term_win].relativenumber = false
	vim.wo[term_win].signcolumn = "no"
	vim.wo[term_win].wrap = false
	vim.wo[term_win].cursorline = false
	vim.wo[term_win].cursorcolumn = false
	vim.wo[term_win].colorcolumn = ""
	vim.wo[term_win].foldcolumn = "0"
	vim.wo[term_win].statuscolumn = ""
	vim.wo[term_win].linebreak = false
	vim.wo[term_win].breakindent = false

	-- Set buffer options
	vim.bo[term_buf].bufhidden = "hide"
	vim.bo[term_buf].swapfile = false

	-- Set up terminal-specific keymaps
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"<leader>A",
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
	-- Add '1' and '9' keymaps for focus switching
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"1",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim editor" }
	)
	vim.api.nvim_buf_set_keymap(
		term_buf,
		"t",
		"9",
		'<C-\\><C-n>:lua require("opencode").focus_opencode()<CR>',
		{ noremap = true, silent = true, desc = "Focus OpenCode terminal" }
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

	-- Set terminal window options - disable ALL visual elements
	vim.wo[term_win].number = false
	vim.wo[term_win].relativenumber = false
	vim.wo[term_win].signcolumn = "no"
	vim.wo[term_win].wrap = false
	vim.wo[term_win].cursorline = false
	vim.wo[term_win].cursorcolumn = false
	vim.wo[term_win].colorcolumn = ""
	vim.wo[term_win].foldcolumn = "0"
	vim.wo[term_win].statuscolumn = ""
	vim.wo[term_win].linebreak = false
	vim.wo[term_win].breakindent = false

	-- Set up terminal-specific keymaps for reopened terminal
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"<leader>A",
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
	-- Add '1' and '9' keymaps for focus switching
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"1",
		'<C-\\><C-n>:lua require("opencode").focus_nvim()<CR>',
		{ noremap = true, silent = true, desc = "Focus Neovim editor" }
	)
	vim.api.nvim_buf_set_keymap(
		M.state.terminal_buf,
		"t",
		"9",
		'<C-\\><C-n>:lua require("opencode").focus_opencode()<CR>',
		{ noremap = true, silent = true, desc = "Focus OpenCode terminal" }
	)

	-- Focus the terminal and enter insert mode
	vim.api.nvim_set_current_win(term_win)
	vim.cmd("startinsert")

	logger.info("terminal", "OpenCode terminal reopened")
end



-- Send file to opencode with content
function M.send_file(file_path, start_line, end_line)
	-- Format file path
	local formatted_path = file_path
	local cwd = vim.fn.getcwd()
	if string.find(file_path, cwd, 1, true) == 1 then
		formatted_path = string.sub(file_path, #cwd + 2)
	end

	-- Read file content
	local content
	if start_line and end_line then
		-- Read specific line range
		local lines = vim.fn.readfile(file_path)
		if #lines > 0 then
			local selected_lines = {}
			for i = start_line + 1, math.min(end_line + 1, #lines) do
				table.insert(selected_lines, lines[i])
			end
			content = table.concat(selected_lines, "\n")
		else
			content = ""
		end
	else
		-- Read entire file
		local lines = vim.fn.readfile(file_path)
		content = table.concat(lines, "\n")
	end

	-- Format the message to send to OpenCode
	local message
	if start_line and end_line then
		message = string.format("File: %s (lines %d-%d)\n```\n%s\n```", 
			formatted_path, start_line + 1, end_line + 1, content)
	else
		message = string.format("File: %s\n```\n%s\n```", formatted_path, content)
	end

	-- Send to opencode terminal
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			vim.fn.jobsend(job_id, message)
			logger.info("command", "Sent file content: " .. formatted_path)
			M.focus_opencode()
			return true
		end
	end

	logger.error("command", "OpenCode terminal not available")
	return false
end

-- Send selected text to opencode
function M.send_selection()
	-- Save current register content
	local save_reg = vim.fn.getreg('"')
	local save_regtype = vim.fn.getregtype('"')

	-- Yank the visual selection to get the text
	vim.cmd('normal! gv"zy')
	local selected_text = vim.fn.getreg("z")

	-- Restore the register
	vim.fn.setreg('"', save_reg, save_regtype)

	if selected_text == "" then
		logger.error("command", "No text selected")
		return false, "No selection"
	end

	-- Use send_to_opencode function for accurate line counting
	if M.state.port then
		local success = send_to_opencode(M.state.port, selected_text)
		if success then
			logger.info("command", "Sent selection to OpenCode: " .. string.len(selected_text) .. " characters")
			M.focus_opencode()
			return true
		else
			logger.error("command", "Failed to send selection via API")
		end
	else
		logger.error("command", "OpenCode server not available")
	end

	return false, "Failed to send selection"
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
	-- Get clipboard content from system clipboard
	local clipboard_text = vim.fn.getreg('+')
	if clipboard_text == "" then
		-- Fallback to unnamed register if system clipboard is empty
		clipboard_text = vim.fn.getreg('"')
	end

	if clipboard_text == "" then
		logger.error("command", "No text in clipboard")
		return false, "No clipboard content"
	end

	-- Copy to system clipboard (in case it was from unnamed register)
	vim.fn.setreg('+', clipboard_text)
	vim.fn.setreg('*', clipboard_text) -- Also set the selection register for compatibility

	-- Focus OpenCode terminal so user can paste
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		M.focus_opencode()
		-- Send Ctrl+V to paste (this will trigger OpenCode's paste detection)
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			-- Wait a moment then paste
			vim.defer_fn(function()
				if vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
					vim.fn.jobsend(job_id, "\x16") -- Ctrl+V
				end
			end, 100)
			
			logger.info(
				"command",
				"Sent clipboard to OpenCode terminal: " .. string.len(clipboard_text) .. " characters"
			)
			return true
		end
	end

	logger.error("command", "OpenCode terminal not available")
	return false, "Terminal not available"
end

-- Clear the OpenCode input box
function M.clear_input()
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

	logger.error("command", "OpenCode terminal not available")
	return false, "Terminal not available"
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
			if
				buf_type == ""
				and filetype ~= "NvimTree"
				and filetype ~= "neo-tree"
				and filetype ~= "oil"
				and filetype ~= "dirvish"
				and filetype ~= "netrw"
				and not buf_name:match("NvimTree")
				and not buf_name:match("neo%-tree")
			then
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



-- Session Management API
function M.create_session(provider, model)
	if not M.state.port then
		logger.error("session", "OpenCode server not running")
		return nil
	end

	local data = {}
	if provider then data.provider = provider end
	if model then data.model = model end

	local success, result = http_request(M.state.port, "/session", "POST", data)
	if success and result and result.id then
		M.state.current_session = result.id
		logger.info("session", "Created session: " .. result.id)
		return result
	else
		logger.error("session", "Failed to create session: " .. (result or "unknown error"))
		return nil
	end
end

function M.list_sessions()
	if not M.state.port then
		logger.error("session", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/session")
	if success then
		return result
	else
		logger.error("session", "Failed to list sessions: " .. (result or "unknown error"))
		return nil
	end
end

function M.delete_session(session_id)
	if not M.state.port then
		logger.error("session", "OpenCode server not running")
		return false
	end

	session_id = session_id or M.state.current_session
	if not session_id then
		logger.error("session", "No session ID provided")
		return false
	end

	local success, result = http_request(M.state.port, "/session/" .. session_id, "DELETE")
	if success then
		if M.state.current_session == session_id then
			M.state.current_session = nil
		end
		logger.info("session", "Deleted session: " .. session_id)
		return true
	else
		logger.error("session", "Failed to delete session: " .. (result or "unknown error"))
		return false
	end
end

function M.send_message(message, session_id)
	if not M.state.port then
		logger.error("session", "OpenCode server not running")
		return nil
	end

	session_id = session_id or M.state.current_session
	if not session_id then
		logger.error("session", "No session ID provided")
		return nil
	end

	local data = { message = message }
	local success, result = http_request(M.state.port, "/session/" .. session_id .. "/message", "POST", data)
	if success then
		logger.info("session", "Sent message to session: " .. session_id)
		return result
	else
		logger.error("session", "Failed to send message: " .. (result or "unknown error"))
		return nil
	end
end

function M.get_session_messages(session_id)
	if not M.state.port then
		logger.error("session", "OpenCode server not running")
		return nil
	end

	session_id = session_id or M.state.current_session
	if not session_id then
		logger.error("session", "No session ID provided")
		return nil
	end

	local success, result = http_request(M.state.port, "/session/" .. session_id .. "/message")
	if success then
		return result
	else
		logger.error("session", "Failed to get messages: " .. (result or "unknown error"))
		return nil
	end
end

-- File Management API
function M.read_file(file_path)
	if not M.state.port then
		logger.error("file", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/file?path=" .. vim.fn.shellescape(file_path))
	if success then
		return result
	else
		logger.error("file", "Failed to read file: " .. (result or "unknown error"))
		return nil
	end
end

function M.find_text(query, file_pattern)
	if not M.state.port then
		logger.error("search", "OpenCode server not running")
		return nil
	end

	local params = "?query=" .. vim.fn.shellescape(query)
	if file_pattern then
		params = params .. "&pattern=" .. vim.fn.shellescape(file_pattern)
	end

	local success, result = http_request(M.state.port, "/find" .. params)
	if success then
		return result
	else
		logger.error("search", "Failed to search text: " .. (result or "unknown error"))
		return nil
	end
end

function M.find_files(pattern)
	if not M.state.port then
		logger.error("search", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/find/file?pattern=" .. vim.fn.shellescape(pattern))
	if success then
		return result
	else
		logger.error("search", "Failed to search files: " .. (result or "unknown error"))
		return nil
	end
end

function M.find_symbols(query)
	if not M.state.port then
		logger.error("search", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/find/symbol?query=" .. vim.fn.shellescape(query))
	if success then
		return result
	else
		logger.error("search", "Failed to search symbols: " .. (result or "unknown error"))
		return nil
	end
end

-- App Information API
function M.get_app_info()
	if not M.state.port then
		logger.error("app", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/app")
	if success then
		return result
	else
		logger.error("app", "Failed to get app info: " .. (result or "unknown error"))
		return nil
	end
end

function M.get_config()
	if not M.state.port then
		logger.error("config", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/config")
	if success then
		return result
	else
		logger.error("config", "Failed to get config: " .. (result or "unknown error"))
		return nil
	end
end

function M.get_providers()
	if not M.state.port then
		logger.error("config", "OpenCode server not running")
		return nil
	end

	local success, result = http_request(M.state.port, "/config/providers")
	if success then
		return result
	else
		logger.error("config", "Failed to get providers: " .. (result or "unknown error"))
		return nil
	end
end

-- TUI Control API
function M.open_help()
	if not M.state.port then
		logger.error("tui", "OpenCode server not running")
		return false
	end

	local success, result = http_request(M.state.port, "/tui/open-help", "POST")
	if success then
		logger.info("tui", "Opened help dialog")
		return true
	else
		logger.error("tui", "Failed to open help: " .. (result or "unknown error"))
		return false
	end
end

-- Logging API
function M.send_log(level, message, context)
	if not M.state.port then
		return -- Don't log errors when logging itself
	end

	local data = {
		level = level or "info",
		message = message,
		context = context or "nvim-plugin"
	}

	local success = http_request(M.state.port, "/log", "POST", data)
	if not success then
		-- Don't spam console if logging fails
	end
end

-- Send current buffer context to OpenCode
function M.send_current_file()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path == "" then
		logger.error("command", "No file in current buffer")
		return false
	end

	return M.send_file(file_path)
end

-- Send current buffer with cursor context (surrounding lines)
function M.send_current_context(lines_before, lines_after)
	lines_before = lines_before or 10
	lines_after = lines_after or 10

	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path == "" then
		logger.error("command", "No file in current buffer")
		return false
	end

	-- Get current cursor position
	local cursor = vim.api.nvim_win_get_cursor(0)
	local current_line = cursor[1] -- 1-based
	local current_col = cursor[2] -- 0-based

	-- Get buffer content
	local total_lines = vim.api.nvim_buf_line_count(0)
	local start_line = math.max(1, current_line - lines_before)
	local end_line = math.min(total_lines, current_line + lines_after)

	local lines = vim.api.nvim_buf_get_lines(0, start_line - 1, end_line, false)
	local content = table.concat(lines, "\n")

	-- Get relative path
	local formatted_path = file_path
	local cwd = vim.fn.getcwd()
	if string.find(file_path, cwd, 1, true) == 1 then
		formatted_path = string.sub(file_path, #cwd + 2)
	end

	-- Format message with cursor position indicator
	local message = string.format(
		"File: %s (lines %d-%d, cursor at line %d, col %d)\n```\n%s\n```",
		formatted_path, start_line, end_line, current_line, current_col + 1, content
	)

	-- Send to OpenCode terminal
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			vim.fn.jobsend(job_id, message)
			logger.info("command", "Sent current context: " .. formatted_path .. " around line " .. current_line)
			M.focus_opencode()
			return true
		end
	end

	logger.error("command", "OpenCode terminal not available")
	return false
end

-- Send current function/method context to OpenCode
function M.send_current_function()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path == "" then
		logger.error("command", "No file in current buffer")
		return false
	end

	-- Try to find the current function using treesitter if available
	local has_ts, ts_utils = pcall(require, "nvim-treesitter.ts_utils")
	if has_ts then
		local current_node = ts_utils.get_node_at_cursor()
		if current_node then
			-- Walk up the tree to find a function node
			local function_node = current_node
			while function_node do
				local node_type = function_node:type()
				if node_type:match("function") or node_type:match("method") or node_type:match("def") then
					break
				end
				function_node = function_node:parent()
			end

			if function_node then
				local start_row, start_col, end_row, end_col = function_node:range()
				-- Send the function range
				return M.send_file(file_path, start_row, end_row)
			end
		end
	end

	-- Fallback: send context around cursor if treesitter is not available
	logger.info("command", "Treesitter not available, sending cursor context instead")
	return M.send_current_context(20, 20)
end

-- Add current file context to OpenCode session
function M.add_file_context()
	local file_path = vim.api.nvim_buf_get_name(0)
	if file_path == "" then
		logger.error("context", "No file in current buffer")
		return false
	end

	-- Check if context is already added
	if M.state.file_context_added and M.state.file_context_path == file_path then
		logger.info("context", "File context already added")
		return true
	end

	-- Send file content with a context marker
	local formatted_path = file_path
	local cwd = vim.fn.getcwd()
	if string.find(file_path, cwd, 1, true) == 1 then
		formatted_path = string.sub(file_path, #cwd + 2)
	end

	-- Read entire file
	local lines = vim.fn.readfile(file_path)
	local content = table.concat(lines, "\n")

	-- Format message with context marker
	local message = string.format(
		"[CONTEXT ADDED] File: %s\n```\n%s\n```\n\nThis file is now in context. You can reference it in our conversation.",
		formatted_path, content
	)

	-- Use send_to_opencode function for accurate line counting
	if M.state.port then
		local success = send_to_opencode(M.state.port, message)
		if success then
			M.state.file_context_added = true
			M.state.file_context_path = file_path
			logger.info("context", "Added file context: " .. formatted_path .. " (" .. #lines .. " lines)")
			M.focus_opencode()
			return true
		else
			logger.error("context", "Failed to add file context via API")
		end
	else
		logger.error("context", "OpenCode server not available")
	end

	return false
end

-- Remove current file context from OpenCode session
function M.remove_file_context()
	if not M.state.file_context_added then
		logger.info("context", "No file context to remove")
		return true
	end

	-- Get the formatted path for the message
	local formatted_path = M.state.file_context_path
	local cwd = vim.fn.getcwd()
	if string.find(M.state.file_context_path, cwd, 1, true) == 1 then
		formatted_path = string.sub(M.state.file_context_path, #cwd + 2)
	end

	-- Send context removal message
	local message = string.format(
		"[CONTEXT REMOVED] File: %s is no longer in context. Please ignore previous file content unless specifically referenced.",
		formatted_path
	)

	-- Send to opencode terminal
	if M.state.terminal_buf and vim.api.nvim_buf_is_valid(M.state.terminal_buf) then
		local job_id = vim.b[M.state.terminal_buf].terminal_job_id
		if job_id then
			vim.fn.jobsend(job_id, message)
			M.state.file_context_added = false
			M.state.file_context_path = nil
			logger.info("context", "Removed file context: " .. formatted_path)
			M.focus_opencode()
			return true
		end
	end

	logger.error("context", "OpenCode terminal not available")
	return false
end

-- Toggle file context
function M.toggle_file_context()
	if M.state.file_context_added then
		return M.remove_file_context()
	else
		return M.add_file_context()
	end
end

-- Diff management functions (stubs for now)
function M.accept_diff_hunk(file_path, hunk_index)
	logger.info("diff", "Accept diff hunk not implemented yet: " .. file_path .. " hunk " .. hunk_index)
	return false
end

function M.reject_diff_hunk(file_path, hunk_index)
	logger.info("diff", "Reject diff hunk not implemented yet: " .. file_path .. " hunk " .. hunk_index)
	return false
end

function M.accept_all_diffs(file_path)
	logger.info("diff", "Accept all diffs not implemented yet: " .. file_path)
	return false
end

function M.reject_all_diffs(file_path)
	logger.info("diff", "Reject all diffs not implemented yet: " .. file_path)
	return false
end

function M.prev_diff_file()
	logger.info("diff", "Navigate to previous diff file not implemented yet")
	return false
end

function M.next_diff_file()
	logger.info("diff", "Navigate to next diff file not implemented yet")
	return false
end

-- Setup function
function M.setup(opts)
	opts = opts or {}

	-- Merge config
	M.state.config = vim.tbl_deep_extend("force", default_config, opts)



	-- Create commands

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

	-- Session Management Commands
	vim.api.nvim_create_user_command("OpenCodeCreateSession", function(cmd_opts)
		local args = vim.split(cmd_opts.args, " ")
		local provider = args[1]
		local model = args[2]
		local session = M.create_session(provider, model)
		if session then
			print("Created session: " .. session.id)
		else
			print("Failed to create session")
		end
	end, { nargs = "*", desc = "Create new OpenCode session [provider] [model]" })

	vim.api.nvim_create_user_command("OpenCodeListSessions", function()
		local sessions = M.list_sessions()
		if sessions then
			print("OpenCode Sessions:")
			for _, session in ipairs(sessions) do
				local current = (session.id == M.state.current_session) and " (current)" or ""
				print("  " .. session.id .. current)
			end
		else
			print("Failed to get sessions")
		end
	end, { desc = "List OpenCode sessions" })

	vim.api.nvim_create_user_command("OpenCodeDeleteSession", function(cmd_opts)
		local session_id = cmd_opts.args ~= "" and cmd_opts.args or nil
		if M.delete_session(session_id) then
			print("Session deleted")
		else
			print("Failed to delete session")
		end
	end, { nargs = "?", desc = "Delete OpenCode session [session_id]" })

	vim.api.nvim_create_user_command("OpenCodeSendMessage", function(cmd_opts)
		if cmd_opts.args == "" then
			print("Please provide a message")
			return
		end
		local result = M.send_message(cmd_opts.args)
		if result then
			print("Message sent")
		else
			print("Failed to send message")
		end
	end, { nargs = "+", desc = "Send message to current session" })

	vim.api.nvim_create_user_command("OpenCodeGetMessages", function(cmd_opts)
		local session_id = cmd_opts.args ~= "" and cmd_opts.args or nil
		local messages = M.get_session_messages(session_id)
		if messages then
			print("Session Messages:")
			for i, msg in ipairs(messages) do
				print(i .. ". [" .. (msg.role or "unknown") .. "] " .. (msg.content or "[empty]"))
			end
		else
			print("Failed to get messages")
		end
	end, { nargs = "?", desc = "Get messages from session [session_id]" })

	-- Search Commands
	vim.api.nvim_create_user_command("OpenCodeFindText", function(cmd_opts)
		if cmd_opts.args == "" then
			print("Please provide search query")
			return
		end
		local args = vim.split(cmd_opts.args, " ", { trimempty = true })
		local query = args[1]
		local pattern = args[2]
		local results = M.find_text(query, pattern)
		if results then
			print("Search results for '" .. query .. "':")
			if type(results) == "table" then
				for _, result in ipairs(results) do
					print("  " .. (result.file or "unknown") .. ":" .. (result.line or "?") .. " - " .. (result.text or ""))
				end
			else
				print(vim.inspect(results))
			end
		else
			print("Failed to search text")
		end
	end, { nargs = "+", desc = "Search for text in files [query] [pattern]" })

	vim.api.nvim_create_user_command("OpenCodeFindFiles", function(cmd_opts)
		if cmd_opts.args == "" then
			print("Please provide file pattern")
			return
		end
		local results = M.find_files(cmd_opts.args)
		if results then
			print("File search results for '" .. cmd_opts.args .. "':")
			if type(results) == "table" then
				for _, file in ipairs(results) do
					print("  " .. file)
				end
			else
				print(vim.inspect(results))
			end
		else
			print("Failed to search files")
		end
	end, { nargs = "+", desc = "Search for files by pattern" })

	vim.api.nvim_create_user_command("OpenCodeFindSymbols", function(cmd_opts)
		if cmd_opts.args == "" then
			print("Please provide symbol query")
			return
		end
		local results = M.find_symbols(cmd_opts.args)
		if results then
			print("Symbol search results for '" .. cmd_opts.args .. "':")
			if type(results) == "table" then
				for _, symbol in ipairs(results) do
					print("  " .. (symbol.name or "unknown") .. " in " .. (symbol.file or "unknown") .. ":" .. (symbol.line or "?"))
				end
			else
				print(vim.inspect(results))
			end
		else
			print("Failed to search symbols")
		end
	end, { nargs = "+", desc = "Search for symbols" })

	-- Information Commands
	vim.api.nvim_create_user_command("OpenCodeInfo", function()
		local info = M.get_app_info()
		if info then
			print("OpenCode App Info:")
			print(vim.inspect(info))
		else
			print("Failed to get app info")
		end
	end, { desc = "Get OpenCode application information" })

	vim.api.nvim_create_user_command("OpenCodeConfig", function()
		local config = M.get_config()
		if config then
			print("OpenCode Configuration:")
			print(vim.inspect(config))
		else
			print("Failed to get config")
		end
	end, { desc = "Get OpenCode configuration" })

	vim.api.nvim_create_user_command("OpenCodeProviders", function()
		local providers = M.get_providers()
		if providers then
			print("Available Providers:")
			if type(providers) == "table" then
				for name, provider in pairs(providers) do
					print("  " .. name .. ": " .. (provider.description or "no description"))
					if provider.models then
						for _, model in ipairs(provider.models) do
							print("    - " .. model)
						end
					end
				end
			else
				print(vim.inspect(providers))
			end
		else
			print("Failed to get providers")
		end
	end, { desc = "List available AI providers and models" })

	-- TUI Commands
	vim.api.nvim_create_user_command("OpenCodeHelp", function()
		if M.open_help() then
			print("Opened OpenCode help")
		else
			print("Failed to open help")
		end
	end, { desc = "Open OpenCode help dialog" })

	-- Context Commands (easy file sharing)
	vim.api.nvim_create_user_command("OpenCodeSendFile", function()
		M.send_current_file()
	end, { desc = "Send current file to OpenCode" })

	vim.api.nvim_create_user_command("OpenCodeSendContext", function(cmd_opts)
		local args = vim.split(cmd_opts.args, " ")
		local lines_before = tonumber(args[1]) or 10
		local lines_after = tonumber(args[2]) or lines_before
		M.send_current_context(lines_before, lines_after)
	end, { nargs = "*", desc = "Send current context to OpenCode [lines_before] [lines_after]" })

	vim.api.nvim_create_user_command("OpenCodeSendFunction", function()
		M.send_current_function()
	end, { desc = "Send current function/method to OpenCode" })



	vim.api.nvim_create_user_command("OpenCodeTestSelection", function()
		-- Test function to debug selection using the yank method
		print("Testing selection capture...")

		-- Save current register content
		local save_reg = vim.fn.getreg('"')
		local save_regtype = vim.fn.getregtype('"')

		-- Yank the visual selection to get the text
		vim.cmd('normal! gv"zy')
		local selected_text = vim.fn.getreg("z")

		-- Restore the register
		vim.fn.setreg('"', save_reg, save_regtype)

		if selected_text == "" then
			print("No text selected")
		else
			print("Selected text: '" .. selected_text .. "'")
			print("Length: " .. string.len(selected_text) .. " characters")
			local lines = vim.split(selected_text, "\n", { plain = true })
			print("Lines: " .. #lines)
		end
	end, { desc = "Test selection capture" })



	-- Set up global keymaps for easy file context toggling
	vim.api.nvim_set_keymap("n", "<leader>+", ':lua require("opencode").add_file_context()<CR>', 
		{ noremap = true, silent = true, desc = "Add current file to OpenCode context" })
	vim.api.nvim_set_keymap("n", "<leader>-", ':lua require("opencode").remove_file_context()<CR>', 
		{ noremap = true, silent = true, desc = "Remove current file from OpenCode context" })
	vim.api.nvim_set_keymap("n", "<leader>=", ':lua require("opencode").toggle_file_context()<CR>', 
		{ noremap = true, silent = true, desc = "Toggle current file context in OpenCode" })

	-- Auto-start terminal if configured
	if M.state.config.auto_start then
		M.toggle_terminal()
	end

	M.state.initialized = true
	return M
end

return M
