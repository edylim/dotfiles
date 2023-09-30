-- leader key
vim.g.mapleader = " "

local km = vim.keymap

-- shortcuts
km.set("n", "<leader>q", ":qa<cr>", { desc = "Quit Vim" })
km.set("i", "jj", "<ESC>", { desc = "Home row <ESC>" })

-- move selection
km.set("v", "J", "<plug>SchleppDown", { desc = "Move highlighted text down" })
km.set("v", "K", "<plug>SchleppUp", { desc = "Move highlighted text down" })
km.set("v", "H", "<plug>SchleppLeft", { desc = "Move highlighted text down" })
km.set("v", "L", "<plug>SchleppRight", { desc = "Move highlighted text down" })

-- windows
km.set("n", "<leader>w|", "<C-w>v", { desc = "Split [w]indow [|]" })
km.set("n", "<leader>w-", "<C-w>s", { desc = "split [w]indow [-]" })
km.set("n", "<leader>we", "<C-w>=", { desc = "[w]indows [e]qual width & height" })
km.set("n", "<leader>wd", ":close<CR>", { desc = "[w]indow [d]elete" })
km.set("n", "<leader>wm", ":MaximizerToggle<CR>", { desc = "[w]indow [m]aximize" })
km.set("n", "<leader>wr", ":SessionRestore<CR>", { desc = "[w]indow [r]estore for cwd" })

-- tabs
km.set("n", "<leader>tn", ":tabnew<CR>", { desc = "[t]ab [n]ew" })
km.set("n", "<leader>td", ":tabclose<CR>", { desc = "[t]ab [d]elete" })
km.set("n", "<leader>tl", ":tabn<CR>", { desc = "Switch [t]ab [l] (right)" })
km.set("n", "<leader>th", ":tabp<CR>", { desc = "Switch [t]ab [h] (left)" })
km.set("n", "<leader>t/", ":BufferLinePick<CR>", { desc = "switch [t]ab [h] (left)" })

-- utility
km.set("n", "<leader>rh", ":nohl<CR>", { desc = "[r]emove [h]ighlights" })
km.set("n", "<leader>so", ":so<CR>", { desc = "Vim [so]urce file" })
km.set("n", "<leader>rl", ":LspRestart<CR>", { desc = "[r]estart [l]sp" })
km.set("n", "<leader>hk", ":Telescope keymaps<CR>", { desc = "[h]elp [k]eymaps" })

-- files
km.set("n", "<leader><tab>", "<C-^>", { desc = "Toggle previous file" })
km.set("n", "<leader>pt", ":NvimTreeFindFileToggle<CR>", { desc = "Toggle [p]roject [t]ree" })
km.set("n", "<leader>ptc", "<cmd>NvimTreeCollapse<CR>", { desc = "[p]roject [t]ree [c]ollapse" })
km.set("n", "<leader>pf", ":Telescope find_files<CR>", { desc = "Find [p]roject [f]ile" })
km.set("n", "<leader>pr", ":Telescope oldfiles<CR>", { desc = "[p]roject [r]ecent file" })
km.set("n", "<leader>pw", ":Telescope grep_string<CR>", { desc = "Find [p]roject [w]ord under cursor" })
km.set("n", "<leader>lb", ":Telescope buffers<CR>", { desc = "[l]ist [b]uffers" })
km.set("n", "<leader>/", ":Telescope live_grep<CR>", { desc = "[/] in project" })
km.set("n", "<leader>ff", ":Telescope file_browser path=%:p:h select_buffer=true<CR>", { desc = "[f]ind [f]ile" })

-- git
km.set("n", "<leader>gs", ":Git status<CR>", { desc = "[g]it [s]tatus" })
km.set("n", "<leader>gpo", ":Git push -u origin ", { desc = "[g]it [p]ush [o]rigin -u" })
km.set("n", "<leader>gp", ":Git push<CR>", { desc = "[g]it [p]ush" })
km.set("n", "<leader>gb", ":Git blame<CR>", { desc = "[g]it [b]lame" })
km.set("n", "<leader>gd", ":Git diff<CR>", { desc = "[g]it [d]iff" })
km.set("n", "<leader>ga", ":Git add -A<CR>", { desc = "[g]it [a]dd all (no confirmation! Use <leader>gg instead)" })
km.set("n", "<leader>gco", ":Git checkout ", { desc = "[g]it [c]heck [o]ut" })
km.set("n", "<leader>gbc", ":Git checkout -b ", { desc = "[g]it [c]heck [o]ut" })
km.set("n", "<leader>gcm", ":Git commit -m ", { desc = "[g]it [c]ommit [m]essage" })
km.set("n", "<leader>gr", ":Git rebase -i origin/main<cr>", { desc = "[g]it [c]heck [o]ut" })
km.set("n", "<leader>gg", ":LazyGit<CR>", { desc = "[g]it [g]it (LazyGit)" })

-- auto-session
km.set("n", "<leader>ws", ":SessionSave<CR>", { desc = "Save session for auto session root dir" })

-- harpoon
km.set("n", "<leader>ha", "<cmd>lua require('harpoon.mark').add_file()<cr>", { desc = "[h]arpoon [a]dd" })
km.set("n", "<leader>hls", "<cmd>lua require('harpoon.ui').toggle_quick_menu()<cr>", { desc = "[h]arpoon [l]i[s]t" })
km.set("n", "<leader>hl", "<cmd>lua require('harpoon.ui').nav_next()<cr>", { desc = "[h]arpoon [l] (right)" })
km.set("n", "<leader>hh", "<cmd>lua require('harpoon.ui').nav_prev()<cr>", { desc = "[h]arpoon [h] (left)" })
