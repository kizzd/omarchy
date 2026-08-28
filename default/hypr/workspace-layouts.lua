-- Restore workspace rules saved per workspace: layouts from
-- omarchy-hyprland-workspace-layout-toggle, and the persistent flag from
-- omarchy-hyprland-workspace-persist.

local paths = require("default.hypr.paths")
local require_all = require("default.hypr.require_all")

local layouts_dir = paths.state_home .. "/omarchy/workspace-layouts"

require_all.files(layouts_dir, "omarchy.workspace-layouts", { reload = true })
