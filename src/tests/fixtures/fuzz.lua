return {
  {
    id = "large-osc-payload",
    input = "\27]2;" .. string.rep("x", 8192) .. "\7after",
  },
  {
    id = "large-dcs-payload",
    input = "\27P" .. string.rep("y", 8192) .. "\27\\after",
  },
  {
    id = "csi-parameter-overflow",
    input = "\27[" .. string.rep("999;", 64) .. "Hafter",
  },
  {
    id = "truncated-and-malformed-terminators",
    input = "\27]2;unterminated\27x\27Pdiscard\27x\27[?1049h\27[?1049lafter",
  },
  {
    id = "repeated-mode-reset",
    input = string.rep("\27[?1049h\27[?2004h\27[?2004l\27[?1049l", 32) .. "\27cafter",
  },
  {
    id = "reverse-wraparound-margins",
    input = "\27[?45h\27[2;3r\27[?69h\27[2;3s\8\8\27[?7l\8\27cafter",
  },
}
