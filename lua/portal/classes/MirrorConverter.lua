local M = setmetatable(
  {},
  -- inherit from Converter class
  require("portal.classes.Converter")
)
M.__index = M

--- Create a new MirrorConverter object
--
---@param src string
---@param dest string
---@param bufnr integer
---@return portal.DaemonConverter
function M:construct(src, dest, bufnr)
  local instance = setmetatable({
    src = src,
    dest = dest,
    bufnr = bufnr,
    has_converted = false,
    viewers = {},
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-converter-%s-%s-%s", src, dest, bufnr), {}),
    status = "idle",
  }, M)

  -- reconvert when source content changes
  vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
    group = instance.augroup_id,
    buffer = bufnr,
    callback = function()
      instance:convert()
    end,
  })

  return instance
end

--- Generate outfile
--
function M:convert()
  self.status = "succeeded"
  self.has_converted = true
  self:update_viewers()
end

return M
