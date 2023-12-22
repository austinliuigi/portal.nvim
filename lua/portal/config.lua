---@alias cmd_t (string|function)[]
---@alias view_t { open_cmd: cmd_t, refresh_cmd: cmd_t }
---@alias dest_spec { convert_cmd: cmd_t, update_events: string|string[], view: view_t, throttle_ms: integer }
---@alias portal_spec table<string, dest_spec>

---@class Config
---@field portals portal_spec[]

local portal = require("portal")
local utils = require("portal.utils")

local config = {
  portals = utils.default_table({
    md = {
      html = {
        convert_cmd = function()
          return {
            "pandoc",
            portal.infile,
            "--katex",
            "--standalone",
            "-o",
            portal.outfile,
          }
        end,
        viewer = {
          open_cmd = { "firefox", portal.outfile },
          refresh_cmd = nil,
        },
        update_events = { "TextChanged", "TextChangedI" },
        throttle_ms = nil,
      },
      pdf = {
        convert_cmd = function()
          return {
            "pandoc",
            "--from=markdown",
            "--to=pdf",
            "-o",
            portal.outfile,
          }
        end,
        viewer = {
          open_cmd = { "sioyek", portal.outfile },
          refresh_cmd = nil,
        },
        update_events = { "TextChanged", "TextChangedI" },
        throttle_ms = 1000,
      },
    },
  }),
}

return config
