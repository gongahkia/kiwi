local Corpus = require("kiwi.text.benchmark_corpus")
local Environment = require("kiwi.bench.environment")
local Grapheme = require("kiwi.unicode.grapheme")
local Json = require("kiwi.bench.json")
local Utf8 = require("kiwi.terminal.utf8")
local Width = require("kiwi.terminal.width")

local Review = {}

local function codepoints(text)
  local values = {}
  local decoder = Utf8.Decoder.new(function(codepoint)
    values[#values + 1] = codepoint
  end)
  for index = 1, #text do decoder:feed_byte(text:byte(index)) end
  decoder:finish()
  return values
end

function Review.manifest()
  local scenarios = {}
  for index, scenario in ipairs(Corpus.scenarios) do
    local values = codepoints(scenario.text)
    local clusters = Grapheme.segment(values)
    local columns = 0
    for _, cluster in ipairs(clusters) do columns = columns + Width.columns(cluster) end
    scenarios[index] = {
      id = scenario.id,
      category = scenario.category,
      text = scenario.text,
      input_bytes = #scenario.text,
      codepoints = #values,
      clusters = #clusters,
      columns = columns,
      source = scenario.source,
      license = scenario.license,
    }
  end
  return {
    version = Corpus.version,
    unicode_version = "17.0.0",
    width_policy = Width.policy_version,
    scenarios = scenarios,
  }
end

function Review.main()
  local timestamp = os.date("!%Y%m%dT%H%M%SZ")
  local output = os.getenv("KIWI_TEXT_CORPUS_ARTIFACT") or "bench/results/" .. timestamp .. "-text-corpus.json"
  local file, message = io.open(output, "wb")
  if not file then error("Unable to create " .. output .. ": " .. message .. ". Run through make text-corpus-review so the results directory exists.") end
  file:write(Json.encode({
    schema_version = 1,
    artifact = "Kiwi M8 text corpus review manifest",
    metadata = Environment.collect(timestamp, 1, 0),
    corpus = Review.manifest(),
    review = {
      visual_command = "KIWI_MAX_FRAMES=240 make text-corpus-demo",
      semantic_criteria = "input bytes, code point, grapheme-cluster, and terminal-column counts must match this manifest",
      visual_criteria = "review a screenshot from the native demo for dropped glyphs, overlap, clipping, incorrect wide-cell occupancy, fallback changes, and dense UI alignment",
    },
  }), "\n")
  file:close()
  io.stdout:write("text corpus review manifest: " .. output .. "\n")
end

if ... == nil then Review.main() end

return Review
