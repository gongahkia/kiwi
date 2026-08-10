local Paths = {}

function Paths.lua_root(getenv)
  getenv = getenv or os.getenv
  local root = getenv("KIWI_ROOT") or "."
  return getenv("KIWI_LUA_ROOT") or root .. "/src"
end

return Paths
