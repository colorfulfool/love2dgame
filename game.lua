game = {}

local playerX = 700
local playerY = 100

local tiles = {
  { 0, 0, 0, 0, 1 },
  { 0, 1, 1, 0, 1 },
  { 0, 1, 0, 0, 1 },
  { 0, 1, 1, 1, 1 },
  { 0, 1, 1, 1, 1 },
  { 0, 0, 0, 1, 1 },
}

-- Converts a "#RRGGBB" (or "#RRGGBBAA") color, as written in the comments,
-- into the { r, g, b, a } table of 0-1 values that love.graphics.setColor expects.
local function hexToColor(hex, brightness)
  hex = hex:gsub("#", "")

  local r = tonumber(hex:sub(1, 2), 16) / 255
  local g = tonumber(hex:sub(3, 4), 16) / 255
  local b = tonumber(hex:sub(5, 6), 16) / 255
  local a = 1

  if #hex == 8 then
    a = tonumber(hex:sub(7, 8), 16) / 255
  end

  brightness = brightness or 1

  return { r * brightness, g * brightness, b * brightness, a }
end

local function clamp(value, low, high)
  return math.max(low, math.min(high, value))
end

local function mix(a, b, t)
  return a + (b - a) * t
end

local function smoothstep(edge0, edge1, x)
  local t = clamp((x - edge0) / (edge1 - edge0), 0, 1)
  return t * t * (3 - 2 * t)
end

-- Shoreline look, inspired by the old map in ~/Downloads/map.jpeg:
-- water darkens toward the coast, land darkens toward the coast, and a
-- dark line traces the shoreline itself.
local MAP_SIZE = 512         -- resolution of the baked shoreline texture
local SHORE_RANGE = 0.5      -- tiles: how far the dark shore shading reaches
local OUTLINE_WIDTH = 0.03   -- tiles: half-width of the dark shoreline line
local NOISE_STRENGTH = 0.22  -- how much the coastline wiggles
local NOISE_SCALE = 1.7

local DEEP_WATER = hexToColor("#8FA2BC")
local SHORE_WATER = hexToColor("#566B8C")
local INLAND = hexToColor("#E1CE81")
local SHORE_LAND = hexToColor("#A98F4A")
local OUTLINE = hexToColor("#3A3220")

local mapImage

local function tileValue(row, column)
  row = clamp(row, 1, #tiles)
  column = clamp(column, 1, #tiles[1])
  return tiles[row][column]
end

-- 0 = water, 1 = land, smoothly interpolated between tile centers.
local function landAt(u, v)
  local x = u - 0.5
  local y = v - 0.5

  local x0 = math.floor(x)
  local y0 = math.floor(y)

  local tx = x - x0
  local ty = y - y0

  local column = x0 + 1
  local row = y0 + 1

  local top = mix(tileValue(row, column), tileValue(row, column + 1), tx)
  local bottom = mix(tileValue(row + 1, column), tileValue(row + 1, column + 1), tx)

  return mix(top, bottom, ty)
end

local function fieldAt(u, v)
  local wobble = love.math.noise(u * NOISE_SCALE, v * NOISE_SCALE) - 0.5
  return landAt(u, v) + wobble * NOISE_STRENGTH
end

local function buildMapImage(size)
  local imageData = love.image.newImageData(size, size)

  local fieldWidth = #tiles[1]
  local fieldHeight = #tiles

  local isLand = {}
  local distance = {}

  local infinity = 1e9

  -- First pass: decide whether every pixel is land or water.
  for py = 0, size - 1 do
    isLand[py] = {}
    distance[py] = {}

    for px = 0, size - 1 do
      local u = (px + 0.5) / size * fieldWidth
      local v = (py + 0.5) / size * fieldHeight

      isLand[py][px] = fieldAt(u, v) >= 0.5
    end
  end

  -- Second pass: mark the pixels that touch the shoreline.
  for py = 0, size - 1 do
    for px = 0, size - 1 do
      local land = isLand[py][px]
      local shore = false

      if px > 0 and isLand[py][px - 1] ~= land then shore = true end
      if px < size - 1 and isLand[py][px + 1] ~= land then shore = true end
      if py > 0 and isLand[py - 1][px] ~= land then shore = true end
      if py < size - 1 and isLand[py + 1][px] ~= land then shore = true end

      distance[py][px] = shore and 0 or infinity
    end
  end

  -- Third pass: spread the distance outwards from the shoreline
  -- (two-pass chamfer distance transform, in pixels).
  local diagonal = math.sqrt(2)

  for py = 0, size - 1 do
    for px = 0, size - 1 do
      local d = distance[py][px]

      if px > 0 then
        d = math.min(d, distance[py][px - 1] + 1)
      end

      if py > 0 then
        d = math.min(d, distance[py - 1][px] + 1)

        if px > 0 then
          d = math.min(d, distance[py - 1][px - 1] + diagonal)
        end

        if px < size - 1 then
          d = math.min(d, distance[py - 1][px + 1] + diagonal)
        end
      end

      distance[py][px] = d
    end
  end

  for py = size - 1, 0, -1 do
    for px = size - 1, 0, -1 do
      local d = distance[py][px]

      if px < size - 1 then
        d = math.min(d, distance[py][px + 1] + 1)
      end

      if py < size - 1 then
        d = math.min(d, distance[py + 1][px] + 1)

        if px < size - 1 then
          d = math.min(d, distance[py + 1][px + 1] + diagonal)
        end

        if px > 0 then
          d = math.min(d, distance[py + 1][px - 1] + diagonal)
        end
      end

      distance[py][px] = d
    end
  end

  local pixelsPerTile = size / fieldWidth

  -- Fourth pass: paint the pixels using the distance to the shoreline.
  for py = 0, size - 1 do
    for px = 0, size - 1 do
      local distanceInTiles = distance[py][px] / pixelsPerTile

      local r, g, b

      if isLand[py][px] then
        local t = smoothstep(0, SHORE_RANGE, distanceInTiles)
        r = mix(SHORE_LAND[1], INLAND[1], t)
        g = mix(SHORE_LAND[2], INLAND[2], t)
        b = mix(SHORE_LAND[3], INLAND[3], t)
      else
        local t = smoothstep(0, SHORE_RANGE, distanceInTiles)
        r = mix(SHORE_WATER[1], DEEP_WATER[1], t)
        g = mix(SHORE_WATER[2], DEEP_WATER[2], t)
        b = mix(SHORE_WATER[3], DEEP_WATER[3], t)
      end

      local outline = 1 - smoothstep(OUTLINE_WIDTH * 0.4, OUTLINE_WIDTH, distanceInTiles)
      r = mix(r, OUTLINE[1], outline)
      g = mix(g, OUTLINE[2], outline)
      b = mix(b, OUTLINE[3], outline)

      imageData:setPixel(px, py, r, g, b, 1)
    end
  end

  return love.graphics.newImage(imageData)
end

local function getMapImage()
  if not mapImage then
    mapImage = buildMapImage(MAP_SIZE)
  end

  return mapImage
end

local glowImage

-- Soft radial light used to highlight the player instead of a square tile.
local function getGlowImage()
  if not glowImage then
    local size = 64
    local imageData = love.image.newImageData(size, size)
    local center = (size - 1) / 2
    local radius = size / 2

    for y = 0, size - 1 do
      for x = 0, size - 1 do
        local dx = (x - center) / radius
        local dy = (y - center) / radius
        local distance = math.sqrt(dx * dx + dy * dy)
        local alpha = 1 - smoothstep(0.2, 1, distance)

        imageData:setPixel(x, y, 1, 1, 1, alpha)
      end
    end

    glowImage = love.graphics.newImage(imageData)
  end

  return glowImage
end

function game.update(dt)
  if love.keyboard.isDown("up") then
    playerY = playerY - dt * 200
  end

  if love.keyboard.isDown("down") then
    playerY = playerY + dt * 200
  end

  if love.keyboard.isDown("left") then
    playerX = playerX - dt * 200
  end

  if love.keyboard.isDown("right") then
    playerX = playerX + dt * 200
  end
end

function game.draw()
  local fieldHeight = #tiles
  local fieldWidth = #tiles[1]

  screenWidth, screenHeight = love.graphics.getDimensions()

  local tileWidth = screenWidth / fieldWidth
  local tileHeight = screenHeight / fieldHeight

  local playerWidth = tileWidth * 0.5
  local playerHeight = tileHeight * 0.5

  local playerCenterX = playerX + playerWidth / 2
  local playerCenterY = playerY + playerHeight / 2

  local map = getMapImage()

  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(map, 0, 0, 0, screenWidth / map:getWidth(), screenHeight / map:getHeight())

  -- Soft light around the player instead of a square tile highlight.
  local glow = getGlowImage()
  local glowSize = math.max(playerWidth, playerHeight) * 2.5

  love.graphics.setBlendMode("add")
  love.graphics.setColor(1, 1, 1, 0.18)
  love.graphics.draw(
    glow,
    playerCenterX,
    playerCenterY,
    0,
    glowSize / glow:getWidth(),
    glowSize / glow:getHeight(),
    glow:getWidth() / 2,
    glow:getHeight() / 2
  )
  love.graphics.setBlendMode("alpha")

  love.graphics.setColor({ 0, 0, 0, 0.2 })
  love.graphics.rectangle("fill", playerX + 10, playerY + 10, playerWidth, playerHeight)

  love.graphics.setColor({ 1, 1, 1 })
  love.graphics.rectangle("fill", playerX, playerY, playerWidth, playerHeight)
end

return game
