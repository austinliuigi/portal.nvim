local M = {}

local default_frames = {
  "",
  "",
  "",
  "",
  "",
  "",
}

--- Generate a function that provides a spinner frame for a given time
--
---@param frames? string[]
---@param period_sec? number The time in seconds it takes to cycle through all frames
---@return fun(number): string
function M.animate(frames, period_sec)
  frames = frames or default_frames
  period_sec = period_sec or 1

  --- Timestamp of the first frame of the animation.
  ---@type number?
  local origin

  ---@param now number
  return function(now)
    if not origin then
      origin = now
    end

    local delta_t_mod = (now - origin) % period_sec

    -- map range of period to range of frames, e.g. 0.0 - 1.0 -> 1 - 6
    return frames[math.floor((delta_t_mod * #frames / period_sec) + 1)]
  end
end

return M
