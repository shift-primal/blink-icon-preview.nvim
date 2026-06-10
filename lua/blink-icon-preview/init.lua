---blink-icon-preview.nvim
---
---Renders inline images in the blink.cmp documentation window using
---snacks.nvim's image support. Built for icon-library completions (e.g.
---@phosphor-icons/react) whose LSP docs embed icons as base64 SVG data URLs,
---but works for any data-URL image in completion docs.
local M = {}

---@class blink-icon-preview.Config
local defaults = {
	---filetype blink.cmp assigns to its documentation buffer
	filetype = "blink-cmp-documentation",
	---window-local options applied when the docs contain inline images.
	---wrap=false keeps each concealed data URL on a single screen line, so the
	---image renders directly below its label instead of after dozens of
	---wrapped rows of base64 text
	wo = { wrap = false, conceallevel = 2 },
	---only buffers containing this string (plain-text match) get the `wo`
	---overrides, so regular documentation keeps blink's own window settings
	image_pattern = "data:image/",
	---assume the Kitty graphics protocol when $KITTY_WINDOW_ID is set, instead
	---of relying on snacks' async terminal detection, which can time out and
	---permanently disable inline rendering for the session
	kitty_override = true,
}

---@type blink-icon-preview.Config
M.config = vim.deepcopy(defaults)

local did_setup = false

---@param opts? blink-icon-preview.Config
function M.setup(opts)
	if did_setup then
		return
	end
	did_setup = true
	M.config = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})

	if M.config.kitty_override and vim.env.KITTY_WINDOW_ID and not vim.env.SNACKS_KITTY then
		vim.env.SNACKS_KITTY = "1"
	end

	-- the docs buffer has no treesitter language of its own; snacks finds
	-- images by running its markdown `images.scm` query, so it needs this
	-- filetype to resolve to the markdown parser
	vim.treesitter.language.register("markdown", M.config.filetype)

	local group = vim.api.nvim_create_augroup("blink-icon-preview", { clear = true })

	-- blink re-assigns the filetype on every window open, so this fires for
	-- every docs popup, not just the first one
	vim.api.nvim_create_autocmd("FileType", {
		group = group,
		pattern = M.config.filetype,
		callback = function(ev)
			M.attach(ev.buf)
		end,
	})

	-- warm up snacks' terminal detection (1s timeout on first use) so the
	-- first docs popup doesn't have to wait for it
	vim.api.nvim_create_autocmd("User", {
		group = group,
		pattern = "VeryLazy",
		once = true,
		callback = function()
			pcall(function()
				require("snacks.image.terminal").detect(function() end)
			end)
		end,
	})
end

---@param buf number
function M.attach(buf)
	local ok = pcall(require, "snacks.image.doc")
	if not ok then
		return
	end
	require("blink-icon-preview.patches").apply()

	-- hide the (very long) `![img](data:...)` markdown text behind the image
	vim.b[buf].snacks_image_conceal = true
	pcall(vim.treesitter.get_parser, buf, "markdown")
	require("snacks.image.doc").attach(buf)

	-- blink applies its own window options after setting the filetype, so
	-- defer ours until it is done configuring the window
	vim.schedule(function()
		if not (vim.api.nvim_buf_is_valid(buf) and M.has_images(buf)) then
			return
		end
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			for k, v in pairs(M.config.wo) do
				vim.api.nvim_set_option_value(k, v, { win = win })
			end
		end
	end)
end

---@param buf number
function M.has_images(buf)
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		if line:find(M.config.image_pattern, 1, true) then
			return true
		end
	end
	return false
end

return M
