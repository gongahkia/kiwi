-- Application-only adapter for Kiwi's current renderer and platform layer.
-- This module is deliberately excluded from the `kiwi.vt` public surface:
-- external consumers must use render-update views instead of mutable state.
local Internal = {}

function Internal.state(terminal)
  assert(type(terminal) == "table" and terminal._state ~= nil, "internal VT adapter needs a Kiwi terminal")
  return terminal._state
end

function Internal.parser(terminal)
  assert(type(terminal) == "table" and terminal._parser ~= nil, "internal VT adapter needs a Kiwi terminal")
  return terminal._parser
end

return Internal
