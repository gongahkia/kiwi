local Build = require("kiwi.build")

local Environment = {}

-- Identify the terminal that owns this new PTY. Inheriting TERM_PROGRAM from
-- a launcher terminal can make shells/editors select that terminal's protocols.
function Environment.terminal(terminfo_directory)
  return {
    TERM = "xterm-kiwi",
    TERMINFO = terminfo_directory,
    COLORTERM = "truecolor",
    TERM_PROGRAM = "Kiwi",
    TERM_PROGRAM_VERSION = Build.info().version,
  }
end

return Environment
