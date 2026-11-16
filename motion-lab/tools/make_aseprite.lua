-- Build an editable .aseprite file from a capture folder.
-- Frames play at the captured 60 Hz (1/60 s each), and capture.json is turned
-- into animation tags: one tag per hit phase (startup / active / recovery)
-- plus the trailing idle. Those tags are where to choose the keyframes.
--
-- aseprite -b --script-param dir=<capture folder> --script-param out=<file.aseprite> \
--   --script tools/make_aseprite.lua
local dir = app.params["dir"]
local out = app.params["out"]
local sprite = app.open(dir .. "/f_0000.png")  -- numbered PNGs open as one sequence
if not sprite then error("could not open " .. dir) end

local f = io.open(dir .. "/capture.json", "r")
local meta = json.decode(f:read("a"))
f:close()

for _, fr in ipairs(sprite.frames) do fr.duration = 1 / 60 end
sprite.layers[1].name = "capture"

local frames = meta.frames
local start, prevKey = 1, nil
local function label(m)
  if m.action == "attack" then
    return string.format("hit%d_%s", m.attack_index + 1, m.attack_phase)
  end
  return m.action
end
for i = 1, #frames + 1 do
  local key = frames[i] and label(frames[i]) or nil
  if key ~= prevKey then
    if prevKey then
      local tag = sprite:newTag(start, i - 1)
      tag.name = prevKey
    end
    start, prevKey = i, key
  end
end
sprite:saveAs(out)
print("saved " .. out .. " frames=" .. #sprite.frames .. " tags=" .. #sprite.tags)
