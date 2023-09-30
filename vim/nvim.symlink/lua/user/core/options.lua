local o = vim.opt

o.termguicolors = true -- iTerm2 capable colors
o.background = "dark" -- always dark

o.shiftwidth = 2 -- 2 space indent
o.autoindent = true -- indent based on current line
o.tabstop = 2 -- 2 space tabs
o.expandtab = true -- convert tab to spaces

o.relativenumber = true -- relative line numbers
o.number = true -- abs line number on cursor line
o.cursorline = true -- highlight current line
o.wrap = false -- don't wrap you n00b
o.signcolumn = "yes:1" -- add left column size 1 so it doesn't shift
o.backspace = "eol,start,indent" -- make backspace behave as expected

-- o.iskeyword:append("_") -- make _ part of word
-- o.iskeyword:append("-") -- make - part of word

o.ignorecase = true -- ignore case
o.smartcase = true -- respect case if mixed with UPPER

o.splitright = true -- split to right
o.splitbelow = true -- split to bottom

o.clipboard:append("unnamedplus") -- system clipboard integration

o.swapfile = false
