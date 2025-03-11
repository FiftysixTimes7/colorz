-- conf.lua
-- Desktop-specific configuration for Color Lines game
-- Note: This file is not used for Android builds

function love.conf(t)
    -- Basic window configuration
    t.window.title = "Colorz"
    
    -- Set the window icon
    t.window.icon = "ball_icon.png"  -- Remove the OS check since we want it on all desktop platforms
    
    -- Calculate minimum window size based on game board requirements
    local minCellSize = 40  -- Minimum comfortable cell size in pixels
    local minWidth = math.ceil((9 * minCellSize) / 0.9)  -- 90% width usage for board
    local minHeight = math.ceil((9 * minCellSize) / 0.65) -- 65% height usage for board
    
    -- Set window properties
    t.window.width = minWidth
    t.window.height = minHeight
    t.window.resizable = true
    t.window.minwidth = minWidth
    t.window.minheight = minHeight
end
