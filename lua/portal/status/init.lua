local M = {
  -- parent winid to StatusWindow
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
    :filter(function(winid)
      return vim.api.nvim_win_get_config(winid).zindex == nil
    end)
    :totable()
end

--- Get lines to be rendered for each visible window
--
function M.update()
  -- get active converters for each visible window
  local winid_to_converters = {}
  for _, winid in ipairs(get_visible_wins()) do
    local bufnr = vim.api.nvim_win_get_buf(winid)
    for src, dest_tbl in pairs(require("portal.classes.Converter").instances[bufnr] or {}) do
      for dest, converter in pairs(dest_tbl) do
        winid_to_converters[winid] = winid_to_converters[winid] or {}
        table.insert(winid_to_converters[winid], converter)
      end
    end
  end

  -- remove status windows which aren't active anymore
  M.prune(vim.tbl_keys(winid_to_converters))

  -- get lines to be rendered for each window with active converters
  for winid, converters in pairs(winid_to_converters) do
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
    M.status_wins[winid] = M.status_wins[winid] or require("portal.status.classes.StatusWindow"):construct(winid)
    M.status_wins[winid]:set_lines(lines)
  end
end

--- Remove any stale status windows, i.e. those whose parent windows no longer exist or have open portals
--
---@param active_wins integer[]
function M.prune(active_wins)
  local active_wins_map = {}
  for _, winid in ipairs(active_wins) do
    active_wins_map[winid] = true
  end

  for winid, status_win in pairs(M.status_wins) do
    if not active_wins_map[winid] then
      status_win:destruct()
      M.status_wins[winid] = nil
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
    for winid, status_win in pairs(M.status_wins) do
      status_win:destruct()
      M.status_wins[winid] = nil
    end

    vim.api.nvim_del_augroup_by_id(M.augroup_id)
  end
end

--- Open converter log on click
--
vim.keymap.set("n", "<LeftMouse>", function()
  local mousepos = vim.fn.getmousepos()

  local clicked_status_win = require("portal.status.classes.StatusWindow").instances[mousepos.winid]
  if clicked_status_win == nil then
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes("<LeftMouse>", true, true, true), "n", false)
    return
  end

  local clicked_line_str = require("portal.status.lines").get_raw_lines(clicked_status_win.lines)[mousepos.line]
  local src = clicked_line_str:match("(%w+) %-%->")
  local dest = clicked_line_str:match("%-%-> (%w+)")
  local bufnr = vim.api.nvim_win_get_buf(clicked_status_win.parent_winid)
  local converter = require("portal.classes.Converter").instances[bufnr][src][dest]

  vim.api.nvim_win_call(clicked_status_win.parent_winid, function()
    local log_win = vim.api.nvim_open_win(converter.log_buf, false, {
      split = "below",
    })
    vim.api.nvim_win_call(log_win, function()
      vim.cmd("normal! G")
    end)
  end)
end, {})

return M
