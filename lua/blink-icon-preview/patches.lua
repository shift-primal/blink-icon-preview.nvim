---Runtime patches for snacks.nvim's image doc module, applied once on the
---first blink docs buffer. They fix data-URL SVG rendering without editing
---snacks' installed files, so they survive `:Lazy update`. Each patch can be
---dropped once the corresponding fix lands upstream.
local M = {}

local applied = false

---Fixed replacement for snacks' `data_img` transform. Differences from
---upstream (snacks/image/doc.lua):
---
---  * ext: upstream `ft:match("^image/(%w+)$")` fails on `image/svg+xml`
---    (the `+` is not a word char) and falls back to "png", so the SVG text
---    was cached as a .png file and rasterized blurry. Match up to the `+`
---    instead.
---  * cache key: upstream sets `content_id = data:sub(1, 20)`, but every SVG
---    from the same icon library shares its first 20 base64 chars (same
---    `<svg xmlns=...` header), so all icons resolved to one cache file and
---    showed the same image. Omitting content_id makes snacks fall back to
---    sha256(content), one file per icon.
---  * size: icon SVGs often declare a small explicit width/height (e.g.
---    20x20) next to a large viewBox (e.g. 256); ImageMagick rasterizes at
---    the explicit size and then upscales, producing pixelated output.
---    Stripping width/height makes it render at the viewBox size.
---
---@param img snacks.image.match
---@param ctx snacks.image.ctx
local function data_img(img, ctx)
	if not (vim.base64 and img.src) then
		return
	end
	local ft, data = img.src:match("^data:(.-);base64,(.+)$")
	if not (ft and data) then
		return
	end
	img.content = vim.base64.decode(data)
	img.src = nil
	img.ext = ft:match("^image/([%w%-]+)") or "png"
	if img.ext == "svg" then
		img.content = img.content:gsub(' width="[^"]*"', ""):gsub(' height="[^"]*"', "")
	end
end

function M.apply()
	if applied then
		return
	end
	applied = true

	local doc = require("snacks.image.doc")
	local config = require("blink-icon-preview").config

	doc.transforms.data_img = data_img

	-- snacks only dispatches `data_img` when the src matches
	-- `^data:%w+/%w+;base64,`, which never matches `image/svg+xml` (`%w` does
	-- not include `+`). Markdown image nodes belong to the markdown_inline
	-- language and snacks registers no transform for it, so this shim catches
	-- the data URLs the built-in pattern misses.
	if not doc.transforms.markdown_inline then
		doc.transforms.markdown_inline = function(img, ctx)
			if img.src and img.src:find("^data:[^;]+;base64,") then
				data_img(img, ctx)
			end
		end
	end

	-- `doc.find` forwards row numbers as the start/stop arguments of
	-- `Query:iter_matches`, which nvim 0.12 treats as byte offsets — so the
	-- ranged search used by inline rendering finds none of the images in the
	-- docs buffer. The buffer is tiny; drop the range and scan all of it.
	local find = doc.find
	---@param buf number
	---@param cb snacks.image.find
	---@param opts? {from?: number, to?: number}
	doc.find = function(buf, cb, opts)
		if vim.bo[buf].filetype == config.filetype then
			opts = nil
		end
		return find(buf, cb, opts)
	end
end

return M
