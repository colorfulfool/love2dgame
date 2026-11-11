game = {}

local playerX = 700
local playerY = 100

local tiles = {
  { 0, 0, 0, 0, 1 },
  { 0, 2, 2, 0, 1 },
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
local MAP_SIZE = 1024       -- resolution of the baked shoreline texture
local SHORE_RANGE = 0.5     -- tiles: how far the dark shore shading reaches
local OUTLINE_WIDTH = 0.03  -- tiles: half-width of the dark shoreline line
local NOISE_STRENGTH = 0.22 -- how much the coastline wiggles
local NOISE_SCALE = 1.7

local DEEP_WATER = hexToColor("#8FA2BC")
local SHORE_WATER = hexToColor("#566B8C")
local INLAND = hexToColor("#E1CE81")
local SHORE_LAND = hexToColor("#A98F4A")
local OUTLINE = hexToColor("#3A3220")

-- The city uses just two colors, like the old map: reddish ink for every
-- outline, and an off-white fill for roofs, walls and streets.
local CITY_PAPER = hexToColor("#FAF6EA")
local CITY_INK = hexToColor("#A3542E")

-- City details are drawn in texture pixels, so they scale with MAP_SIZE to
-- keep the same look on screen.
local CITY_SCALE = MAP_SIZE / 512

local WALL_WIDTH = 0.095
local WALL_LINE_WIDTH = 0.012
local TOWER_SPACING = 44 * CITY_SCALE
local TOWER_WIDTH = 14 * CITY_SCALE
local TOWER_DEPTH = 0.05
local MERLON_SPACING = 6 * CITY_SCALE
local MERLON_WIDTH = 2 * CITY_SCALE
local MERLON_DEPTH = 0.022
local BUILDING_MARGIN = 0.14

local mapImage

local function rawTile(row, column)
  row = clamp(row, 1, #tiles)
  column = clamp(column, 1, #tiles[1])
  return tiles[row][column]
end

local function landValue(row, column)
  local value = rawTile(row, column)

  if value == 2 then
    return 1
  end

  return value
end

local function cityValue(row, column)
  return rawTile(row, column) == 2 and 1 or 0
end

local function valueAt(getValue, u, v)
  local x = u - 0.5
  local y = v - 0.5

  local x0 = math.floor(x)
  local y0 = math.floor(y)

  local tx = x - x0
  local ty = y - y0

  local column = x0 + 1
  local row = y0 + 1

  local top = mix(getValue(row, column), getValue(row, column + 1), tx)
  local bottom = mix(getValue(row + 1, column), getValue(row + 1, column + 1), tx)

  return mix(top, bottom, ty)
end

-- 0 = water, 1 = land, smoothly interpolated between tile centers.
local function landAt(u, v)
  return valueAt(landValue, u, v)
end

local function cityAt(u, v)
  return valueAt(cityValue, u, v)
end

local function fieldAt(u, v)
  local wobble = love.math.noise(u * NOISE_SCALE, v * NOISE_SCALE) - 0.5
  return landAt(u, v) + wobble * NOISE_STRENGTH
end

local function setMaskedPixel(imageData, size, mask, x, y, color)
  if x < 0 or x >= size or y < 0 or y >= size then
    return
  end

  if not mask[y][x] then
    return
  end

  imageData:setPixel(x, y, color[1], color[2], color[3], 1)
end

local function fillMaskedRect(imageData, size, mask, x, y, width, height, color)
  for py = math.floor(y), math.floor(y + height) - 1 do
    for px = math.floor(x), math.floor(x + width) - 1 do
      setMaskedPixel(imageData, size, mask, px, py, color)
    end
  end
end

local function fillMaskedCircle(imageData, size, mask, centerX, centerY, radius, color)
  for py = math.floor(centerY - radius), math.ceil(centerY + radius) do
    for px = math.floor(centerX - radius), math.ceil(centerX + radius) do
      local dx = px + 0.5 - centerX
      local dy = py + 0.5 - centerY

      if dx * dx + dy * dy <= radius * radius then
        setMaskedPixel(imageData, size, mask, px, py, color)
      end
    end
  end
end

local function drawMaskedLine(imageData, size, mask, x0, y0, x1, y1, color)
  x0 = math.floor(x0)
  y0 = math.floor(y0)
  x1 = math.floor(x1)
  y1 = math.floor(y1)

  local dx = math.abs(x1 - x0)
  local dy = -math.abs(y1 - y0)
  local stepX = x0 < x1 and 1 or -1
  local stepY = y0 < y1 and 1 or -1
  local error = dx + dy

  while true do
    setMaskedPixel(imageData, size, mask, x0, y0, color)

    if x0 == x1 and y0 == y1 then
      break
    end

    local doubled = 2 * error

    if doubled >= dy then
      error = error + dy
      x0 = x0 + stepX
    end

    if doubled <= dx then
      error = error + dx
      y0 = y0 + stepY
    end
  end
end

-- Houses are drawn the way old game maps do it: a pitched roof over a front
-- wall, stacked in rows from the back of the city to the front so each row
-- rises over the one behind it.
local function fillMaskedTrapezoid(imageData, size, mask, left, right, top, bottom, topInset, color)
  for py = math.floor(top), math.floor(bottom) do
    local t = (py - top) / math.max(1, bottom - top)
    local inset = topInset * (1 - t)

    for px = math.floor(left + inset), math.floor(right - inset) do
      setMaskedPixel(imageData, size, mask, px, py, color)
    end
  end
end

-- Just a roof and the visible sides of the house. The row in front covers
-- the bottom, so there is no need to paint a base or a door.
local function drawHouse(imageData, size, mask, x, baselineY, width, wallHeight, roofHeight, topInset, stroke)
  local wallTop = baselineY - wallHeight
  local roofTop = wallTop - roofHeight

  -- Pitched roof, seen from the side.
  fillMaskedTrapezoid(imageData, size, mask, x, x + width, roofTop, wallTop, topInset, CITY_INK)
  fillMaskedTrapezoid(
    imageData,
    size,
    mask,
    x + stroke,
    x + width - stroke,
    roofTop + stroke,
    wallTop - stroke,
    topInset,
    CITY_PAPER
  )

  -- Faces of the front wall: two reddish edges on off-white.
  fillMaskedRect(imageData, size, mask, x + stroke, wallTop + stroke, width - stroke * 2, wallHeight - stroke, CITY_PAPER)
  fillMaskedRect(imageData, size, mask, x, wallTop, stroke, wallHeight, CITY_INK)
  fillMaskedRect(imageData, size, mask, x + width - stroke, wallTop, stroke, wallHeight, CITY_INK)
end

local function drawDomeHouse(imageData, size, mask, x, baselineY, width, wallHeight, roofRadius, stroke)
  local wallTop = baselineY - wallHeight
  local centerX = x + width / 2

  -- Dome: the lower half is hidden behind the wall drawn next.
  fillMaskedCircle(imageData, size, mask, centerX, wallTop, roofRadius, CITY_INK)
  fillMaskedCircle(imageData, size, mask, centerX, wallTop, roofRadius - stroke, CITY_PAPER)

  -- Little finial on top.
  fillMaskedRect(imageData, size, mask, centerX - stroke / 2, wallTop - roofRadius - stroke * 2, stroke, stroke * 3, CITY_INK)

  -- Visible sides of the front wall.
  fillMaskedRect(imageData, size, mask, x + stroke, wallTop + stroke, width - stroke * 2, wallHeight - stroke, CITY_PAPER)
  fillMaskedRect(imageData, size, mask, x, wallTop, stroke, wallHeight, CITY_INK)
  fillMaskedRect(imageData, size, mask, x + width - stroke, wallTop, stroke, wallHeight, CITY_INK)
end

local function drawMinaret(imageData, size, mask, centerX, baselineY, width, height, stroke)
  local left = centerX - width / 2
  local top = baselineY - height

  fillMaskedRect(imageData, size, mask, left - stroke, top - stroke, width + stroke * 2, height + stroke, CITY_INK)
  fillMaskedRect(imageData, size, mask, left, top, width, height, CITY_PAPER)

  -- Small cap and balcony.
  fillMaskedRect(imageData, size, mask, left - stroke * 2, top - stroke * 3, width + stroke * 4, stroke * 2, CITY_INK)
  fillMaskedCircle(imageData, size, mask, centerX, top - stroke * 2, width * 0.9, CITY_INK)
  fillMaskedCircle(imageData, size, mask, centerX, top - stroke * 2, width * 0.9 - stroke, CITY_PAPER)
end

local function drawMosque(imageData, size, mask, centerX, baselineY, stroke)
  local width = 24 * CITY_SCALE
  local wallHeight = 9 * CITY_SCALE
  local wallTop = baselineY - wallHeight
  local x = centerX - width / 2
  local domeRadius = width * 0.5

  -- Big dome.
  fillMaskedCircle(imageData, size, mask, centerX, wallTop, domeRadius, CITY_INK)
  fillMaskedCircle(imageData, size, mask, centerX, wallTop, domeRadius - stroke, CITY_PAPER)
  fillMaskedRect(
    imageData,
    size,
    mask,
    centerX - stroke / 2,
    wallTop - domeRadius - stroke * 3,
    stroke,
    stroke * 4,
    CITY_INK
  )

  -- Wall: only the sides are painted, the front row covers the bottom.
  fillMaskedRect(imageData, size, mask, x, wallTop, width, wallHeight, CITY_PAPER)
  fillMaskedRect(imageData, size, mask, x, wallTop, stroke, wallHeight, CITY_INK)
  fillMaskedRect(imageData, size, mask, x + width - stroke, wallTop, stroke, wallHeight, CITY_INK)

  -- Minaret beside it.
  drawMinaret(
    imageData,
    size,
    mask,
    x + width + 4 * CITY_SCALE,
    baselineY,
    3 * CITY_SCALE,
    26 * CITY_SCALE,
    stroke
  )
end

local function paintCityWall(imageData, size, isLand, cityAmount, distance, pixelsPerTile)
  for py = 0, size - 1 do
    for px = 0, size - 1 do
      if isLand[py][px] and cityAmount[py][px] > 0.3 then
        local d = distance[py][px] / pixelsPerTile

        -- Which way does the wall run here? Horizontal walls repeat along x,
        -- vertical walls repeat along y.
        local left = distance[py][math.max(px - 1, 0)]
        local right = distance[py][math.min(px + 1, size - 1)]
        local up = distance[math.max(py - 1, 0)][px]
        local down = distance[math.min(py + 1, size - 1)][px]

        local gradientX = right - left
        local gradientY = down - up

        local along
        if math.abs(gradientX) > math.abs(gradientY) then
          along = py
        else
          along = px
        end

        local inTower = (along % TOWER_SPACING) < TOWER_WIDTH
        local wallDepth = inTower and (WALL_WIDTH + TOWER_DEPTH) or WALL_WIDTH

        if d > OUTLINE_WIDTH and d <= wallDepth then
          imageData:setPixel(px, py, CITY_PAPER[1], CITY_PAPER[2], CITY_PAPER[3], 1)
        end

        -- Dark line along the city side of the wall, following tower tops too.
        if d > wallDepth - WALL_LINE_WIDTH and d <= wallDepth + 0.004 then
          imageData:setPixel(px, py, CITY_INK[1], CITY_INK[2], CITY_INK[3], 1)
        end

        -- Crenellations (merlons) poking out of the city side of the wall.
        if d > wallDepth and d <= wallDepth + MERLON_DEPTH
          and (along % MERLON_SPACING) < MERLON_WIDTH then
          imageData:setPixel(px, py, CITY_INK[1], CITY_INK[2], CITY_INK[3], 1)
        end
      end
    end
  end
end

local function paintCityBuildings(imageData, size, isCity, canBuild, centerX, centerY)
  local random = love.math.newRandomGenerator(2024)

  local spacingX = 8.5 * CITY_SCALE
  local rowSpacing = 5.5 * CITY_SCALE
  local stroke = 1
  local jitter = 2.5 * CITY_SCALE

  local mosqueDrawn = false

  for row = 0, math.ceil(size / rowSpacing) do
    local offset = (row % 2) * spacingX / 2

    for column = 0, math.ceil(size / spacingX) do
      local width = (8 + random:random() * 6) * CITY_SCALE
      local wallHeight = (3 + random:random() * 2) * CITY_SCALE
      local roofHeight = (4 + random:random() * 3) * CITY_SCALE

      local x = column * spacingX + offset + (random:random() - 0.5) * jitter
      local baselineY = row * rowSpacing + (random:random() - 0.5) * jitter
      local roofTop = baselineY - wallHeight - roofHeight
      local cellX = math.floor(x + width / 2)
      local topY = math.floor(roofTop)

      local inside = cellX >= 0 and cellX < size and topY >= 0 and topY < size
        and isCity[topY][cellX]
        and canBuild[math.floor(baselineY)][cellX]

      if inside then
        if not mosqueDrawn and centerX and centerY
          and math.abs(cellX - centerX) < spacingX
          and math.abs(baselineY - centerY) < rowSpacing then
          mosqueDrawn = true
          drawMosque(imageData, size, canBuild, cellX, baselineY, stroke)
        else
          local roll = random:random()

          if roll < 0.06 then
            -- A minaret rising out of the roofs.
            drawMinaret(
              imageData,
              size,
              canBuild,
              x + width / 2,
              baselineY,
              2.5 * CITY_SCALE,
              (13 + random:random() * 6) * CITY_SCALE,
              stroke
            )
          elseif roll < 0.13 then
            drawDomeHouse(
              imageData,
              size,
              canBuild,
              x,
              baselineY,
              width,
              wallHeight,
              width * 0.42,
              stroke
            )
          else
            drawHouse(
              imageData,
              size,
              canBuild,
              x,
              baselineY,
              width,
              wallHeight,
              roofHeight,
              width * (0.15 + random:random() * 0.35),
              stroke
            )
          end
        end
      end
    end
  end
end

local function buildMapImage(size)
  local imageData = love.image.newImageData(size, size)

  local fieldWidth = #tiles[1]
  local fieldHeight = #tiles

  local isLand = {}
  local isCity = {}
  local cityAmount = {}
  local canBuild = {}
  local distance = {}

  local infinity = 1e9

  -- First pass: decide whether every pixel is land or water.
  for py = 0, size - 1 do
    isLand[py] = {}
    isCity[py] = {}
    cityAmount[py] = {}
    canBuild[py] = {}
    distance[py] = {}

    for px = 0, size - 1 do
      local u = (px + 0.5) / size * fieldWidth
      local v = (py + 0.5) / size * fieldHeight

      local land = fieldAt(u, v) >= 0.5
      local city = cityAt(u, v)

      isLand[py][px] = land
      cityAmount[py][px] = city
      isCity[py][px] = land and city >= 0.4
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

  -- Buildings sit behind the wall, never on it or in the water.
  for py = 0, size - 1 do
    for px = 0, size - 1 do
      local distanceInTiles = distance[py][px] / pixelsPerTile

      canBuild[py][px] = isLand[py][px] and distanceInTiles >= BUILDING_MARGIN

      if isCity[py][px] and not canBuild[py][px] then
        isCity[py][px] = false
      end
    end
  end

  -- Fourth pass: paint the terrain using the distance to the shoreline.
  for py = 0, size - 1 do
    for px = 0, size - 1 do
      local distanceInTiles = distance[py][px] / pixelsPerTile

      local r, g, b

      if isLand[py][px] then
        local t = smoothstep(0, SHORE_RANGE, distanceInTiles)
        r = mix(SHORE_LAND[1], INLAND[1], t)
        g = mix(SHORE_LAND[2], INLAND[2], t)
        b = mix(SHORE_LAND[3], INLAND[3], t)

        -- Off-white ground under the city, kept away from the shoreline.
        local cityTint = smoothstep(0.25, 0.65, cityAmount[py][px])
          * smoothstep(0.02, 0.12, distanceInTiles)
          * 0.95

        r = mix(r, CITY_PAPER[1], cityTint)
        g = mix(g, CITY_PAPER[2], cityTint)
        b = mix(b, CITY_PAPER[3], cityTint)
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

  paintCityWall(imageData, size, isLand, cityAmount, distance, pixelsPerTile)

  local citySumX = 0
  local citySumY = 0
  local cityCount = 0

  for py = 0, size - 1 do
    for px = 0, size - 1 do
      if isCity[py][px] then
        citySumX = citySumX + px
        citySumY = citySumY + py
        cityCount = cityCount + 1
      end
    end
  end

  local cityCenterX = nil
  local cityCenterY = nil

  if cityCount > 0 then
    cityCenterX = citySumX / cityCount
    cityCenterY = citySumY / cityCount
  end

  paintCityBuildings(imageData, size, isCity, canBuild, cityCenterX, cityCenterY)

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
