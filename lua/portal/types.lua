--==============================================================================
-- CONVERTERS
--==============================================================================

---@class portal.Converter
---@field src string
---@field dest string
---@field bufnr integer
---@field has_converted boolean
---@field augroup_id integer
---@field cfg portal.ConverterConfig
---@field cmd portal.Cmd
---@field cmd_substitutions portal.CmdSubstitutions
---@field proc? vim.SystemObj
---@field viewers (portal.LocalViewer|portal.GlobalViewer)[]
---@field construct function(): nil
---@field destruct function(): nil
---@field convert function(): nil
---@field is_headless function(): boolean
---@field attach_viewer function(): nil
---@field detach_viewer function(): nil
---@field update_viewers function(): nil
---@field status portal.Status

---@class portal.OneShotConverter: portal.Converter
---@field busy boolean
---@field queued boolean
---@field handle_successful_conversion function(): nil
---@field handle_failed_conversion function(): nil

---@class portal.DaemonConverter: portal.Converter
---@field handle_successful_conversion function(): nil
---@field handle_failed_conversion function(): nil

---@class portal.MirrorConverter: portal.Converter

--==============================================================================
-- VIEWERS
--==============================================================================

---@class portal.Viewer
---@field src string
---@field dest string
---@field cfg portal.ViewerConfig
---@field open_cmd portal.Cmd
---@field refresh_cmd portal.Cmd?
---@field cmd_substitutions portal.CmdSubstitutions
---@field converter? portal.Converter
---@field proc? vim.SystemObj
---@field construct function(): nil
---@field destruct function(): nil
---@field open function(): nil
---@field refresh function(): nil
---@field open_or_update function(): nil

---@class portal.LocalViewer: portal.Viewer
---@field bufnr integer

---@class portal.GlobalViewer: portal.LocalViewer
---@field is_target_outdated boolean
---@field augroup_id integer
---@field switch_cmd portal.Cmd
---@field switch function(): nil

--==============================================================================
-- CONFIG
--==============================================================================

---@alias portal.CmdSubstitutions { [string]: (string|fun(): string) }
---@alias portal.CmdArg string|fun(): string
---@alias portal.CmdConfig portal.CmdArg[]|fun(): portal.CmdArg[]
---@alias portal.Cmd portal.CmdArg[]

---@alias portal.ConverterSuccessConditions { stdout_contains: string?, stderr_contains: string?, exit_code: integer? }
---@alias portal.ConverterFailureConditions { stdout_contains: string?, stderr_contains: string? }

---@class portal.ConverterConfig
---@field cmd portal.CmdConfig
---@field stdin boolean
---@field daemon boolean
---@field success_condition? portal.ConverterSuccessConditions
---@field failure_condition? portal.ConverterFailureConditions

---@class portal.ViewerConfig
---@field open_cmd portal.CmdConfig
---@field switch_cmd portal.CmdConfig
---@field refresh_cmd? portal.CmdConfig
---@field detach boolean

---@class portal.PortalConfig
---@field converter nil|string|portal.ConverterConfig
---@field viewer string|portal.ViewerConfig

---@class portal.Config
---@field cache_retention_days integer
---@field converters { [string]: portal.ConverterConfig }
---@field viewers { [string]: portal.ViewerConfig }
---@field portals { [string]: { [string]: portal.PortalConfig } }

--==============================================================================
-- STATUS
--==============================================================================

---@alias portal.Status "idle"|"converting"|"failed"|"succeeded"

---@alias portal.StatusChunk {[1]: string, [2]?: string|string[]}
---@alias portal.StatusLine portal.StatusChunk[]

---@class portal.StatusWindow
---@field parent_winnr integer
---@field bufnr integer
---@field namespace_id integer
---@field winnr? integer
---@field lines portal.StatusLine[]
