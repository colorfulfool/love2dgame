local lurker = require("libs.lurker")

lurker.quiet = true -- print errors instead of freezing the game

local game = require("game")

function love.update(dt)
  lurker.update() -- poll for changed .lua files (every 0.5s)
  game.update(dt)
end

function love.draw()
  game.draw()
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
end

