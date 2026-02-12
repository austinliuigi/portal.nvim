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
    log_buf = require("portal.utils").create_log_buf(),

    ---@diagnostic disable-next-line: need-check-nil
    cmd = require("portal.utils").eval_if_func(cfg.cmd),
  }, M)

  return instance
end

--- Start daemon process
--
function M:convert()
  self.status = "converting"
  local cmd = require("portal.cmd")
  local command, is_command_wrapped = cmd.wrap(cmd.interpolate(self.cmd, self.cmd_substitutions))
  self.proc = vim.system(command, {
    text = true,
    detach = false,
    ---@diagnostic disable-next-line: assign-type-mismatch
    stdin = self.cfg.stdin and vim.api.nvim_buf_get_lines(0, 0, -1, false) or false,
    stdout = vim.schedule_wrap(function(_, stdout_str)
      if stdout_str then
        -- append output to log
        vim.api.nvim_chan_send(self.log_buf.chan, stdout_str)

        self:handle_output_conditions()
        -- if command is wrapped, stdout and stderr are merged due to how `script` operates
        if is_command_wrapped then
          self:handle_output_conditions(true)
        end
      end
    end),
    stderr = vim.schedule_wrap(function(_, stderr_str)
      if stderr_str then
        -- append output to log
        vim.api.nvim_chan_send(self.log_buf.chan, stderr_str)

        -- a wrapped command's stderr will be that of the `script` process, not the process that script invokes
        -- therefore, we only check the stderr if we run the command directly (non-wrapped)
        if not is_command_wrapped then
          self:handle_output_conditions(true)
        end
      end
    end),
  }, vim.schedule_wrap(function(obj) end))
end

local UNMATCHABLE = "$^"
--- Callback to handle output from converter process
--
---@param stderr boolean?
function M:handle_output_conditions(stderr)
  local failure_pat = stderr and self.cfg.failure_condition.stderr_contains
    or self.cfg.failure_condition.stdout_contains
  failure_pat = failure_pat or UNMATCHABLE

  local success_pat = stderr and self.cfg.success_condition.stderr_contains
    or self.cfg.success_condition.stdout_contains
  success_pat = success_pat or UNMATCHABLE

  -- HACK: the terminal buffer updates async after sending data to the channel, so buffer contents won't be available immediately
  vim.defer_fn(function()
    -- handle failure/success conditions
    local log_lines = table.concat(vim.api.nvim_buf_get_lines(self.log_buf.bufnr, 0, -1, true), "\n")
    if string.match(log_lines, failure_pat) then
      self:handle_failed_conversion()
    elseif string.match(log_lines, success_pat) then
      self:handle_successful_conversion()
    end
  end, 500)
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
