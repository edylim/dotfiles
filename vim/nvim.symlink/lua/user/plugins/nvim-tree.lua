return {
  "nvim-tree/nvim-tree.lua",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local nvimtree = require("nvim-tree")

    vim.g.loaded_netrw = 1
    vim.g.loaded_netrwPlugin = 1

    vim.cmd([[ highlight NvimTreeIndentMarker guifg=#444444 ]])

    nvimtree.setup({
      view = {
        width = 40,
        relativenumber = true,
      },
      filters = {
        custom = { ".DS_Store" },
      },
      renderer = {
        indent_markers = {
          enable = true,
        },
        icons = {
          glyphs = {
            folder = {
              arrow_closed = "",
              arrow_open = "",
            },
          },
        },
      },
      git = {
        ignore = false,
      },
      actions = {
        open_file = {
          window_picker = {
            enable = false,
          },
        },
      },
    })
  end,
}
