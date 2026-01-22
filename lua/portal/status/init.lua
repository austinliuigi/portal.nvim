local M = {
  status_wins = {},
}

local get_spinner_frame = require("portal.status.spinner").animate()

--- Get the icon and highlight corresponding to a given status
--
---@param status portal.Status
---@return portal.StatusChunk
local function get_icon_chunk(status)
  if status == "failed" then
    return { "⨯", "DiagnosticError" }
  elseif status == "succeeded" then
    return { "✓", "DiagnosticInfo" }
  elseif status == "converting" then
    return { get_spinner_frame(vim.fn.reltimefloat(vim.fn.reltime())), "DiagnosticWarn" }
  end
end

--- Get a list of currently visible non-floating windows
--
---@return integer[]
local function get_visible_wins()
  return vim
    .iter(vim.api.nvim_tabpage_list_wins(0))
    :filter(function(winnr)
      return vim.api.nvim_win_get_config(winnr).zindex == nil
    end)
    :totable()
end

--- Get lines to be rendered for each visible window
--
function M.update()
  -- get active converters for each visible window
  local winnr_to_converters = {}
  for _, winnr in ipairs(get_visible_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winnr)
    for src, dest_tbl in pairs(require("portal.classes.Converter").instances[bufnr] or {}) do
      for dest, converter in pairs(dest_tbl) do
        winnr_to_converters[winnr] = winnr_to_converters[winnr] or {}
        table.insert(winnr_to_converters[winnr], converter)
      end
    end
  end

  -- remove status windows which aren't active anymore
  M.prune(vim.tbl_keys(winnr_to_converters))

  -- get lines to be rendered for each window with active converters
  for winnr, converters in pairs(winnr_to_converters) do
    local lines = {}
    for _, converter in ipairs(converters) do
      table.insert(lines, {
        { string.format("%s --> %s ", converter.src, converter.dest), "Comment" },
        get_icon_chunk(converter.status),
      })
    end

    -- sort lines to ensure they are in the same order every render
    require("portal.status.lines").sort(lines)

    -- create/update status windows
    M.status_wins[winnr] = M.status_wins[winnr] or require("portal.status.classes.StatusWindow"):construct(winnr)
    M.status_wins[winnr]:set_lines(lines)
  end
end

--- Remove any stale status windows, i.e. those whose parent windows no longer exist or have open portals
--
---@param active_wins integer[]
function M.prune(active_wins)
  local active_wins_map = {}
  for _, winnr in ipairs(active_wins) do
    active_wins_map[winnr] = true
  end

  for winnr, status_win in pairs(M.status_wins) do
    if not active_wins_map[winnr] then
      status_win:destruct()
      M.status_wins[winnr] = nil
    end
  end
end

--- Enable status messages
--
function M.enable()
  if not M.timer then
    M.timer = vim.uv.new_timer()
    M.timer:start(
      0,
      150,
      vim.schedule_wrap(function()
        M.update()
      end)
    )

    M.augroup_id = vim.api.nvim_create_augroup("portal-status", {})
    vim.api.nvim_create_autocmd({ "VimLeavePre" }, {
      group = M.augroup_id,
      callback = function()
        require("portal.status").disable()
      end,
      once = true,
    })
  end
end

--- Disable status messages
--
function M.disable()
  if M.timer then
    M.timer:stop()
    M.timer:close()

    -- close all status wins
    for winnr, status_win in pairs(M.status_wins) do
      status_win:destruct()
      M.status_wins[winnr] = nil
    end

    vim.api.nvim_del_augroup_by_id(M.augroup_id)
  end
end

return M
