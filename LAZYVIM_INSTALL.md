# LazyVim Installation Guide for nvim-opencode

This guide shows how to install and configure the nvim-opencode plugin in LazyVim for testing and development.

## Prerequisites

1. **Install opencode** (if not already installed):
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   # or
   npm i -g opencode-ai@latest
   # or
   brew install sst/tap/opencode
   ```

2. **Verify opencode is working**:
   ```bash
   opencode --version
   ```

## Installation

### Method 1: Local Development (Recommended for Testing)

1. **Clone the plugin locally**:
   ```bash
   git clone https://github.com/your-username/nvim-opencode.git ~/.local/share/nvim-opencode
   ```

2. **Create plugin configuration** in `~/.config/nvim/lua/plugins/opencode.lua`:
   ```lua
   return {
     {
       dir = "~/.local/share/nvim-opencode", -- Local path
       name = "nvim-opencode",
       event = "VeryLazy",
       config = function()
         require("opencode").setup({
           keybind = "<leader>a",  -- Toggle with leader+a
           terminal_size = 0.8,    -- 80% for float, try 0.4 for splits
           position = "float",     -- "float", "bottom", or "right"
         })
       end,
       keys = {
         { "<leader>a", function() require("opencode").toggle() end, desc = "Toggle opencode" },
       },
     },
   }
   ```

### Method 2: From GitHub Repository

```lua
return {
  {
    "your-username/nvim-opencode",
    event = "VeryLazy",
    config = function()
      require("opencode").setup({
        keybind = "<leader>a",
        terminal_size = 0.8,
        position = "float",
      })
    end,
    keys = {
      { "<leader>a", function() require("opencode").toggle() end, desc = "Toggle opencode" },
    },
  },
}
```

## Configuration Examples

### Floating Window (Default)
```lua
require("opencode").setup({
  keybind = "<leader>a",
  terminal_size = 0.8,  -- 80% of screen
  position = "float",
})
```

### Bottom Split (Like Terminal)
```lua
require("opencode").setup({
  keybind = "<leader>a",
  terminal_size = 0.4,  -- 40% of screen height
  position = "bottom",
})
```

### Right Split (Like File Explorer)
```lua
require("opencode").setup({
  keybind = "<leader>a", 
  terminal_size = 0.4,  -- 40% of screen width
  position = "right",
})
```

## Testing the Plugin

1. **Restart Neovim** or run `:Lazy reload nvim-opencode`

2. **Test the keybinding**:
   - Press `<leader>a` (usually `\a` or ` a` depending on your leader key)
   - opencode should open in the configured position

3. **Test commands**:
   ```vim
   :OpencodeToggle
   :OpencodeOpen  
   :OpencodeClose
   ```

4. **In the opencode terminal**:
   - `<Esc>` to exit insert mode
   - `<leader>a` to close opencode
   - Normal opencode commands work

## Troubleshooting

### Plugin Not Loading
- Check `:Lazy` to see if the plugin is loaded
- Verify the file path in `~/.config/nvim/lua/plugins/opencode.lua`
- Restart Neovim completely

### opencode Command Not Found
- Ensure opencode is in your PATH: `which opencode`
- The plugin checks these paths automatically:
  - `opencode` (in PATH)
  - `~/.local/bin/opencode`
  - `/usr/local/bin/opencode`
  - `/opt/homebrew/bin/opencode`

### Keybinding Conflicts
- Check if `<leader>a` conflicts with other plugins
- Change the keybind in your configuration:
  ```lua
  keybind = "<leader>oc", -- Use leader+oc instead
  ```

### Window Size Issues
- For splits, try smaller sizes: `terminal_size = 0.3` or `0.4`
- For floating windows, `0.8` is usually good
- Adjust based on your screen size and preferences

## Development Workflow

1. **Make changes** to the plugin files
2. **Reload the plugin**: `:Lazy reload nvim-opencode`
3. **Test the changes**: Press `<leader>a`
4. **Check for errors**: `:messages`

## Advanced Configuration

### Custom Keybindings
```lua
keys = {
  { "<leader>a", function() require("opencode").toggle() end, desc = "Toggle opencode" },
  { "<leader>oo", function() require("opencode").open() end, desc = "Open opencode" },
  { "<leader>oc", function() require("opencode").close() end, desc = "Close opencode" },
},
```

### Multiple Configurations
You can create different configurations for different projects by using LazyVim's conditional loading:

```lua
return {
  {
    dir = "~/.local/share/nvim-opencode",
    name = "nvim-opencode",
    event = "VeryLazy",
    cond = function()
      -- Only load in specific directories
      return vim.fn.getcwd():match("/path/to/project")
    end,
    config = function()
      require("opencode").setup({
        position = "bottom", -- Different config for this project
        terminal_size = 0.3,
      })
    end,
  },
}
```

## Next Steps

Once you've tested the plugin and it's working well:

1. **Publish to GitHub** if you haven't already
2. **Update the repository URL** in your LazyVim config
3. **Consider contributing** improvements back to the project
4. **Share your configuration** with the community

The plugin now supports all three window positions (float, bottom, right) with configurable sizes, making it flexible for different workflows and preferences.