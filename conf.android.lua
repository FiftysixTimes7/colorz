-- conf.android.lua
-- Android-specific configuration for Color Lines game

function love.conf(t)
    -- Enforce portrait mode
    t.window.width = 1080
    t.window.height = 1920
end
