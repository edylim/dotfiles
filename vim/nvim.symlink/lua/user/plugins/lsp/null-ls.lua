return {
  "edylim/null-ls.nvim",
  event = { "BufReadPre", "BufNewFile" },
  config = function()
    local null_ls = require("null-ls")
    local null_ls_utils = require("null-ls.utils")
    local fmt = null_ls.builtins.formatting
    local diag = null_ls.builtins.diagnostics
    local aug = vim.api.nvim_create_augroup("LspFormatting", {}) -- to setup format on save

    null_ls.setup({
      root_dir = null_ls_utils.root_pattern("Brewfile", ".git", "package.json"),
      sources = {
        fmt.prettier.with({
          extra_filetypes = { "svelte" },
        }), -- js/ts formatter
        fmt.stylua, -- lua
        diag.eslint_d.with({
          condition = function(utils) -- lint condition
            return utils.root_has_file({ ".eslintrc.js" })
          end,
        }),
      },
      -- format on save
      on_attach = function(current_client, bufnr)
        if current_client.supports_method("textDocument/formatting") then
          vim.api.nvim_clear_autocmds({ group = aug, buffer = bufnr })
          vim.api.nvim_create_autocmd("BufWritePre", {
            group = aug,
            buffer = bufnr,
            callback = function()
              vim.lsp.buf.format({
                filter = function(client)
                  -- use null-ls
                  return client.name == "null-ls"
                end,
                bufnr = bufnr,
              })
            end,
          })
        end
      end,
    })
  end,
}
