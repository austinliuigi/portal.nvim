local M = {}
M.__index = M

--- Whether or not the viewer process is open
--
---@return boolean
function M:is_open()
  return self.proc ~= nil
end

--- Create and open viewer process
--
function M:open()
  if self:is_open() then
    return
  end

  local interpolated_cmd = require("portal.cmd").interpolate(self.open_cmd, self.cmd_substitutions)

  self.proc = vim.system(
    interpolated_cmd,
    { text = true, detach = true },
    vim.schedule_wrap(function(obj)
      if obj.code ~= 0 then
        vim.notify(
          string.format("Failed to open viewer, exited with code %s\n[stderr]:\n%s", obj.code, obj.stderr),
          vim.log.levels.ERROR,
          { title = "portal.nvim" }
        )
      end
      if not self.cfg.detach and require("portal").is_open(self.src, self.dest, self.bufnr) then
        require("portal").close(self.src, self.dest, self.bufnr)
      end
    end)
  )
end

--- Ensure updated content is shown in viewer
--
function M:update()
  -- switch target (for global viewers)
  if self.is_target_outdated then
    vim.system(
      require("portal.cmd").interpolate(self.switch_cmd, self.cmd_substitutions),
      { text = true, detach = true },
      vim.schedule_wrap(function(obj) end)
    )
    self.is_target_outdated = false
  -- refresh target
  elseif self.refresh_cmd then
    vim.system(
      require("portal.cmd").interpolate(self.refresh_cmd, self.cmd_substitutions),
      { text = true, detach = true },
      vim.schedule_wrap(function(obj) end)
    )
  end
end

--- Open the viewer if it isn't, otherwise refresh
--
function M:open_or_update()
  if not self:is_open() then
    self:open()
  else
    self:update()
  end
end

return M
