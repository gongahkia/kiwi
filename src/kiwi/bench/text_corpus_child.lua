local Corpus = require("kiwi.text.benchmark_corpus")

for _, line in ipairs(Corpus.display_lines()) do io.stdout:write(line, "\n") end
