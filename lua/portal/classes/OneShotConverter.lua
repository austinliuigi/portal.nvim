local M = setmetatable(
  {},
  -- inherit from Converter clas
  require("portal.classes.Converter")
)
M.__index = M

--- Create a new OneShotConverter object
--
---@param src string
---@param dest string
---@param bufnr integer
---@return portal.OneShotConverter?
function M:construct(src, dest, bufnr)
  local cfg = require("portal.config").get_portal_config(src, dest).converter
  local instance = setmetatable({
    src = src,
    dest = dest,
    bufnr = bufnr,
    has_converted = false,
    busy = false,
    queued = false,
    viewers = {},
    augroup_id = vim.api.nvim_create_augroup(string.format("portal-converter-%s-%s-%s", src, dest, bufnr), {}),
    cfg = cfg,
    status = "idle",
    log_buf = require("portal.utils").create_log_buf(),

    ---@diagnostic disable-next-line: need-check-nil
    cmd = require("portal.utils").eval_if_func(cfg.cmd),
  }, M)

  -- reconvert when source content changes
  vim.api.nvim_create_autocmd(instance.cfg.stdin and { "TextChanged", "TextChangedI" } or "BufWritePost", {
    group = instance.augroup_id,
    buffer = bufnr,
    callback = function()
      if instance.busy then
        instance.queued = true
      else
        instance:convert()
      end
    end,
  })

  return instance
end

--- Convert an unnested list to a string
--
---@param list any[]
local function list_to_str(list)
  local str_tbl = {}
  for _, item in ipairs(list) do
    table.insert(str_tbl, tostring(item))
  end
  return table.concat(str_tbl, ",")
end

--- Perform conversion to generate corresponding output file from current input file
--
function M:convert()
  self.status = "converting"
  self.busy = true

  -- clear output log
  vim.api.nvim_chan_send(self.log_buf.chan, "\x1b[2J\x1b[H")

  -- NOTE: We hash the cmd of the converter because some input types can contain contents corresponding to
  --       multiple outputs of the same dest in a single file, e.g. a manim file can have multiple scenes
  --       in a file, which can all be of type gif.
  --       Thus, to avoid false cache hits when changing outputs (e.g. scenes) but keeping the buffer content unchanged,
  --       we use the cmd of the converter to distinguish them, as that is what determines the chosen output.
  -- NOTE: This only works when the cmd doesn't contain any functions, as converting a function to a string
  --       is not deterministic since it uses its memory address in the current neovim instance. A cmd containing
  --       any functions, it will most likely cache miss and generate an identical entry when run from a different
  --       neovim instance.
  local cache_outfile =
    require("portal.cache").get_cache_outfile(self.src, self.dest, self.bufnr, list_to_str(self.cmd))

  -- handle cache hit ---------------------------
  if vim.uv.fs_stat(cache_outfile) then
    -- update mtime of cache file
    vim.uv.fs_utime(cache_outfile, nil, "now")

    -- copy to outfile instead of linking because a future generation will alter the outfile, which shouldn't alter the cache file
    vim.uv.fs_copyfile(cache_outfile, require("portal").get_outfile(self.src, self.dest, self.bufnr))

    self.busy = false
    self.has_converted = true
    self.status = "succeeded"
    self:update_viewers()

    if self.queued then
      self.queued = false
      self:convert()
    end

  -- handle cache miss ---------------------------
  else
    local cmd = require("portal.cmd")
    local command, is_command_wrapped = cmd.wrap(cmd.interpolate(self.cmd, self.cmd_substitutions))
    self.proc = vim.system(
      command,
      {
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
      },
      vim.schedule_wrap(function(obj)
        self.busy = false

        if self.cfg.success_condition.exit_code then
          if obj.code == self.cfg.success_condition.exit_code then
            self:handle_successful_conversion(cache_outfile)
          else
            self:handle_failed_conversion()
          end
        end

        if self.queued then
          self.queued = false
          self:convert()
        end
      end)
    )
  end
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
function M:handle_successful_conversion(cache_outfile)
  -- cache the output
  vim.uv.fs_copyfile(require("portal").get_outfile(self.src, self.dest, self.bufnr), cache_outfile)

  self.has_converted = true
  self:update_viewers()

  self.status = "succeeded"
end

--- Handle a conversion which failed to produce an output
--
function M:handle_failed_conversion()
  self.status = "failed"
end

return M
