local M = setmetatable(
  {
    ---@type { [string]: { [string]: portal.GlobalViewer } }
    instances = {},
  },
  -- inherit from Viewer class
  require("portal.classes.Viewer")
)
M.__index = M

--- Create a new GlobalViewer object
--
---@param src string
---@param dest string
---@return portal.GlobalViewer
function M:construct(src, dest)
  -- return existing instance if one exists with the same target
  local instance = require("portal.utils").tbl_get(M.instances, { src, dest })
  if instance then
    return instance
  end

  instance = setmetatable({
    src = src,
    dest = dest,
    is_target_outdated = false,
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-globalviewer-%s-%s", src, dest), {}),
    cfg = require("portal.config").get_portal_config(src, dest).viewer,
  }, M)

  instance.cmd_substitutions = {
    ["$TEMPDIR"] = require("portal").tempdir,
    ["$INFILE"] = function()
      return vim.api.nvim_buf_get_name(instance.converter.bufnr)
    end,
    ["$OUTFILE"] = function()
      return require("portal").get_outfile(src, dest, instance.converter.bufnr)
    end,
    ["$ID"] = string.format("portal-%s-%s-%s", vim.fn.getpid(), src, dest),
    ["$PID"] = function()
      return self.proc and self.proc.pid or ""
    end,
  }

  -- switch source when matching buffer is focused
  vim.api.nvim_create_autocmd("BufEnter", {
    group = instance.augroup_id,
    callback = function()
      if vim.o.filetype == src then
        instance:switch()
      end
    end,
  })

  -- trigger global portal immediately if already in matching source file
  if vim.o.filetype == src then
    instance:switch()
  end

  require("portal.utils").tbl_set(M.instances, { src, dest }, instance)
  return instance
end

--- Destroy GlobalViewer object
--
function M:destruct()
  M.instances[self.src][self.dest] = nil
  require("portal.utils").tbl_prune(M.instances, 1)

  if self.converter ~= nil then
    self.converter:detach_viewer(self)
  end

  vim.api.nvim_del_augroup_by_id(self.augroup_id)

  if self:is_open() then -- portals that never converted successfully have not opened
    if not self.cfg.detach and not self.proc:is_closing() then
      self.proc:kill(15)
    end
  end
end

--- Switch buffer that global viewer is attached to
--
---@param bufnr? integer
function M:switch(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  -- switching to same buffer; early exit
  if self.converter ~= nil and self.converter.bufnr == bufnr then
    return
  end

  -- remove old converter
  if self.converter ~= nil then
    self.converter:detach_viewer(self)
  end

  if self:is_open() then
    self.is_target_outdated = true
  end

  -- store new converter
  self.converter = require("portal.classes.Converter"):construct(self.src, self.dest, bufnr)
  self.converter:attach_viewer(self)
end

return M
