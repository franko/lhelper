local lua_dir = os.getenv("LHELPER_DIR") or (os.getenv("LHELPER_PREFIX") .. "/share/lhelper")
local module_path = lua_dir .. "/lua/?.lua"
local orig_path = package.path
package.path = module_path .. ";" .. orig_path

local M = {
   LHELPER_DIR = lua_dir,
}

return M
