-- Simple test script to verify plugin structure
-- Run with: nvim --headless -c "luafile test.lua" -c "qa"

print("Testing nvim-opencode plugin...")

-- Test that the module can be loaded
local ok, opencode = pcall(require, "opencode")
if not ok then
	print("❌ Failed to load opencode module: " .. opencode)
	return
end

print("✅ Successfully loaded opencode module")

-- Test setup function
local setup_ok, setup_err = pcall(opencode.setup, {
	keybind = "<leader>t",
	terminal_size = 0.9,
})

if not setup_ok then
	print("❌ Failed to run setup: " .. setup_err)
	return
end

print("✅ Setup function works")

-- Test that functions exist
local functions = { "open", "close", "toggle", "is_open" }
for _, func in ipairs(functions) do
	if type(opencode[func]) ~= "function" then
		print("❌ Missing function: " .. func)
		return
	end
end

print("✅ All required functions exist")

-- Test is_open initially returns false
if opencode.is_open() ~= false then
	print("❌ is_open() should initially return false")
	return
end

print("✅ is_open() returns false initially")

print("🎉 All tests passed!")
print("")
print("To install the plugin:")
print("1. Copy the nvim-opencode directory to your Neovim plugin directory")
print("2. Add the LazyVim configuration from lazy-config-example.lua")
print("3. Restart Neovim and use <leader>A to toggle opencode")

