---@alias portal.Cmd string[]|fun(): string[]

---@alias portal.LocalPortalDescription { bufnr: integer, src: string, dest: string }
---@alias portal.GlobalPortalDescription { src: string, dest: string }
---@alias portal.PortalDescription portal.LocalPortalDescription|portal.GlobalPortalDescription

---@class portal.Converter
---@field proc? vim.SystemObj
---@field busy boolean
---@field queued boolean
---@field augroup_id integer
---@field convert function(): nil
---@field cfg portal.ConverterSpec

---@class portal.LocalViewer
---@field proc? vim.SystemObj
---@field augroup_id integer
---@field view function(): nil
---@field cfg portal.ViewerSpec

---@class portal.GlobalViewer
---@field proc? vim.SystemObj
---@field augroup_id integer
---@field bufnr integer
---@field view function(): nil
---@field cfg portal.ViewerSpec

---@alias portal.ActiveComponents { converters: { [integer]: { [string]: { [string]: portal.Converter } } }, local_viewers: { [integer]: { [string]: { [string]: portal.LocalViewer } }, global_viewers: { [string]: { [string]: portal.GlobalViewer } } } }

---@alias portal.ConverterSpec { cmd: portal.Cmd, daemon: boolean, stdin: boolean }
---@alias portal.ViewerSpec { open_cmd: portal.Cmd, refresh_cmd: portal.Cmd?, detach: boolean }

---@class portal.Config
---@field converters { [string]: portal.ConverterSpec }
---@field viewers { [string]: portal.ViewerSpec }
---@field portals { [string]: { [string]: { converter: string|portal.ConverterSpec, viewer: string|portal.ViewerSpec } } }
