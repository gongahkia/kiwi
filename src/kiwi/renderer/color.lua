-- Kept as a compatibility import for renderer callers. Colour packing belongs
-- to the terminal core so renderer-neutral consumers do not depend on it.
return require("kiwi.terminal.color")
