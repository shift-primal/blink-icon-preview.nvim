# blink-icon-preview.nvim

Inline image previews in the [blink.cmp](https://github.com/saghen/blink.cmp)
documentation window, rendered by
[snacks.nvim](https://github.com/folke/snacks.nvim)'s image module.

Built for icon-library completions — e.g. `@phosphor-icons/react`, whose LSP
hover/completion docs embed every icon as a base64 SVG data URL
(`![img](data:image/svg+xml;base64,...)`). Out of the box those show up as
plain `@regular — img` text; with this plugin you see the actual icon.

## Requirements

- Neovim 0.10+ (`vim.base64`); developed on 0.12
- snacks.nvim with `image.enabled = true` and `image.doc.inline = true`
- A terminal supporting the Kitty graphics protocol (Kitty, Ghostty, WezTerm)
- ImageMagick (`magick`) for SVG rasterization
- treesitter parsers for `markdown` and `markdown_inline`

## Install (lazy.nvim)

```lua
{
  "shift-primal/blink-icon-preview.nvim",
  dependencies = { "folke/snacks.nvim" },
  -- setup() should run before snacks' first terminal detection;
  -- lazy-loading on InsertEnter is fine, `init` is safest:
  init = function()
    require("blink-icon-preview").setup()
  end,
}
```

Recommended snacks.nvim opts, so big-viewBox icons rasterize sharp but capped:

```lua
opts = {
  image = {
    convert = {
      magick = {
        vector = { "-density", "192", "-background", "none", "{src}[{page}]", "-resize", "256x256" },
      },
    },
  },
}
```

## Configuration (defaults)

```lua
require("blink-icon-preview").setup({
  filetype = "blink-cmp-documentation",
  -- window options forced on docs popups that contain images
  wo = { wrap = false, conceallevel = 2 },
  -- plain-text marker that decides whether a popup "contains images"
  image_pattern = "data:image/",
  -- set SNACKS_KITTY=1 inside Kitty to skip snacks' async terminal detection
  kitty_override = true,
})
```

## How it works

The docs buffer is registered as a `markdown` treesitter language so snacks'
`images.scm` query can find image nodes in it, and snacks' doc renderer is
attached on every popup (blink re-assigns the filetype each time the window
opens, so the `FileType` autocmd fires per popup). The long
`![img](data:...)` line is concealed and `wrap` is disabled so the icon
renders directly under its label.

`patches.lua` additionally hot-patches four bugs in `snacks.image.doc` at
runtime (no files in the snacks installation are modified, so `:Lazy update`
is safe). Each is a candidate upstream fix:

1. **MIME dispatch** — `^data:%w+/%w+;base64,` never matches
   `image/svg+xml` (`%w` excludes `+`), so the `data_img` transform was
   skipped and the raw data URL was treated as a file path.
2. **Extension** — `ft:match("^image/(%w+)$")` also fails on `svg+xml`,
   falling back to `png`, so SVG content was cached as `.png` and rasterized
   without the vector pipeline.
3. **Cache key** — `content_id = data:sub(1, 20)` is identical for every SVG
   sharing a header, so all icons displayed the first icon's cached image.
4. **Ranged find** — `doc.find` passes row numbers where
   `Query:iter_matches` expects byte offsets (Neovim 0.12), so the ranged
   search used by inline rendering found no images. The patch scans the whole
   (tiny) docs buffer instead.

It also strips explicit `width`/`height` attributes from SVGs so ImageMagick
rasterizes at the viewBox size (Phosphor icons declare 20x20 with a 256
viewBox — rendering 20px and upscaling looks pixelated), and warms up snacks'
terminal detection at startup so the first popup is not delayed by it.
