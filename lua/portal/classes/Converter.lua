local M = {
  ---@type { [integer]: { [string]: { [string]: portal.Converter } } }
  instances = {},
}
M.__index = M

--- Create a new Converter object. This is a factory to create specific converter types.
--
---@param src string
---@param dest string
---@param bufnr integer
---@return portal.Converter?
function M:construct(src, dest, bufnr)
  -- return existing instance if one exists with the same target
  local instance = require("portal.utils").tbl_get(M.instances, { bufnr, src, dest })
  if instance then
    return instance
  end

  local cfg = require("portal.config").get_portal_config(src, dest).converter
  if cfg == nil then
    instance = require("portal.classes.MirrorConverter"):construct(src, dest, bufnr)
  elseif cfg.daemon then
    instance = require("portal.classes.DaemonConverter"):construct(src, dest, bufnr)
  else
    instance = require("portal.classes.OneShotConverter"):construct(src, dest, bufnr)
  end

  instance.cmd_substitutions = {
    ["$TEMPDIR"] = require("portal").tempdir,
    ["$INFILE"] = vim.api.nvim_buf_get_name(bufnr),
    ["$OUTFILE"] = require("portal").get_outfile(src, dest, bufnr),
    ["$ID"] = string.format("portal-%s-%s-%s", vim.fn.getpid(), src, dest),
  }

  -- perform initial conversion
  instance:convert()

  require("portal.utils").tbl_set(M.instances, { bufnr, src, dest }, instance)
  return instance
end

-- Destroy Converter object
--
function M:destruct()
  vim.api.nvim_del_augroup_by_id(self.augroup_id)

  if self.proc then -- portals with no converter or have only hit the cache have no converter_proc
    if not self.proc:is_closing() then
      self.proc:kill(15)
    end
  end

  M.instances[self.bufnr][self.src][self.dest] = nil
  require("portal.utils").tbl_prune(M.instances, 2)
end

--- Whether the converter has any viewers attached to it
--
---@return boolean
function M:is_headless()
  return #self.viewers == 0
end

--- Add an attached viewer
--
---@param viewer portal.LocalViewer|portal.GlobalViewer
function M:attach_viewer(viewer)
  for _, v in ipairs(self.viewers) do
    if v == viewer then
      return
    end
  end

  table.insert(self.viewers, viewer)
  if self.has_converted then
    viewer:open_or_update()
  end
end

--- Remove an attached viewer
--
---@param viewer portal.LocalViewer|portal.GlobalViewer
---@param keepalive? boolean Whether to keep converter alive if it's headless after detaching viewer
function M:detach_viewer(viewer, keepalive)
  for i, v in ipairs(self.viewers) do
    if v == viewer then
      table.remove(self.viewers, i)
      break
    end
  end

  if not keepalive and self:is_headless() then
    self:destruct()
  end
end

--- Update attached viewers
--
function M:update_viewers()
  for _, viewer in ipairs(self.viewers) do
    viewer:open_or_update()
  end
end

return M
