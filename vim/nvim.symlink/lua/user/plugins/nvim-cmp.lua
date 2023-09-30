return {
  "hrsh7th/nvim-cmp",
  event = "InsertEnter",
  dependencies = {
    "hrsh7th/cmp-buffer",
    "hrsh7th/cmp-path",
    "saadparwaiz1/cmp_luasnip",
    "onsails/lspkind.nvim",
    "rafamadriz/friendly-snippets",
    "L3MON4D3/LuaSnip",
  },
  config = function()
    local cmp = require("cmp")
    local lspkind = require("lspkind")
    local luasnip = require("luasnip")

    require("luasnip.loaders.from_vscode").lazy_load()

    cmp.setup({
      completion = {
        completeopt = "menu,menuone,preview,noselect",
      },
      snippet = {
        expand = function(args)
          luasnip.lsp_expand(args.body)
        end,
      },
      mapping = cmp.mapping.preset.insert({
        ["<C-k>"] = cmp.mapping.select_prev_item(),
        ["<C-j>"] = cmp.mapping.select_next_item(),
        ["<C-h>"] = cmp.mapping.scroll_docs(-4),
        ["<C-l>"] = cmp.mapping.scroll_docs(4),
        ["<C-Space>"] = cmp.mapping.complete(),
        ["<C-e>"] = cmp.mapping(function()
          vim.api.nvim_feedkeys("<ESC>", "t", true)
          cmp.mapping.abort()
        end),
        ["<CR>"] = cmp.mapping.confirm({ select = false }),
      }),
      sources = cmp.config.sources({
        { name = "buffer" },
        { name = "luasnip" },
        { name = "nvim_lsp" },
        { name = "path" },
      }),
      formatting = {
        format = lspkind.cmp_format({
          maxwidth = 50,
          ellipsis_char = "...",
        }),
      },
    })
  end,
}
