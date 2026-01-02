local settings = require("settings")
local colors = require("colors")

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

local cal = sbar.add("item", {
	icon = {
		color = colors.white,
		padding_left = 8,
		font = {
			style = settings.font.style_map["Black"],
			size = 12.0,
		},
	},
	label = {
		color = colors.white,
		padding_right = 8,
		-- width = 49,
		align = "right",
		font = { family = settings.font.numbers },
	},
	position = "right",
	update_freq = 30,
	padding_left = 1,
	padding_right = 1,
	background = {
		color = colors.bg2,
		border_color = colors.white,
		border_width = 1,
	},
	click_script = "open -a 'Google Chrome' 'https://calendar.google.com",
})

-- Double border for calendar using a single item bracket
sbar.add("bracket", { cal.name }, {
	background = {
		color = colors.transparent,
		height = 30,
		border_color = colors.transparent,
	},
})

-- Padding item required because of bracket
sbar.add("item", { position = "right", width = settings.group_paddings })

print(time_string)
cal:subscribe({ "forced", "routine", "system_woke" }, function(env)
	local hour = tonumber(os.date("%I"))
	local minute = os.date("%M")
	local ampm = os.date("%p")

	local time_string = string.format("%d:%s %s", hour, minute, ampm)

	cal:set({ icon = os.date("%A, %B %d - "), label = time_string })
end)
