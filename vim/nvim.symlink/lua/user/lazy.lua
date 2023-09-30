local lazy = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not vim.loop.fs_stat(lazy) then
  vim.fn.system({
    "git",
    "clone",
    "https://github.com/folke/lazy.nvim.git",
    "--branch=stable",
    "--filter=blob:none",
    lazy,
  })
end

vim.opt.rtp:prepend(lazy)

require("lazy").setup({
  { import = "user.plugins" },
  { import = "user.plugins.lsp" },
}, {
  install = {
    colorscheme = { "gruvbox" },
  },
  change_detection = {
    notify = false,
  },
  checker = {
    enabled = true,
    notify = false,
  },
})
