local M = setmetatable(
  {},
  -- inherit from Converter class
  require("portal.classes.Converter")
)
M.__index = M

--- Create a new DaemonConverter object
--
---@param src string
---@param dest string
---@param bufnr integer
---@return portal.DaemonConverter
function M:construct(src, dest, bufnr)
  local cfg = require("portal.config").get_portal_config(src, dest).converter
  local instance = setmetatable({
    src = src,
    dest = dest,
    bufnr = bufnr,
    has_converted = false,
    viewers = {},
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-converter-%s-%s-%s", src, dest, bufnr), {}),
    cfg = cfg,
    status = "idle",

    ---@diagnostic disable-next-line: need-check-nil
    cmd = require("portal.utils").eval_if_func(cfg.cmd),
  }, M)

  return instance
end

--- Start daemon process
--
function M:convert()
  self.status = "converting"
  self.proc = vim.system(require("portal.cmd").interpolate(self.cmd, self.cmd_substitutions), {
    text = true,
    detach = false,
    ---@diagnostic disable-next-line: assign-type-mismatch
    stdin = self.cfg.stdin and vim.api.nvim_buf_get_lines(0, 0, -1, false) or false,
    stdout = vim.schedule_wrap(function(_, stdout_str)
      if stdout_str then
        if
          self.cfg.failure_condition.stdout_contains
          and string.match(stdout_str, self.cfg.failure_condition.stdout_contains)
        then
          self:handle_failed_conversion()
        elseif
          self.cfg.success_condition.stdout_contains
          and string.match(stdout_str, self.cfg.success_condition.stdout_contains)
        then
          self:handle_successful_conversion()
        end
      end
    end),
    stderr = vim.schedule_wrap(function(_, stderr_str)
      if stderr_str then
        if
          self.cfg.failure_condition.stderr_contains
          and string.match(stderr_str, self.cfg.failure_condition.stderr_contains)
        then
          self:handle_failed_conversion()
        elseif
          self.cfg.success_condition.stderr_contains
          and string.match(stderr_str, self.cfg.success_condition.stderr_contains)
        then
          self:handle_successful_conversion()
        end
      end
    end),
  }, vim.schedule_wrap(function(obj) end))
end

--- Handle a conversion which succeeded to produce an output
--
function M:handle_successful_conversion()
  self.status = "succeeded"
  self.has_converted = true
  self:update_viewers()
end

--- Handle a conversion which failed to produce an output
--
function M:handle_failed_conversion()
  self.status = "failed"
end

return M
