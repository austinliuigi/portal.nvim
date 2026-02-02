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
    self.proc = vim.system(
      require("portal.cmd").interpolate(self.cmd, self.cmd_substitutions),
      {
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
              self:handle_successful_conversion(cache_outfile)
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
              self:handle_successful_conversion(cache_outfile)
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
