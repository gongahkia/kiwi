local Base64 = require("kiwi.terminal.base64")
local Png = require("kiwi.ffi.png")

local KittyGraphics = {}
KittyGraphics.__index = KittyGraphics

KittyGraphics.default_max_apc_bytes = 4096
KittyGraphics.default_max_encoded_bytes = 1024 * 1024
KittyGraphics.default_max_images = 64
KittyGraphics.default_max_transfer_chunks = 256
KittyGraphics.default_max_width = 8192
KittyGraphics.default_max_height = 8192
KittyGraphics.default_max_pixels = 16 * 1024 * 1024
KittyGraphics.default_max_decoded_bytes = 64 * 1024 * 1024
KittyGraphics.default_max_cpu_bytes = 64 * 1024 * 1024
KittyGraphics.default_max_gpu_bytes = 64 * 1024 * 1024

local function positive_integer(value, name)
  assert(type(value) == "number" and value >= 1 and value % 1 == 0, name .. " must be a positive integer")
  return value
end

local function copy_stats(stats)
  return {
    accepted = stats.accepted,
    cpu_bytes = stats.cpu_bytes,
    decoded = stats.decoded,
    evicted = stats.evicted,
    gpu_bytes = stats.gpu_bytes,
    gpu_evicted = stats.gpu_evicted,
    gpu_released = stats.gpu_released,
    last_error = stats.last_error,
    rejected = stats.rejected,
    released = stats.released,
    transfers_completed = stats.transfers_completed,
    transfers_interrupted = stats.transfers_interrupted,
  }
end

local function parse_controls(value)
  if value == "" then return nil, "empty-controls" end
  if value:sub(-1) == "," then return nil, "empty-control" end
  local controls = {}
  local start = 1
  while start <= #value do
    local comma = value:find(",", start, true)
    local token = value:sub(start, comma and comma - 1 or #value)
    if token == "" then return nil, "empty-control" end
    local key, field = token:match("^([a-zA-Z])=(.*)$")
    if key == nil or controls[key] ~= nil then return nil, "invalid-controls" end
    for index = 1, #field do
      local byte = field:byte(index)
      if byte < 0x20 or byte > 0x7e then return nil, "invalid-controls" end
    end
    controls[key] = field
    if comma == nil then break end
    start = comma + 1
  end
  return controls
end

local function unsigned_integer(value, maximum)
  if value == nil or not value:match("^%d+$") then return nil end
  local number = tonumber(value)
  if number == nil or number > maximum then return nil end
  return number
end

local function strict_base64(value)
  if #value == 0 or #value % 4 ~= 0 then return false end
  local padding = 0
  for index = #value, 1, -1 do
    if value:byte(index) == 0x3d then padding = padding + 1 else break end
  end
  if padding > 2 then return false end
  for index = 1, #value - padding do
    local byte = value:byte(index)
    if not ((byte >= 0x41 and byte <= 0x5a)
      or (byte >= 0x61 and byte <= 0x7a)
      or (byte >= 0x30 and byte <= 0x39)
      or byte == 0x2b
      or byte == 0x2f) then
      return false
    end
  end
  return true
end

local function png_header(bytes)
  if #bytes < 24 or bytes:sub(1, 8) ~= "\137PNG\r\n\26\n" or bytes:sub(13, 16) ~= "IHDR" then
    return nil, "png-header"
  end
  local length = ((bytes:byte(9) * 0x100 + bytes:byte(10)) * 0x100 + bytes:byte(11)) * 0x100 + bytes:byte(12)
  if length ~= 13 then return nil, "png-header" end
  local width = ((bytes:byte(17) * 0x100 + bytes:byte(18)) * 0x100 + bytes:byte(19)) * 0x100 + bytes:byte(20)
  local height = ((bytes:byte(21) * 0x100 + bytes:byte(22)) * 0x100 + bytes:byte(23)) * 0x100 + bytes:byte(24)
  return width, height
end

local function protocol_response(id, status)
  return string.format("\27_Gi=%d;%s\27\\", id or 0, status)
end

function KittyGraphics.new(options)
  options = options or {}
  local self = setmetatable({
    images = {},
    max_apc_bytes = positive_integer(options.max_apc_bytes or KittyGraphics.default_max_apc_bytes, "kitty graphics APC limit"),
    max_cpu_bytes = positive_integer(options.max_cpu_bytes or KittyGraphics.default_max_cpu_bytes, "kitty graphics CPU cache limit"),
    max_decoded_bytes = positive_integer(options.max_decoded_bytes or KittyGraphics.default_max_decoded_bytes, "kitty graphics decoded-image limit"),
    max_encoded_bytes = positive_integer(options.max_encoded_bytes or KittyGraphics.default_max_encoded_bytes, "kitty graphics encoded transfer limit"),
    max_gpu_bytes = positive_integer(options.max_gpu_bytes or KittyGraphics.default_max_gpu_bytes, "kitty graphics GPU cache limit"),
    max_height = positive_integer(options.max_height or KittyGraphics.default_max_height, "kitty graphics height limit"),
    max_images = positive_integer(options.max_images or KittyGraphics.default_max_images, "kitty graphics image limit"),
    max_pixels = positive_integer(options.max_pixels or KittyGraphics.default_max_pixels, "kitty graphics pixel limit"),
    max_transfer_chunks = positive_integer(options.max_transfer_chunks or KittyGraphics.default_max_transfer_chunks, "kitty graphics transfer chunk limit"),
    max_width = positive_integer(options.max_width or KittyGraphics.default_max_width, "kitty graphics width limit"),
    next_generation = 0,
    next_use = 0,
    pending_gpu_releases = {},
    stats = {
      accepted = 0,
      cpu_bytes = 0,
      decoded = 0,
      evicted = 0,
      gpu_bytes = 0,
      gpu_evicted = 0,
      gpu_released = 0,
      last_error = nil,
      rejected = 0,
      released = 0,
      transfers_completed = 0,
      transfers_interrupted = 0,
    },
    transfer = nil,
  }, KittyGraphics)
  assert(self.max_decoded_bytes <= self.max_cpu_bytes, "kitty graphics decoded-image limit must not exceed CPU cache limit")
  return self
end

function KittyGraphics:touch(image, gpu)
  self.next_use = self.next_use + 1
  image[gpu and "gpu_last_used" or "cpu_last_used"] = self.next_use
end

function KittyGraphics:reject(reason)
  self.stats.rejected = self.stats.rejected + 1
  self.stats.last_error = reason
  return { ok = false, reason = reason }
end

function KittyGraphics:queue_gpu_release(image, reason, evicted)
  if image.gpu_bytes == 0 then return end
  self.pending_gpu_releases[#self.pending_gpu_releases + 1] = { generation = image.generation, id = image.id, reason = reason }
  self.stats.gpu_bytes = self.stats.gpu_bytes - image.gpu_bytes
  self.stats.gpu_released = self.stats.gpu_released + 1
  if evicted then self.stats.gpu_evicted = self.stats.gpu_evicted + 1 end
  image.gpu_bytes = 0
  image.gpu_last_used = nil
end

function KittyGraphics:release_image(image, reason, evicted)
  if self.on_image_release then self.on_image_release(image.id, reason) end
  self:queue_gpu_release(image, reason, evicted)
  self.images[image.id] = nil
  self.stats.cpu_bytes = self.stats.cpu_bytes - image.bytes
  self.stats.released = self.stats.released + 1
  if evicted then self.stats.evicted = self.stats.evicted + 1 end
end

function KittyGraphics:cpu_victim()
  local victim
  for _, image in pairs(self.images) do
    if victim == nil or image.cpu_last_used < victim.cpu_last_used
      or (image.cpu_last_used == victim.cpu_last_used and image.id < victim.id) then
      victim = image
    end
  end
  return victim
end

function KittyGraphics:gpu_victim(excluded)
  local victim
  for _, image in pairs(self.images) do
    if image.id ~= excluded and image.gpu_bytes > 0 and (victim == nil or image.gpu_last_used < victim.gpu_last_used
      or (image.gpu_last_used == victim.gpu_last_used and image.id < victim.id)) then
      victim = image
    end
  end
  return victim
end

function KittyGraphics:discard_transfer(reason)
  if self.transfer == nil then return end
  self.transfer = nil
  self.stats.transfers_interrupted = self.stats.transfers_interrupted + 1
end

function KittyGraphics:validate_transfer_controls(controls, continuation)
  if continuation then
    if controls.m == nil then return nil, "continuation-missing" end
    for key in pairs(controls) do
      if key ~= "m" then return nil, "continuation-controls" end
    end
    local more = unsigned_integer(controls.m, 1)
    if more == nil then return nil, "invalid-continuation" end
    return { more = more }
  end

  for key in pairs(controls) do
    if key ~= "a" and key ~= "f" and key ~= "i" and key ~= "m" and key ~= "s" and key ~= "t" and key ~= "v" then
      return nil, "unsupported-controls"
    end
  end
  if controls.a ~= "t" and controls.a ~= "q" then return nil, "unsupported-action" end
  if controls.f ~= "100" or controls.t ~= "d" then return nil, "unsupported-format" end
  local id = unsigned_integer(controls.i, 0xffffffff)
  local width = unsigned_integer(controls.s, self.max_width)
  local height = unsigned_integer(controls.v, self.max_height)
  local more = controls.m == nil and 0 or unsigned_integer(controls.m, 1)
  if id == nil or id == 0 then return nil, "invalid-image-id" end
  if width == nil or width == 0 or height == nil or height == 0 then return nil, "invalid-dimensions" end
  if more == nil then return nil, "invalid-continuation" end
  local pixels = width * height
  local decoded_bytes = pixels * 4
  if pixels > self.max_pixels or decoded_bytes > self.max_decoded_bytes then return nil, "decoded-limit" end
  return { action = controls.a, bytes = decoded_bytes, height = height, id = id, more = more, width = width }
end

function KittyGraphics:store(image)
  local existing = self.images[image.id]
  if existing then self:release_image(existing, "replaced", false) end
  while self.stats.cpu_bytes + image.bytes > self.max_cpu_bytes or self:image_count() >= self.max_images do
    local victim = self:cpu_victim()
    if victim == nil then return false end
    self:release_image(victim, "cpu-evicted", true)
  end
  self.images[image.id] = image
  self.stats.cpu_bytes = self.stats.cpu_bytes + image.bytes
  self:touch(image, false)
  return true
end

function KittyGraphics:image_count()
  local count = 0
  for _ in pairs(self.images) do count = count + 1 end
  return count
end

function KittyGraphics:complete_transfer(transfer, query)
  transfer.encoded = table.concat(transfer.chunks)
  transfer.chunks = nil
  if not strict_base64(transfer.encoded) then return self:reject("invalid-base64") end
  local decoded, bytes = pcall(Base64.decode, transfer.encoded)
  if not decoded then return self:reject("invalid-base64") end
  local width, height = png_header(bytes)
  if width == nil then return self:reject(height) end
  if width ~= transfer.width or height ~= transfer.height then return self:reject("png-dimensions") end
  local decoded_png, pixels, reason = pcall(Png.decode_rgba, bytes, transfer.width, transfer.height, transfer.bytes)
  if not decoded_png then return self:reject("png-decode") end
  if pixels == nil then return self:reject(reason) end

  self.stats.decoded = self.stats.decoded + 1
  self.stats.transfers_completed = self.stats.transfers_completed + 1
  self.stats.accepted = self.stats.accepted + 1
  self.stats.last_error = nil
  if query then return { ok = true, response = protocol_response(transfer.id, "OK") } end

  self.next_generation = self.next_generation + 1
  local image = {
    bytes = transfer.bytes,
    generation = self.next_generation,
    gpu_bytes = 0,
    height = transfer.height,
    id = transfer.id,
    pixels = pixels,
    width = transfer.width,
  }
  if not self:store(image) then return self:reject("cpu-cache-limit") end
  return { ok = true }
end

function KittyGraphics:apply(payload)
  if type(payload) ~= "string" or #payload > self.max_apc_bytes then
    if self.transfer then self:discard_transfer("apc-limit") end
    return self:reject("apc-limit")
  end
  local separator = payload:find(";", 1, true)
  local controls, reason = parse_controls(separator and payload:sub(1, separator - 1) or payload)
  if controls == nil then
    if self.transfer then self:discard_transfer(reason) end
    return self:reject(reason)
  end
  local data = separator and payload:sub(separator + 1) or ""

  if self.transfer then
    if controls.a == "d" and (separator == nil or data == "") then
      self:discard_transfer("deleted")
      return { controls = controls, ok = true, placement_action = "d" }
    end
    local continuation, continuation_reason = self:validate_transfer_controls(controls, true)
    if continuation == nil then
      self:discard_transfer(continuation_reason)
      return self:reject(continuation_reason)
    end
    if self.transfer.encoded_bytes + #data > self.max_encoded_bytes then
      self:discard_transfer("encoded-limit")
      return self:reject("encoded-limit")
    end
    if self.transfer.chunk_count >= self.max_transfer_chunks then
      self:discard_transfer("chunk-limit")
      return self:reject("chunk-limit")
    end
    self.transfer.chunks[#self.transfer.chunks + 1] = data
    self.transfer.chunk_count = self.transfer.chunk_count + 1
    self.transfer.encoded_bytes = self.transfer.encoded_bytes + #data
    if continuation.more == 1 then return { ok = true } end
    local transfer = self.transfer
    self.transfer = nil
    return self:complete_transfer(transfer, false)
  end

  if controls.a == "p" or controls.a == "d" then
    if separator and data ~= "" then return self:reject("unexpected-payload") end
    return { controls = controls, ok = true, placement_action = controls.a }
  end

  if separator == nil then return self:reject("missing-payload") end

  local transfer, transfer_reason = self:validate_transfer_controls(controls, false)
  if transfer == nil then return self:reject(transfer_reason) end
  if #data > self.max_encoded_bytes then return self:reject("encoded-limit") end
  transfer.chunks = { data }
  transfer.chunk_count = 1
  transfer.encoded_bytes = #data
  if transfer.action == "q" then
    if transfer.more ~= 0 then
      local result = self:reject("query-continuation")
      result.response = protocol_response(transfer.id, "ERR:query-continuation")
      return result
    end
    local result = self:complete_transfer(transfer, true)
    if not result.ok then result.response = protocol_response(transfer.id, "ERR:" .. result.reason) end
    return result
  end
  if transfer.more == 1 then
    self.transfer = transfer
    return { ok = true }
  end
  return self:complete_transfer(transfer, false)
end

function KittyGraphics:has_image(id)
  return self.images[id] ~= nil
end

function KittyGraphics:delete_image(id)
  if self.transfer and self.transfer.id == id then self:discard_transfer("deleted") end
  local image = self.images[id]
  if image == nil then return false end
  self:release_image(image, "deleted", false)
  return true
end

function KittyGraphics:upload_descriptor(id)
  local image = self.images[id]
  if image == nil then return nil, "unknown-image" end
  self:touch(image, false)
  return {
    bytes = image.bytes,
    generation = image.generation,
    height = image.height,
    id = image.id,
    pixels = image.pixels,
    width = image.width,
  }
end

function KittyGraphics:register_gpu_upload(id, generation, bytes)
  local image = self.images[id]
  if image == nil or image.generation ~= generation then return nil, "stale-image" end
  if image.gpu_bytes ~= 0 then return nil, "gpu-already-registered" end
  if bytes ~= image.bytes or bytes > self.max_gpu_bytes then return nil, "gpu-limit" end
  while self.stats.gpu_bytes + bytes > self.max_gpu_bytes do
    local victim = self:gpu_victim(id)
    if victim == nil then return nil, "gpu-limit" end
    self:queue_gpu_release(victim, "gpu-evicted", true)
  end
  image.gpu_bytes = bytes
  self.stats.gpu_bytes = self.stats.gpu_bytes + bytes
  self:touch(image, true)
  return true
end

function KittyGraphics:release_gpu_upload(id, generation, reason)
  local image = self.images[id]
  if image == nil or image.generation ~= generation then return false, "stale-image" end
  self:queue_gpu_release(image, reason or "renderer-release", false)
  return true
end

function KittyGraphics:touch_gpu_upload(id, generation)
  local image = self.images[id]
  if image == nil or image.generation ~= generation or image.gpu_bytes == 0 then return false end
  self:touch(image, true)
  return true
end

function KittyGraphics:take_gpu_releases()
  local releases = self.pending_gpu_releases
  self.pending_gpu_releases = {}
  return releases
end

function KittyGraphics:clear()
  local images = {}
  for _, image in pairs(self.images) do images[#images + 1] = image end
  for _, image in ipairs(images) do self:release_image(image, "reset", false) end
  self.transfer = nil
end

function KittyGraphics:view()
  local images = {}
  for _, image in pairs(self.images) do
    images[#images + 1] = {
      bytes = image.bytes,
      generation = image.generation,
      gpu = image.gpu_bytes == 0 and "unallocated" or "uploaded",
      height = image.height,
      id = image.id,
      width = image.width,
    }
  end
  table.sort(images, function(left, right) return left.id < right.id end)
  return {
    image_count = #images,
    images = images,
    limits = {
      cpu_bytes = self.max_cpu_bytes,
      decoded_bytes = self.max_decoded_bytes,
      encoded_bytes = self.max_encoded_bytes,
      gpu_bytes = self.max_gpu_bytes,
      images = self.max_images,
      pixels = self.max_pixels,
      transfer_chunks = self.max_transfer_chunks,
    },
    stats = copy_stats(self.stats),
    transfer_open = self.transfer ~= nil,
  }
end

function KittyGraphics:snapshot()
  return self:view()
end

return KittyGraphics
