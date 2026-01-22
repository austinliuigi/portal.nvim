local M = {}
M.__index = M

--- Create a StatusWindow object
--
---@param parent_winnr integer The window that this status win should be anchored to
---@return portal.StatusWindow
function M:construct(parent_winnr)
  local instance = setmetatable({
    parent_winnr = parent_winnr,
    bufnr = vim.api.nvim_create_buf(false, true),
    namespace_id = vim.api.nvim_create_namespace(""),
    lines = {},
  }, M)

  return instance
end

--- Destroy a StatusWindow object
--
function M:destruct()
  if self.winnr then
    vim.api.nvim_win_close(self.winnr, true)
  end
  if self.bufnr then
    vim.api.nvim_buf_clear_namespace(self.bufnr, self.namespace_id, 0, -1)
    vim.api.nvim_buf_delete(self.bufnr, { force = true })
  end
end

--- Open or reposition the status window
--
function M:show()
  local width, height = require("portal.status.lines").get_dims(self.lines)
  local row = 0
  local col = vim.api.nvim_win_get_width(self.parent_winnr)

  if self.winnr == nil or not vim.api.nvim_win_is_valid(self.winnr) then
    -- create status window
    self.winnr = vim.api.nvim_open_win(self.bufnr, false, {
      relative = "win",
      win = self.parent_winnr,
      width = width,
      height = height,
      row = row,
      col = col,
      anchor = "NE",
      focusable = false,
      noautocmd = true,
      style = "minimal",
    })
    vim.wo[self.winnr].winblend = 100
  else
    -- reposition status window
    vim.api.nvim_win_set_config(self.winnr, {
      relative = "win",
      win = self.parent_winnr,
      width = width,
      height = height,
      row = row,
      col = col,
    })
  end
end

--- Set the lines that the status window should display
--
---@param lines portal.StatusLine[]
function M:set_lines(lines)
  self.lines = lines

  -- clear previous extmarks
  vim.api.nvim_buf_clear_namespace(self.bufnr, self.namespace_id, 0, -1)

  -- set empty lines for extmarks
  local empty_lines = vim.tbl_map(function()
    return ""
  end, lines)
  vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, empty_lines)

  for iline, line in ipairs(lines) do
    if vim.fn.has("nvim-0.11.0") == 1 then
      vim.api.nvim_buf_set_extmark(self.bufnr, self.namespace_id, iline - 1, 0, {
        virt_text = line,
        virt_text_pos = "eol_right_align",
      })
    else
      -- pre-0.11.0: eol_right_align was only introduced in 0.11.0;
      -- without it we need to compute and add the padding ourselves
      local width, _ = require("portal.status.lines").get_dims(lines)
      local len, padded = 0, { {} }
      for _, chunk in ipairs(line) do
        len = len + vim.fn.strwidth(chunk[1]) + vim.fn.count(chunk[1], "\t") * math.max(0, M.options.tabstop - 1)
        table.insert(padded, chunk)
      end
      local pad_width = math.max(0, width - len)
      if pad_width > 0 then
        padded[1] = { string.rep(" ", pad_width), {} }
      else
        padded = line
      end
      vim.api.nvim_buf_set_extmark(self.bufnr, self.namespace_id, iline - 1, 0, {
        virt_text = padded,
        virt_text_pos = "eol",
      })
    end
  end

  self:show()
end

return M
