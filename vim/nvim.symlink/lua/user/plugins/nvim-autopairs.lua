return {
  "windwp/nvim-autopairs",
  event = { "InsertEnter" },
  dependencies = {
    "hrsh7th/nvim-cmp",
  },
  config = function()
    local autopairs = require("nvim-autopairs")
    local cmp = require("cmp")
    local autopairs_cmp = require("nvim-autopairs.completion.cmp")

    autopairs.setup({
      check_ts = true,
      ts_config = {
        lua = { "string" }, -- no pairs in lua string treesitter
        javascript = { "template_string" }, -- no pairs in js template_string treesitter
      },
    })

    cmp.event:on("confirm_done", autopairs_cmp.on_confirm_done())
  end,
}
