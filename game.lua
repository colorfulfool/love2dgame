game = {}

local playerX = 700
local playerY = 100

local tiles = {
  { 0, 0, 0, 0, 1 },
  { 0, 1, 1, 0, 1 },
  { 0, 1, 0, 0, 1 },
  { 0, 1, 1, 1, 1 },
  { 0, 1, 1, 1, 1 },
}

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

  local playerCellIndex = math.floor(playerCenterX / tileWidth + 1)
  local playerRowIndex = math.floor(playerCenterY / tileHeight + 1)

  for rowIndex, row in pairs(tiles) do
    for cellIndex, cell in pairs(row) do
      local b = 1

      if rowIndex == playerRowIndex and cellIndex == playerCellIndex then
        b = 1.2
      end

      if cell == 0 then 
        love.graphics.setColor({ 0.7 * b, 0.6 * b, 0 * b })
      end

      if cell == 1 then 
        love.graphics.setColor({ 0 * b, 0.3 * b, 0.5 * b })
      end

      love.graphics.rectangle(
        "fill", 
        (cellIndex-1)*tileWidth,
        (rowIndex-1)*tileHeight,
        tileWidth,
        tileHeight
      )
    end
  end

  love.graphics.setColor({ 0, 0, 0, 0.2 })
  love.graphics.rectangle("fill", playerX + 10, playerY + 10, playerWidth, playerHeight)

  love.graphics.setColor({ 1, 1, 1 })
  love.graphics.rectangle("fill", playerX, playerY, playerWidth, playerHeight)
end

return game
