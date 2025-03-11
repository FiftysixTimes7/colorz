------------------------------------------------------------
-- main.lua
------------------------------------------------------------
--[[ 
    Color Lines – LOVE2D Refactored

    Features & Mechanics (unchanged):
      • Move a ball if a valid path exists.
      • Generate new balls if no chain is formed.
      • Remove chains (5+ balls) and award points.
      • Preview zone shows next balls.
      • Current and Best score bars.
      • Restart button with confirmation dialog.
      • Eye button toggles preview.
      • Undo button for last move.
      • Smooth ball animations.
      • State persistence across sessions.
      • Cross-platform support (Desktop & Android)

    Refactoring goals:
      • Better overall design and organization.
      • Group helper routines by purpose.
      • Remove code redundancy.
      • Lower resource overhead where possible.
      
    All code is self contained in one file.
--]]

------------------------------------------------------------
-- CONFIGURATION & CONSTANTS
------------------------------------------------------------
local BOARD_SIZE       = 9
local NEW_BALLS_COUNT  = 3
local SAVE_FILE        = "colorz_save.lua"
local FADE_DURATION    = 0.1      -- fade out in seconds
local FADE_IN_DURATION = 0.2      -- fade in animation in seconds

local BG_COLOR         = { r = 169/255, g = 170/255, b = 169/255 }  -- background cell color

local COLORS = {
    { r = 1,   g = 0,   b = 0   },  -- red
    { r = 0,   g = 1,   b = 0   },  -- green
    { r = 0,   g = 0,   b = 1   },  -- blue
    { r = 1,   g = 1,   b = 0   },  -- yellow
    { r = 1,   g = 0,   b = 1   },  -- magenta
    { r = 0,   g = 1,   b = 1   }   -- cyan
}

------------------------------------------------------------
-- STATE & UI LAYOUT (calculated later)
------------------------------------------------------------
local board, selected, movingBall
local nextBalls = {}
local score, bestScore = 0, 0
local combo, lastCombo = 0, 0
local lastBoardState, lastScore, canUndo = nil, 0, false
local gameOver = false

-- Animation lists for fading effects
local fadingBalls, fadingInBalls = {}, {}
local previewVisible = true
local showingRestartConfirmation = false

-- UI geometry (calculated in calculateSizes)
local CELL_SIZE, BOARD_OFFSET_X, BOARD_OFFSET_Y
local RESTART_BUTTON, PROGRESS_BAR, BEST_BAR, EYE_BUTTON, UNDO_BUTTON, DIALOG_LAYOUT

------------------------------------------------------------
-- UTILITY FUNCTIONS
------------------------------------------------------------
local function sameColor(c1, c2)
    return c1.r==c2.r and c1.g==c2.g and c1.b==c2.b
end

-- Table serialization used for saving game state.
local function serializeTable(val, name, skipnewlines, depth)
    skipnewlines = skipnewlines or false
    depth = depth or 0
    local tmp = string.rep("  ", depth)
    if name then 
        tmp = tmp .. (type(name)=="number" and ("[" .. name .. "] = ") or (name .. " = "))
    end
    if type(val)=="table" then
        tmp = tmp .. "{" .. (skipnewlines and "" or "\n")
        for k, v in pairs(val) do
            tmp = tmp .. serializeTable(v, k, skipnewlines, depth+1) .. "," .. (skipnewlines and "" or "\n")
        end
        tmp = tmp .. string.rep("  ", depth) .. "}"
    elseif type(val)=="number" then
        tmp = tmp .. tostring(val)
    elseif type(val)=="string" then
        tmp = tmp .. string.format("%q", val)
    elseif type(val)=="boolean" then
        tmp = tmp .. (val and "true" or "false")
    else
        tmp = tmp .. "nil"
    end
    return tmp
end

------------------------------------------------------------
-- STATE MANAGEMENT
------------------------------------------------------------
local function createEmptyBoard()
    local b = {}
    for i = 1, BOARD_SIZE do
        b[i] = {}
        for j = 1, BOARD_SIZE do
            b[i][j] = nil
        end
    end
    return b
end

local function storeBoard(b)
    local t = {}
    for i = 1, BOARD_SIZE do
        t[i] = {}
        for j = 1, BOARD_SIZE do
            if b[i][j] then
                t[i][j] = { color = { r = b[i][j].color.r, g = b[i][j].color.g, b = b[i][j].color.b } }
            end
        end
    end
    return t
end

local function loadBoard(target, src)
    if not src then return end
    for i = 1, BOARD_SIZE do
        if src[i] then
            for j = 1, BOARD_SIZE do
                if src[i][j] and src[i][j].color then
                    target[i][j] = { color = { r = src[i][j].color.r, g = src[i][j].color.g, b = src[i][j].color.b } }
                else
                    target[i][j] = nil
                end
            end
        end
    end
end

local function resetGameState()
    board = createEmptyBoard()
    score = 0
    combo = 0
    gameOver = false
    selected = nil
    movingBall = nil
    lastBoardState = nil
    lastScore = 0
    lastCombo = 0
    canUndo = false
    fadingBalls, fadingInBalls = {}, {}
    showingRestartConfirmation = false
end

local function generateNextBalls()
    local preview = {}
    for i=1,NEW_BALLS_COUNT do
        preview[i] = { color = COLORS[ math.random(#COLORS) ] }
    end
    return preview
end

local function addRandomBalls(n)
    local empties = {}
    for i=1,BOARD_SIZE do
        for j=1,BOARD_SIZE do
            if board[i][j] == nil then
                table.insert(empties, { i, j })
            end
        end
    end
    while n>0 and #empties>0 do
        local idx = math.random(#empties)
        local cell = empties[idx]
        local newBall = { color = COLORS[ math.random(#COLORS) ] }
        board[cell[1]][cell[2]] = newBall
        table.insert(fadingInBalls, { row = cell[1], col = cell[2], color = newBall.color, alpha=0, timer=0 })
        table.remove(empties, idx)
        n = n - 1
    end
end

local function applyPreviewBalls()
    for i=1, #nextBalls do
        local empties = {}
        for r=1, BOARD_SIZE do
            for c=1, BOARD_SIZE do
                if board[r][c] == nil then table.insert(empties, { r, c }) end
            end
        end
        if #empties == 0 then break end
        local idx = math.random(#empties)
        local cell = empties[idx]
        local newBall = { color = nextBalls[i].color }
        board[cell[1]][cell[2]] = newBall
        table.insert(fadingInBalls, { row = cell[1], col = cell[2], color = newBall.color, alpha=0, timer=0 })
    end
    nextBalls = generateNextBalls()
end

local function isBoardFull()
    for i=1, BOARD_SIZE do
        for j=1, BOARD_SIZE do
            if board[i][j] == nil then return false end
        end
    end
    return true
end

local function saveGameState()
    local state = {
        board = storeBoard(board),
        lastBoardState = lastBoardState and storeBoard(lastBoardState) or nil,
        nextBalls = {},
        score = score,
        bestScore = bestScore,
        combo = combo,
        lastCombo = lastCombo,
        previewVisible = previewVisible,
        randomSeed = love.math.getRandomSeed(),
        lastScore = lastScore,
        canUndo = canUndo
    }
    for i=1, #nextBalls do
        if nextBalls[i] and nextBalls[i].color then
            state.nextBalls[i] = { color = { r = nextBalls[i].color.r, g = nextBalls[i].color.g, b = nextBalls[i].color.b } }
        end
    end
    local serialized = "return " .. serializeTable(state)
    love.filesystem.write(SAVE_FILE, serialized)
end

local function loadGameState()
    resetGameState()
    if not love.filesystem.getInfo(SAVE_FILE) then return false end
    local chunk = love.filesystem.load(SAVE_FILE)
    if not chunk then return false end
    local success, state = pcall(chunk)
    if not success or type(state)~='table' then return false end

    loadBoard(board, state.board)
    if state.lastBoardState then 
        lastBoardState = createEmptyBoard()
        loadBoard(lastBoardState, state.lastBoardState)
    end
    nextBalls = {}
    if type(state.nextBalls)=='table' then
        for i=1, math.min(#state.nextBalls, NEW_BALLS_COUNT) do
            local nb = state.nextBalls[i]
            if nb and nb.color then
                nextBalls[i] = { color = { r = nb.color.r, g = nb.color.g, b = nb.color.b } }
            end
        end
    end
    score = (type(state.score)=='number') and state.score or 0
    bestScore = (type(state.bestScore)=='number') and state.bestScore or 0
    combo = (type(state.combo)=='number') and state.combo or 0
    lastCombo = (type(state.lastCombo)=='number') and state.lastCombo or 0
    if type(state.previewVisible) == "boolean" then
        previewVisible = state.previewVisible
    else
        previewVisible = true
    end
    if type(state.randomSeed)=='number' then love.math.setRandomSeed(state.randomSeed) end
    lastScore = (type(state.lastScore)=='number') and state.lastScore or 0
    if type(state.canUndo) == "boolean" then
        canUndo = state.canUndo
    else
        canUndo = false
    end

    while #nextBalls < NEW_BALLS_COUNT do
        table.insert(nextBalls, { color = COLORS[ math.random(#COLORS) ] })
    end
    return true
end

local function newGame()
    resetGameState()
    addRandomBalls(NEW_BALLS_COUNT)
    nextBalls = generateNextBalls()
    saveGameState()
end

------------------------------------------------------------
-- PATH FINDING (Breadth-First Search)
------------------------------------------------------------
local function findPath(sr, sc, tr, tc)
    local queue, visited, prev = {}, {}, {}
    for i=1, BOARD_SIZE do
        visited[i], prev[i] = {}, {}
        for j=1, BOARD_SIZE do
            visited[i][j] = false
            prev[i][j] = nil
        end
    end
    table.insert(queue, { sr, sc })
    visited[sr][sc] = true
    local directions = { {1,0}, {-1,0}, {0,1}, {0,-1} }
    while #queue > 0 do
        local pos = table.remove(queue, 1)
        local r,c = pos[1], pos[2]
        if r==tr and c==tc then
            local path = {}
            local cr, cc = r, c
            while true do
                table.insert(path, 1, { row = cr, col = cc })
                if cr==sr and cc==sc then break end
                local p = prev[cr][cc]
                cr, cc = p[1], p[2]
            end
            return path
        end
        for _, d in ipairs(directions) do
            local nr, nc = r + d[1], c + d[2]
            if nr>=1 and nr<=BOARD_SIZE and nc>=1 and nc<=BOARD_SIZE and 
               (not visited[nr][nc]) and (board[nr][nc]==nil) then
                visited[nr][nc] = true
                prev[nr][nc] = { r, c }
                table.insert(queue, {nr, nc})
            end
        end
    end
    return nil
end

------------------------------------------------------------
-- CHAIN DETECTION, REMOVAL & SCORING
------------------------------------------------------------
local function checkChains()
    local toRemove = {}
    local totalScore = 0
    local chainCount = 0
    local directions = {
        {1, 0},   -- horizontal
        {0, 1},   -- vertical
        {1, 1},   -- diag down-right
        {1, -1}   -- diag up-right
    }
    for i=1, BOARD_SIZE do
        for j=1, BOARD_SIZE do
            if board[i][j] then
                local ballColor = board[i][j].color
                for _, d in ipairs(directions) do
                    local dr, dc = d[1], d[2]
                    local prevR, prevC = i - dr, j - dc
                    if (prevR < 1 or prevR > BOARD_SIZE or prevC < 1 or prevC > BOARD_SIZE or 
                        not board[prevR][prevC] or 
                        not sameColor(board[prevR][prevC].color, ballColor)) then
                        local chain = {}
                        local r, c = i, j
                        while r>=1 and r<=BOARD_SIZE and c>=1 and c<=BOARD_SIZE and 
                              board[r][c] and sameColor(board[r][c].color, ballColor) do
                            table.insert(chain, { r, c })
                            r, c = r+dr, c+dc
                        end
                        if #chain >= 5 then
                            -- Use the original game's scoring formula: 10 + 2 * (N-5)^2
                            local chainScore = 10 + 2 * ((#chain - 5) ^ 2)
                            totalScore = totalScore + chainScore
                            chainCount = chainCount + 1
                            
                            for _, pos in ipairs(chain) do
                                toRemove[pos[1] .. '-' .. pos[2]] = pos
                            end
                        end
                    end
                end
            end
        end
    end

    for _, pos in pairs(toRemove) do
        if board[pos[1]][pos[2]] then
            table.insert(fadingBalls, { row = pos[1], col = pos[2], color = board[pos[1]][pos[2]].color, alpha = 1.0, timer = FADE_DURATION })
            board[pos[1]][pos[2]] = nil
        end
    end
    return totalScore, chainCount
end

------------------------------------------------------------
-- UI & LAYOUT CALCULATIONS 
------------------------------------------------------------
local function calculateDialogLayout()
    local dlgWidth = BOARD_SIZE * CELL_SIZE * 0.8
    local dlgHeight = 100
    local dlgX = (love.graphics.getWidth() - dlgWidth) / 2
    local dlgY = (love.graphics.getHeight() - dlgHeight) / 2
    DIALOG_LAYOUT = {
        x = dlgX, y = dlgY, width = dlgWidth, height = dlgHeight,
        buttons = {
            yes = { x = dlgX + 20, y = dlgY + dlgHeight - 40, width = (dlgWidth - 60)/2, height = 30 },
            no  = { x = dlgX + 40 + (dlgWidth - 60)/2, y = dlgY + dlgHeight - 40, width = (dlgWidth - 60)/2, height = 30 }
        }
    }
end

local function calculateSizes()
    local winW, winH = love.graphics.getDimensions()
    if love.system.getOS() == "Android" then
        CELL_SIZE = math.floor((winW - 8) / BOARD_SIZE)
        BOARD_OFFSET_X = math.floor((winW - BOARD_SIZE * CELL_SIZE) / 2)
        BOARD_OFFSET_Y = math.floor(winH * 0.25)
    else
        local maxCellWidth  = (winW * 0.9) / BOARD_SIZE
        local maxCellHeight = (winH * 0.65) / BOARD_SIZE
        CELL_SIZE = math.floor(math.min(maxCellWidth, maxCellHeight))
        BOARD_OFFSET_X = math.floor((winW - BOARD_SIZE * CELL_SIZE) / 2)
        BOARD_OFFSET_Y = math.floor(winH * 0.15)
    end
    local eyeSize = CELL_SIZE * 0.8
    EYE_BUTTON = { x = BOARD_OFFSET_X, y = BOARD_OFFSET_Y - CELL_SIZE * 1.5, width = eyeSize, height = eyeSize }
    UNDO_BUTTON = { x = BOARD_OFFSET_X + BOARD_SIZE * CELL_SIZE - eyeSize, y = BOARD_OFFSET_Y - CELL_SIZE * 1.5, width = eyeSize, height = eyeSize }
    RESTART_BUTTON = { x = BOARD_OFFSET_X, y = BOARD_OFFSET_Y + BOARD_SIZE * CELL_SIZE + math.floor(CELL_SIZE * 0.25), width = BOARD_SIZE * CELL_SIZE, height = math.floor(CELL_SIZE * 0.8) }
    local barWidth = BOARD_SIZE * CELL_SIZE - 135
    local barHeight = math.floor(CELL_SIZE * 0.4)
    PROGRESS_BAR = { x = BOARD_OFFSET_X + BOARD_SIZE * CELL_SIZE - barWidth - 1, y = RESTART_BUTTON.y + RESTART_BUTTON.height + math.floor(CELL_SIZE * 0.25), width = barWidth, height = barHeight }
    BEST_BAR     = { x = PROGRESS_BAR.x, y = PROGRESS_BAR.y + PROGRESS_BAR.height + math.floor(CELL_SIZE * 0.25), width = barWidth, height = barHeight }
    calculateDialogLayout()
end

------------------------------------------------------------
-- DRAWING HELPERS
------------------------------------------------------------
local function drawButtonBevel(x, y, w, h, bevel)
    bevel = bevel or 3
    -- Draw a light bevel on top & left
    love.graphics.setColor(0.65, 0.65, 0.65, 0.6)
    love.graphics.polygon("fill",
         x, y,
         x+w, y,
         x+w-bevel, y+bevel,
         x+bevel, y+bevel)
    love.graphics.polygon("fill",
         x, y,
         x+bevel, y+bevel,
         x+bevel, y+h-bevel,
         x, y+h)
    -- Draw a dark bevel on bottom & right
    love.graphics.setColor(0.3, 0.3, 0.3, 0.8)
    love.graphics.polygon("fill",
         x+bevel, y+h-bevel,
         x+w-bevel, y+h-bevel,
         x+w, y+h,
         x, y+h)
    love.graphics.polygon("fill",
         x+w-bevel, y+bevel,
         x+w, y,
         x+w, y+h,
         x+w-bevel, y+h-bevel)
end

local function drawButton(btn, baseColor)
    -- Fill the button background
    love.graphics.setColor(baseColor.r, baseColor.g, baseColor.b)
    love.graphics.rectangle("fill", btn.x, btn.y, btn.width, btn.height)
    -- Draw the bevel effect (using drawButtonBevel)
    drawButtonBevel(btn.x, btn.y, btn.width, btn.height, 3)
    -- Draw the button outline
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle("line", btn.x, btn.y, btn.width, btn.height)
end

local function drawBall(x, y, radius, color, scaleX, scaleY)
    scaleX = scaleX or 1; scaleY = scaleY or 1
    local alpha = color.a or 1.0
    love.graphics.setLineWidth(1)
    love.graphics.setLineStyle('smooth')
    -- Layers from dark to bright with progressive offsets:
    local layers = {
        { mult = 0.4, offset = 0 },
        { mult = 0.5, offset = 0.05 },
        { mult = 0.65, offset = 0.1 },
        { mult = 0.8, offset = 0.15 },
        { mult = 0.95, offset = 0.2 },
        { mult = 1.0, offset = 0.25 }
    }
    for i, layer in ipairs(layers) do
        love.graphics.setColor(color.r * layer.mult, color.g * layer.mult, color.b * layer.mult, alpha)
        love.graphics.circle('fill', x - radius * layer.offset, y - radius * layer.offset, radius * (1 - 0.08*(i-1)))
    end
    love.graphics.setColor(1,1,1, 0.3 * alpha)
    love.graphics.circle('fill', x - radius * 0.3, y - radius * 0.3, radius * 0.2)
end

local function drawUndoIcon(x, y, w, h, enabled)
    local margin = math.min(w, h) * 0.15
    x, y, w, h = x+margin, y+margin, w-2*margin, h-2*margin
    if enabled then love.graphics.setColor(0.8,0.8,0.8)
    else love.graphics.setColor(0.5,0.5,0.5) end
    love.graphics.setLineWidth(2)
    local centerX, centerY = x + w/2, y + h/2
    local radius = math.min(w,h) * 0.35
    local segments = 32
    local startAngle, endAngle = math.pi * 0.25, math.pi * 1.75
    local arcPoints = {}
    for i=0, segments do
        local t = i/segments
        local angle = startAngle + (endAngle - startAngle) * t
        table.insert(arcPoints, centerX + radius * math.cos(angle))
        table.insert(arcPoints, centerY + radius * math.sin(angle))
    end
    love.graphics.line(arcPoints)
    local arrowSize = radius * 0.4
    local px = centerX + radius * math.cos(startAngle)
    local py = centerY + radius * math.sin(startAngle)
    love.graphics.line(px, py, px - arrowSize * 0.7, py - arrowSize * 0.7)
end

local function drawEyeIcon(x, y, w, h, closed)
    love.graphics.setColor(0.8, 0.8, 0.8)
    love.graphics.setLineWidth(2)
    local margin = math.min(w, h) * 0.15
    x, y, w, h = x+margin, y+margin, w-2*margin, h-2*margin
    if closed then
        local centerY = y+h/2
        love.graphics.line(x, centerY, x+w, centerY)
        for i=0,2 do
            local lashX = x + w * i/2
            love.graphics.line(lashX, centerY, lashX - w/10, centerY - h/5)
            love.graphics.line(lashX, centerY, lashX - w/10, centerY + h/5)
        end
    else
        love.graphics.ellipse('line', x+w/2, y+h/2, (w/2)*0.9, (h/3)*0.9)
        love.graphics.circle('fill', x+w/2, y+h/2, h/7)
    end
end

local function drawRestartDialog()
    local dlg = DIALOG_LAYOUT
    local btnYes = dlg.buttons.yes
    local btnNo = dlg.buttons.no
    love.graphics.setColor(0,0,0,0.7)
    love.graphics.rectangle('fill', dlg.x, dlg.y, dlg.width, dlg.height)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle('line', dlg.x, dlg.y, dlg.width, dlg.height)
    love.graphics.printf('Are you sure you want to restart?', dlg.x, dlg.y+10, dlg.width, 'center')
    love.graphics.setColor(0.3,0.8,0.3)
    love.graphics.rectangle('fill', btnYes.x, btnYes.y, btnYes.width, btnYes.height)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle('line', btnYes.x, btnYes.y, btnYes.width, btnYes.height)
    love.graphics.printf('Yes', btnYes.x, btnYes.y+5, btnYes.width, 'center')
    love.graphics.setColor(0.8,0.3,0.3)
    love.graphics.rectangle('fill', btnNo.x, btnNo.y, btnNo.width, btnNo.height)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle('line', btnNo.x, btnNo.y, btnNo.width, btnNo.height)
    love.graphics.printf('No', btnNo.x, btnNo.y+5, btnNo.width, 'center')
end

------------------------------------------------------------
-- LOVE2D DRAW CALLBACK
------------------------------------------------------------
function love.draw()
    local font = love.graphics.getFont()
    local bevel = 3

    -- Draw eye button
    drawButton(EYE_BUTTON, { r = 0.5, g = 0.5, b = 0.5 })
    drawEyeIcon(EYE_BUTTON.x+bevel, EYE_BUTTON.y+bevel, EYE_BUTTON.width-2*bevel, EYE_BUTTON.height-2*bevel, not previewVisible)

    -- Draw undo button
    drawButton(UNDO_BUTTON, { r = 0.5, g = 0.5, b = 0.5 })
    drawUndoIcon(UNDO_BUTTON.x+bevel, UNDO_BUTTON.y+bevel, UNDO_BUTTON.width-2*bevel, UNDO_BUTTON.height-2*bevel, canUndo)

    -- Draw preview bar if enabled
    if previewVisible then
        local previewSpacing = 10
        local previewTotalWidth = NEW_BALLS_COUNT * CELL_SIZE + (NEW_BALLS_COUNT-1)*previewSpacing
        local previewX = (love.graphics.getWidth() - previewTotalWidth) / 2
        local previewY = BOARD_OFFSET_Y - CELL_SIZE*1.5
        for i=1, #nextBalls do
            local ball = nextBalls[i]
            if ball and ball.color then
                local cx = previewX + (i-1)*(CELL_SIZE+previewSpacing) + CELL_SIZE/2
                local cy = previewY + CELL_SIZE/2
                drawBall(cx, cy, CELL_SIZE/2-5, ball.color)
            end
        end
    end

    -- Draw board cells (first pass: background and bevels)
    for i=1,BOARD_SIZE do
        for j=1,BOARD_SIZE do
            local x = BOARD_OFFSET_X + (j-1)*CELL_SIZE
            local y = BOARD_OFFSET_Y + (i-1)*CELL_SIZE
            love.graphics.setColor(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b)
            love.graphics.rectangle('fill', x, y, CELL_SIZE, CELL_SIZE)
            -- Draw bevels: lighter top/left and darker bottom/right
            love.graphics.setColor(math.min(BG_COLOR.r*1.3,1), math.min(BG_COLOR.g*1.3,1), math.min(BG_COLOR.b*1.3,1))
            love.graphics.polygon('fill', x, y, x+CELL_SIZE, y, x+CELL_SIZE-bevel, y+bevel, x+bevel, y+bevel)
            love.graphics.polygon('fill', x, y, x+bevel, y+bevel, x+bevel, y+CELL_SIZE-bevel, x, y+CELL_SIZE)
            love.graphics.setColor(BG_COLOR.r*0.6, BG_COLOR.g*0.6, BG_COLOR.b*0.6)
            love.graphics.polygon('fill', x+bevel, y+CELL_SIZE-bevel, x+CELL_SIZE-bevel, y+CELL_SIZE-bevel, x+CELL_SIZE, y+CELL_SIZE, x, y+CELL_SIZE)
            love.graphics.polygon('fill', x+CELL_SIZE-bevel, y+bevel, x+CELL_SIZE, y, x+CELL_SIZE, y+CELL_SIZE, x+CELL_SIZE-bevel, y+CELL_SIZE-bevel)
        end
    end

    -- Draw grid lines
    love.graphics.setColor(0,0,0)
    love.graphics.setLineWidth(1)
    for i=1,BOARD_SIZE do
        for j=1,BOARD_SIZE do
            local x = BOARD_OFFSET_X + (j-1)*CELL_SIZE
            local y = BOARD_OFFSET_Y + (i-1)*CELL_SIZE
            love.graphics.rectangle('line', x, y, CELL_SIZE, CELL_SIZE)
        end
    end

    -- Draw balls from board, skipping those still in fade-in
    for i=1,BOARD_SIZE do
        for j=1,BOARD_SIZE do
            if board[i][j] and board[i][j].color then
                local x = BOARD_OFFSET_X + (j-1)*CELL_SIZE
                local y = BOARD_OFFSET_Y + (i-1)*CELL_SIZE
                local skip = false
                for _, fb in ipairs(fadingInBalls) do
                    if fb.row==i and fb.col==j then skip = true break end
                end
                if not skip then
                    local centerX, centerY = x+CELL_SIZE/2, y+CELL_SIZE/2
                    local radius = CELL_SIZE/2-5
                    if selected and selected.row==i and selected.col==j then
                        local squash = 0.90 + 0.10*math.cos(selected.bounceTimer)
                        local stretch = math.min(1/squash, 1.10)
                        love.graphics.push()
                        love.graphics.translate(centerX, centerY+radius)
                        love.graphics.scale(stretch, squash)
                        drawBall(0, -radius, radius, board[i][j].color)
                        love.graphics.pop()
                    else
                        drawBall(centerX, centerY, CELL_SIZE/2-5, board[i][j].color)
                    end
                end
            end
        end
    end

    -- Draw fading out balls
    for _, ball in ipairs(fadingBalls) do
        local x = BOARD_OFFSET_X + (ball.col-1)*CELL_SIZE
        local y = BOARD_OFFSET_Y + (ball.row-1)*CELL_SIZE
        drawBall(x+CELL_SIZE/2, y+CELL_SIZE/2, CELL_SIZE/2-5, { r = ball.color.r, g = ball.color.g, b = ball.color.b, a = ball.alpha })
    end
    -- Draw fading in balls
    for _, ball in ipairs(fadingInBalls) do
        local x = BOARD_OFFSET_X + (ball.col-1)*CELL_SIZE
        local y = BOARD_OFFSET_Y + (ball.row-1)*CELL_SIZE
        drawBall(x+CELL_SIZE/2, y+CELL_SIZE/2, CELL_SIZE/2-5, { r = ball.color.r, g = ball.color.g, b = ball.color.b, a = ball.alpha })
    end

    -- Draw moving ball if any
    if movingBall and movingBall.ball and movingBall.path and movingBall.currentIndex then
        local idx = movingBall.currentIndex
        local pos1 = movingBall.path[idx]
        local pos2 = movingBall.path[idx+1] or pos1
        if pos1 and pos2 then
            local t = movingBall.timer / movingBall.cellSpeed
            local cx1 = BOARD_OFFSET_X + (pos1.col - 0.5)*CELL_SIZE
            local cy1 = BOARD_OFFSET_Y + (pos1.row - 0.5)*CELL_SIZE
            local cx2 = BOARD_OFFSET_X + (pos2.col - 0.5)*CELL_SIZE
            local cy2 = BOARD_OFFSET_Y + (pos2.row - 0.5)*CELL_SIZE
            local cx = cx1*(1-t) + cx2*t
            local cy = cy1*(1-t) + cy2*t
            drawBall(cx, cy, CELL_SIZE/2-5, movingBall.ball.color)
        end
    end

    -- Draw game over message if needed
    if gameOver then
        local txt = "Game Over!"
        local tw = font:getWidth(txt)
        local th = font:getHeight(txt)
        local rectW, rectH = tw+20, th+20
        local rectX = (love.graphics.getWidth()-rectW)/2
        local rectY = (love.graphics.getHeight()-rectH)/2
        love.graphics.setColor(0,0,0,0.7)
        love.graphics.rectangle('fill', rectX, rectY, rectW, rectH, 5,5)
        love.graphics.setColor(1,1,1)
        love.graphics.printf(txt, rectX, rectY+10, rectW, 'center')
    end

    -- Draw restart button
    drawButton(RESTART_BUTTON, { r = 0.5, g = 0.5, b = 0.5 })
    love.graphics.setColor(1,1,1)
    love.graphics.printf("Restart", RESTART_BUTTON.x, RESTART_BUTTON.y+10, RESTART_BUTTON.width, "center")

    -- Draw score bars
    local currText = "Current Score: " .. score
    local bestText = "Best Score: " .. bestScore
    -- Current score bar
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle('fill', PROGRESS_BAR.x, PROGRESS_BAR.y, PROGRESS_BAR.width, PROGRESS_BAR.height)
    love.graphics.setColor(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b)
    local fraction = bestScore>0 and math.min(score/bestScore, 1) or 0
    love.graphics.rectangle('fill', PROGRESS_BAR.x, PROGRESS_BAR.y, PROGRESS_BAR.width*fraction, PROGRESS_BAR.height)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle('line', PROGRESS_BAR.x, PROGRESS_BAR.y, PROGRESS_BAR.width, PROGRESS_BAR.height)
    love.graphics.print(currText, PROGRESS_BAR.x - font:getWidth(currText) - 10, PROGRESS_BAR.y + (PROGRESS_BAR.height-font:getHeight())/2)

    -- Display combo counter on the progress bar if combo > 1
    if combo > 1 then
        local comboText = "x" .. combo
        love.graphics.setColor(1,1,0) -- Yellow color for combo
        love.graphics.print(comboText, PROGRESS_BAR.x + PROGRESS_BAR.width - font:getWidth(comboText) - 5, PROGRESS_BAR.y + (PROGRESS_BAR.height-font:getHeight())/2)
    end

    -- Best score bar
    love.graphics.setColor(0,0,0)
    love.graphics.rectangle('fill', BEST_BAR.x, BEST_BAR.y, BEST_BAR.width, BEST_BAR.height)
    love.graphics.setColor(BG_COLOR.r, BG_COLOR.g, BG_COLOR.b)
    love.graphics.rectangle('fill', BEST_BAR.x, BEST_BAR.y, BEST_BAR.width, BEST_BAR.height)
    love.graphics.setColor(1,1,1)
    love.graphics.rectangle('line', BEST_BAR.x, BEST_BAR.y, BEST_BAR.width, BEST_BAR.height)
    love.graphics.print(bestText, BEST_BAR.x - font:getWidth(bestText) - 10, BEST_BAR.y + (BEST_BAR.height-font:getHeight())/2)

    -- Draw restart confirmation dialog if active
    if showingRestartConfirmation then drawRestartDialog() end
end

------------------------------------------------------------
-- ANIMATION UPDATE (for fades and moving ball)
------------------------------------------------------------
function love.update(dt)
    if selected then
        selected.bounceTimer = (selected.bounceTimer + dt*15) % (2*math.pi)
    end

    -- Update fading out balls (reduce timer / alpha)
    for i = #fadingBalls, 1, -1 do
        local ball = fadingBalls[i]
        ball.timer = ball.timer - dt
        ball.alpha = ball.timer / FADE_DURATION
        if ball.timer <= 0 then table.remove(fadingBalls, i) end
    end

    -- Update fading in balls (increase timer / alpha)
    local allFadedIn = true
    for i = #fadingInBalls, 1, -1 do
        local ball = fadingInBalls[i]
        ball.timer = ball.timer + dt
        ball.alpha = math.min(ball.timer/FADE_IN_DURATION,1)
        if ball.timer < FADE_IN_DURATION then allFadedIn = false else table.remove(fadingInBalls,i) end
    end

    -- Update moving ball animation
    if movingBall and movingBall.path and movingBall.currentIndex then
        movingBall.timer = movingBall.timer + dt
        if movingBall.timer >= movingBall.cellSpeed then
            movingBall.timer = movingBall.timer - movingBall.cellSpeed
            movingBall.currentIndex = movingBall.currentIndex + 1
            if movingBall.currentIndex >= #movingBall.path then
                local dest = movingBall.path[#movingBall.path]
                if dest and movingBall.ball then
                    board[dest.row][dest.col] = movingBall.ball
                end
                movingBall = nil
                if #fadingInBalls == 0 then
                    local scoreGained, chainsRemoved = checkChains()
                    if scoreGained > 0 then
                        -- Increase combo by number of chains removed
                        combo = combo + chainsRemoved
                        -- Apply combo multiplier to the score
                        score = score + (scoreGained * combo)
                        if score > bestScore then bestScore = score end
                    else
                        -- Reset combo when no chains are formed by a move
                        combo = 0
                        applyPreviewBalls()
                    end
                end
                if isBoardFull() then gameOver = true end
                saveGameState()
            end
        end
    end

    if allFadedIn and #fadingInBalls==0 and #fadingBalls==0 and (not movingBall) then
        local scoreGained, chainsRemoved = checkChains()
        if chainsRemoved > 0 then 
            -- No score added here since this check happens after random ball generation,
            -- not as a result of player's move. Only chains created by player actions score points.
            saveGameState() 
        end
    end
end

------------------------------------------------------------
-- MOUSE & INPUT HANDLERS
------------------------------------------------------------
function love.mousepressed(x, y, button)
    -- If restart dialog is active, process its buttons only.
    if showingRestartConfirmation then
        local btnYes = DIALOG_LAYOUT.buttons.yes
        local btnNo  = DIALOG_LAYOUT.buttons.no
        if x>=btnYes.x and x<=btnYes.x+btnYes.width and y>=btnYes.y and y<=btnYes.y+btnYes.height then
            newGame(); showingRestartConfirmation = false; return
        elseif x>=btnNo.x and x<=btnNo.x+btnNo.width and y>=btnNo.y and y<=btnNo.y+btnNo.height then
            showingRestartConfirmation = false; return
        end
        return
    end

    -- Process UI buttons first.
    if x>=RESTART_BUTTON.x and x<=RESTART_BUTTON.x+RESTART_BUTTON.width and y>=RESTART_BUTTON.y and y<=RESTART_BUTTON.y+RESTART_BUTTON.height then
        if gameOver then newGame() 
        else showingRestartConfirmation = true end
        return
    end

    if x>=EYE_BUTTON.x and x<=EYE_BUTTON.x+EYE_BUTTON.width and y>=EYE_BUTTON.y and y<=EYE_BUTTON.y+EYE_BUTTON.height then
        previewVisible = not previewVisible
        saveGameState()
        return
    end

    if x>=UNDO_BUTTON.x and x<=UNDO_BUTTON.x+UNDO_BUTTON.width and y>=UNDO_BUTTON.y and y<=UNDO_BUTTON.y+UNDO_BUTTON.height and canUndo then
        if lastBoardState then
            local tempBoard, tempScore, tempCombo = board, score, combo
            board = lastBoardState
            score = lastScore
            combo = lastCombo
            lastBoardState, lastScore, lastCombo, canUndo = nil, 0, 0, false
            selected, movingBall = nil, nil
            fadingBalls, fadingInBalls = {}, {}
            math.randomseed(os.time())
            nextBalls = generateNextBalls()
            saveGameState()
        end
        return
    end

    if movingBall then return end  -- ignore board clicks while ball is moving

    if x < BOARD_OFFSET_X or y < BOARD_OFFSET_Y then return end
    local col = math.floor((x-BOARD_OFFSET_X)/CELL_SIZE) + 1
    local row = math.floor((y-BOARD_OFFSET_Y)/CELL_SIZE) + 1
    if row < 1 or row > BOARD_SIZE or col < 1 or col > BOARD_SIZE then return end

    if board[row][col] then
        selected = { row = row, col = col, bounceTimer = 0 }
    elseif selected then
        local path = findPath(selected.row, selected.col, row, col)
        if path then
            lastBoardState = createEmptyBoard()
            for i=1,BOARD_SIZE do
                for j=1,BOARD_SIZE do
                    if board[i][j] then
                        lastBoardState[i][j] = { color = { r = board[i][j].color.r, g = board[i][j].color.g, b = board[i][j].color.b } }
                    end
                end
            end
            lastScore = score
            lastCombo = combo
            canUndo = true
            local ball = board[selected.row][selected.col]
            board[selected.row][selected.col] = nil
            movingBall = { ball = ball, path = path, currentIndex = 1, timer = 0, cellSpeed = 0.03 }
            selected = nil
        else
            selected = nil
        end
    end
end

------------------------------------------------------------
-- LOVE2D LIFECYCLE CALLBACKS
------------------------------------------------------------
function love.load()
    math.randomseed(os.time())
    calculateSizes()
    if not loadGameState() then newGame() end
end

function love.resize(w, h) calculateSizes() end

function love.quit()
    if gameOver then newGame() end
    saveGameState()
end
