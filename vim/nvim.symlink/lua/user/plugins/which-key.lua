return {
  "folke/which-key.nvim",
  event = "VeryLazy",
  init = function()
    vim.o.timeout = true
    vim.o.timeoutlen = 300
  end,
  opts = {
    layout = {
      align = "center",
    },
  },
  config = function()
    local wk = require("which-key")
    wk.register({
      ["<leader>"] = {
        q = { "Quit Grumpy Vim" },
        f = {
          name = "+file",
          f = { "<cmd>Telescope find_files<cr>", "Find File" },
          r = { "<cmd>Telescope oldfiles<cr>", "Open Recent File" },
          n = { "<cmd>enew<cr>", "New File" },
        },
      },
    })
  end,
}
