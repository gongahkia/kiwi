local Corpus = {
  version = "kiwi-text-corpus-v1",
  scenarios = {
    {
      id = "ascii",
      category = "ASCII",
      text = "Kiwi terminal text 123: printf --help",
      source = "Kiwi-authored fixture text",
      license = "no third-party text or font asset",
    },
    {
      id = "combining",
      category = "combining",
      text = "Cafe\204\129 e\204\136 a\204\212\204\201",
      source = "Kiwi-authored arrangement of Unicode 17 code points",
      license = "Unicode License v3 for referenced Unicode data",
    },
    {
      id = "cjk",
      category = "CJK",
      text = "\228\184\173\230\150\135 \230\188\162\229\173\151 \230\151\165\230\156\172\232\170\158 \227\130\171\227\130\191\227\130\171\227\131\138 \237\149\156\234\184\128",
      source = "Kiwi-authored arrangement of Unicode 17 code points",
      license = "Unicode License v3 for referenced Unicode data",
    },
    {
      id = "emoji",
      category = "emoji",
      text = "\240\159\145\169\226\128\141\240\159\154\128 \240\159\135\184\240\159\135\172 \226\157\164\239\184\143 1\239\184\143\226\131\163",
      source = "Kiwi-authored arrangement of Unicode 17 emoji code points",
      license = "Unicode License v3 for referenced Unicode data",
    },
    {
      id = "ligatures",
      category = "ligatures",
      text = "ffi fl fi == != -> <= >=",
      source = "Kiwi-authored fixture text",
      license = "no third-party text or font asset",
    },
    {
      id = "dense-ui",
      category = "dense UI",
      text = "\226\148\140\226\148\128 build \226\148\128\226\148\172\226\148\128 99% \226\148\128\226\148\144 \226\148\130 main.lua \226\148\130 \226\156\147 42 \226\148\130 \226\148\148\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\180\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\128\226\148\152 \226\150\136\226\150\147\226\150\146\226\150\145",
      source = "Kiwi-authored box-drawing and status fixture",
      license = "no third-party text or font asset",
    },
  },
}

function Corpus.display_lines()
  local lines = { "Kiwi M8 text corpus " .. Corpus.version }
  for _, scenario in ipairs(Corpus.scenarios) do
    lines[#lines + 1] = scenario.id .. ": " .. scenario.text
  end
  return lines
end

return Corpus
