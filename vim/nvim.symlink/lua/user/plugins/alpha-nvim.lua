return {
  "goolord/alpha-nvim",
  event = "VimEnter",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  config = function()
    local dashboard = require("alpha.themes.dashboard")

    -- create array of colors for header image
    local header_color = function()
      local no_cols = 170
      local no_rows = 27
      local color = "GruvboxBlue" -- For more colors, use :highlight
      local color_array = {}
      for i = 1, no_rows do
        color_array[i] = { { color, 0, no_cols } }
      end
      return color_array
    end

    dashboard.section.buttons.val = {
      dashboard.button(
        "SPC f b",
        "  > [f]ile [b]rowser",
        "<cmd>Telescope file_browser path=%:p:h select_buffer=true<CR>"
      ),
      -- nvim-tree/nvim-tree
      dashboard.button("SPC p t", "  > Toggle [p]roject [t]ree", "<cmd>NvimTreeToggle<CR>"),
      -- nvim-telescope/telescope
      dashboard.button("SPC p f", "󰱼  > Find [p]roject [f]ile", "<cmd>Telescope find_files<CR>"),
      dashboard.button("SPC   /", "  > Fuzzy search", "<cmd>Telescope live_grep<CR>"),
      -- rmagatti/auto-session
      dashboard.button("SPC w r", "󰁯  > Restore [w]indow [r]estore session", "<cmd>SessionRestore<CR>"),
      dashboard.button("q", " >  Quit grumpyVIM", "<cmd>qa<CR>"),
    }

    dashboard.section.header.val = {
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⡴⠒⠢⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡞⠀⠀⠀⠈⠳⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣠⣤⡀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠁⢀⣤⠀⠀⠀⠘⢷⣄⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠞⠁⠀⠀⡇⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⠀⢸⣿⡇⠀⠀⠀⠀⠉⠳⣄⡀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡠⠊⠀⠀⠀⠀⢀⡇⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡆⠘⠻⣷⠀⠀⠀⠀⠀⠀⠈⠛⢦⣄⠀⠀⣀⣤⣶⣶⣶⣤⣤⣤⣤⣄⣀⣀⣀⡠⠔⠊⠀⠀⠀⠀⠀⠀⣼⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢣⠀⠀⢿⡇⠀⠀⠀⠀⠀⠀⠀⣀⣽⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣤⣀⣀⠀⠀⠀⠀⠀⢠⠇⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠘⡄⠀⠀⠀⠀⠀⠀⠀⢀⣴⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠛⢿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⡞⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢧⠀⠀⠀⠀⠀⣠⣶⣿⣿⣿⣿⣿⣿⣿⡿⠛⠛⠋⠈⠉⠁⠘⡟⠀⠈⠉⠁⠈⠿⣿⣿⣆⠀⠀⢸⠇⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢸⡄⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⠟⠀⠀⠀⠀⠀⠀⠀⠀⣷⣄⡄⠀⠀⠀⠀⠀⠉⠉⠀⠀⣾⠀⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠈⡇⠀⠀⠀⢸⣿⣿⣿⣿⠏⠉⠁⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣿⣿⡇⠀⠀⠀⠀⠀⠀⠀⠀⠀⢹⡀⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⡇⠀⢀⣶⣿⣿⡿⠋⠁⠀⠀⠀⢰⣿⣷⠀⢠⡀⠀⠀⠀⠀⣿⣿⣷⣄⠀⠀⣀⣀⢀⣶⠀⠀⠈⡇⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢰⣧⣴⣿⣿⣿⣿⣷⡆⠀⠀⠀⠀⠈⠻⣿⣿⠟⠁⠀⠀⠀⢀⣿⣿⣿⣿⣷⡀⠙⠻⠛⠋⠀⠀⠀⡿⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣾⣿⣿⣿⣿⣿⣿⣿⣷⣀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⢀⣾⣿⠻⣿⣿⠿⢷⣄⠀⠀⠀⠀⠀⠠⡇⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡆⠀⠀⠀⠀⠀⠀⠀⣀⣴⣿⣿⣿⣷⣮⠀⣴⣿⣿⣦⣄⠀⠀⠀⢠⡇⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⠀⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣧⠀⠀⠀⣀⣤⣶⣿⣿⣿⣿⣿⠟⢉⣤⣤⣬⡙⢿⣿⣿⣆⠀⣠⣿⣇⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⠀⣴⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠁⠀⠻⢿⣷⣶⣿⣿⣿⣿⣿⣿⣿⠟⣡⣾⣿⣿⣿⣿⣿⣆⣿⣿⢿⣿⣿⣿⣿⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀ ⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣦⣄⣀⣽⠿⠿⠟⢻⣿⣿⣿⣯⣾⣿⣿⣿⣿⣿⣿⣿⣿⡿⢯⢲⠈⢻⣿⡟⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⠀⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣶⣦⣤⣾⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣷⣀⣠⣴⣾⣿⠃⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⠀⣸⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣇⠀⠀⠀⠀⠀",
      " ⠀⠀⠀⠀⠀⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⠀⠀⠀⠀⠀",
      "   █▀▀⣿█▀▄⣿█⣿█⣿█▄█⣿█▀█⣿█⣿█⣿⣿██╗⣿⣿⣿██╗██╗███╗⣿⣿⣿███╗  ",
      "   █⢠█⣿█▀▄⣿█⣿█⣿█⣿█⣿█▀▀⣿⣿█⣿⣿⣿██║⣿⣿⣿██║██║████╗⣿████║  ",
      "   ▀▀▀⣿▀⣿▀⣿▀▀▀⣿▀⣿▀⣿▀⣿⣿⣿⣿▀⣿⣿⣿██║⣿⣿⣿██║██║██╔████╔██║  ",
      "   ⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿╚██╗⣿██╔╝██║██║╚██╔╝██║  ",
      "  ⣼⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿╚████╔╝ ██║██║⣿╚═╝⣿██║  ",
      " ⣰⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿╚═══╝  ╚═╝╚═╝⣿⣿⣿⣿⣿╚═╝  ",
      "⢠⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⣿⡀  ",
    }

    dashboard.section.header.opts = {
      position = "center",
      hl = header_color(),
    }

    local alpha = require("alpha")
    alpha.setup(dashboard.opts)

    -- Disable folding on alpha buffer
    vim.cmd([[autocmd FileType alpha setlocal nofoldenable]])
  end,
}
