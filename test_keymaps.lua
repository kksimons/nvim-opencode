-- Simple test script to verify keymaps are working
local opencode = require('opencode')

print("Testing OpenCode keymaps...")

-- Test 1: Check if the module loads
print("✓ OpenCode module loaded successfully")

-- Test 2: Check if functions exist
if opencode.send_selection then
    print("✓ send_selection function exists")
else
    print("✗ send_selection function missing")
end

if opencode.toggle_terminal then
    print("✓ toggle_terminal function exists")
else
    print("✗ toggle_terminal function missing")
end

if opencode.focus_opencode then
    print("✓ focus_opencode function exists")
else
    print("✗ focus_opencode function missing")
end

if opencode.focus_nvim then
    print("✓ focus_nvim function exists")
else
    print("✗ focus_nvim function missing")
end

-- Test 3: Check keymap setup
local keymaps = vim.api.nvim_get_keymap('v')
local has_a_keymap = false
for _, keymap in ipairs(keymaps) do
    if keymap.lhs == 'a' then
        has_a_keymap = true
        break
    end
end

if has_a_keymap then
    print("✓ Visual mode 'a' keymap is set")
else
    print("✗ Visual mode 'a' keymap is missing")
end

-- Test 4: Check normal mode leader+a keymap
local normal_keymaps = vim.api.nvim_get_keymap('n')
local has_leader_a = false
for _, keymap in ipairs(normal_keymaps) do
    if keymap.lhs:match('<leader>a') or keymap.lhs:match(' a') then
        has_leader_a = true
        break
    end
end

if has_leader_a then
    print("✓ Normal mode '<leader>a' keymap is set")
else
    print("✗ Normal mode '<leader>a' keymap is missing")
end

print("Keymap test complete!")