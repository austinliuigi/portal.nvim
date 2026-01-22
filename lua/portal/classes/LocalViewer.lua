local M = setmetatable(
  {
    ---@type { [integer]: { [string]: { [string]: portal.LocalViewer } } }
    instances = {},
  },
  -- inherit from Viewer class
  require("portal.classes.Viewer")
)
M.__index = M

--- Create a new LocalViewer object
--
---@param src string
---@param dest string
---@param bufnr integer
---@return portal.LocalViewer
function M:construct(src, dest, bufnr)
  -- return existing instance if one exists with the same target
  local instance = require("portal.utils").tbl_get(M.instances, { bufnr, src, dest })
  if instance then
    return instance
  end

  instance = setmetatable({
    src = src,
    dest = dest,
    bufnr = bufnr,
    id = vim.fn.getpid() .. src .. dest .. bufnr,
    converter = require("portal.classes.Converter"):construct(src, dest, bufnr),
    cfg = require("portal.config").get_portal_config(src, dest).viewer,
  }, M)

  instance.cmd_substitutions = {
    ["$TEMPDIR"] = require("portal").tempdir,
    ["$INFILE"] = vim.api.nvim_buf_get_name(instance.converter.bufnr),
    ["$OUTFILE"] = require("portal").get_outfile(src, dest, instance.converter.bufnr),
    ["$ID"] = string.format("portal-%s-%s-%s", vim.fn.getpid(), src, dest),
    ["$PID"] = function()
      return self.proc and self.proc.pid or ""
    end,
  }

  instance.converter:attach_viewer(instance)

  require("portal.utils").tbl_set(M.instances, { bufnr, src, dest }, instance)
  return instance
end

--- Destroy LocalViewer object
--
function M:destruct()
  M.instances[self.bufnr][self.src][self.dest] = nil
  require("portal.utils").tbl_prune(M.instances, 2)

  self.converter:detach_viewer(self)

  if self:is_open() then -- portals that never converted successfully have not opened
    if not self.cfg.detach and not self.proc:is_closing() then
      self.proc:kill(15)
    end
  end
end

return M
