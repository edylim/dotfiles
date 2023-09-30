return {
  "akinsho/bufferline.nvim",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  version = "*",
  opts = {
    options = {
      separator_style = "slope",
      always_show_bufferline = false,
      mode = "tabs",
      offsets = {
        {
          filetype = "NvimTree",
          text = function()
            return vim.fn.getcwd()
          end,
          highlight = "Directory",
          text_align = "left",
        },
      },
    },
  },
}
