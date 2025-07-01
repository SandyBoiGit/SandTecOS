-- SandTecOS - Fallout Terminal Style OS for CC:Tweaked
-- Author: SandyBoi (modded by Qodo)
-- File: startup.lua

-- === CONFIGURATION ===
local OS_NAME = "SandTecOS"
local USERS_FILE = "/sandtecos_users"
local USERS_DIR = "/users"
local PALETTE = {
    bg = colors.black,
    fg = colors.lime,
    accent = colors.yellow,
    border = colors.green,
    error = colors.red,
    select = colors.orange
}
local SESSION_TIMEOUT = 300 -- seconds (5 minutes)

-- === GUI UTILS ===
local function clearScreen()
    term.setBackgroundColor(PALETTE.bg)
    term.setTextColor(PALETTE.fg)
    term.clear()
    term.setCursorPos(1,1)
end

local function drawClickableText(x, y, label, active)
    term.setCursorPos(x, y)
    term.setTextColor(active and PALETTE.select or PALETTE.fg)
    term.write(label)
    term.setTextColor(PALETTE.fg)
end

local function isInClickable(mx, my, x, y, label)
    return my == y and mx >= x and mx < x + #label
end

local function centerText(y, text, color)
    local w, _ = term.getSize()
    term.setCursorPos(math.floor((w - #text)/2)+1, y)
    if color then term.setTextColor(color) end
    term.write(text)
    term.setTextColor(PALETTE.fg)
end

local function inputBox(x, y, w, mask)
    term.setCursorPos(x, y)
    term.setBackgroundColor(PALETTE.bg)
    term.setTextColor(PALETTE.fg)
    local input = ""
    while true do
        term.setCursorPos(x, y)
        if mask then
            term.write(string.rep("*", #input) .. string.rep(" ", w-#input))
        else
            term.write(input .. string.rep(" ", w-#input))
        end
        local event, p1, p2, p3 = os.pullEvent()
        if event == "char" then
            -- Only allow printable ASCII characters (32-126)
            if #input < w and p1:match("^[%w%p%s]$") and #p1 == 1 and string.byte(p1) >= 32 and string.byte(p1) <= 126 then
                input = input .. p1
            end
        elseif event == "key" then
            if p1 == keys.enter then
                break
            elseif p1 == keys.backspace then
                if #input > 0 then
                    input = input:sub(1, -2)
                end
            end
        end
    end
    return input
end

-- === USER SYSTEM ===
local UserManager = {}

function UserManager.load()
    if not fs.exists(USERS_FILE) then return {} end
    local f = fs.open(USERS_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

function UserManager.save(users)
    local f = fs.open(USERS_FILE, "w")
    f.write(textutils.serialize(users))
    f.close()
end

function UserManager.hashPassword(password)
    if not password or password == "" then return "" end
    return string.reverse(password) .. "s@nd"
end

function UserManager.exists(users, username)
    for _, user in ipairs(users) do
        if user.name == username then return true end
    end
    return false
end

function UserManager.get(users, username)
    for _, user in ipairs(users) do
        if user.name == username then return user end
    end
    return nil
end

function UserManager.remove(users, username)
    for i, user in ipairs(users) do
        if user.name == username then
            table.remove(users, i)
            return true
        end
    end
    return false
end

function UserManager.setPassword(users, username, newPassword)
    for i, user in ipairs(users) do
        if user.name == username then
            users[i].pass = UserManager.hashPassword(newPassword)
            return true
        end
    end
    return false
end

function UserManager.setAdmin(users, username, isAdmin)
    for i, user in ipairs(users) do
        if user.name == username then
            users[i].admin = isAdmin and true or false
            return true
        end
    end
    return false
end

function UserManager.createUserDir(username)
    local userDir = fs.combine(USERS_DIR, username)
    if not fs.exists(USERS_DIR) then fs.makeDir(USERS_DIR) end
    if not fs.exists(userDir) then fs.makeDir(userDir) end
end

function UserManager.deleteUserDir(username)
    local userDir = fs.combine(USERS_DIR, username)
    if fs.exists(userDir) then
        local function recursiveDelete(path)
            if fs.isDir(path) then
                for _, f in ipairs(fs.list(path)) do
                    recursiveDelete(fs.combine(path, f))
                end
                fs.delete(path)
            else
                fs.delete(path)
            end
        end
        recursiveDelete(userDir)
    end
end

function UserManager.countAdmins(users)
    local count = 0
    for _, user in ipairs(users) do
        if user.admin then count = count + 1 end
    end
    return count
end

-- === TEXT EDITOR ===
local function textEditorScreen(filepath)
    local function safeSetCursorBlink(val)
        if term.setCursorBlink then
            pcall(term.setCursorBlink, val)
        end
    end

    local function safeSleep(t)
        if sleep then
            pcall(sleep, t)
        end
    end

    local function safeOpen(path, mode)
        local ok, f = pcall(fs.open, path, mode)
        if ok and f then return f end
        return nil
    end

    local function safeGetSize()
        local ok, w, h = pcall(term.getSize)
        if ok and w and h then return w, h end
        return 51, 19 -- fallback
    end

    local w, h = safeGetSize()
    local lines = {}
    local statusMsg = ""
    local statusColor = colors.lime

    -- Load file
    do
        local f = safeOpen(filepath, "r")
        if f then
            while true do
                local line = f.readLine()
                if not line then break end
                table.insert(lines, line)
            end
            f.close()
        end
    end
    if #lines == 0 then lines = {""} end

    local cursorX, cursorY = 1, 1
    local scroll = 0
    local editing = true

    -- Кнопки управления
    local saveLabel = "Save"
    local exitLabel = "Exit"
    local btnY = h-1
    local saveX = 4
    local exitX = saveX + #saveLabel + 6

    local function drawEditorButtons()
        drawClickableText(saveX, btnY, saveLabel, false)
        drawClickableText(exitX, btnY, exitLabel, false)
    end

    local function redraw()
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.lime)
        term.clear()
        term.setCursorPos(1,1)
        term.write("Text Editor - " .. filepath)
        -- Draw lines
        for i=1, h-3 do
            term.setCursorPos(1, i+1)
            local idx = i + scroll
            if lines[idx] then
                local line = lines[idx]
                -- Highlight cursor if this is the cursor line
                if idx == cursorY then
                    local before = line:sub(1, cursorX-1)
                    local curChar = line:sub(cursorX, cursorX)
                    if curChar == "" then curChar = " " end
                    local after = line:sub(cursorX+1)
                    -- Draw before cursor
                    term.setTextColor(colors.lime)
                    term.write(before)
                    -- Draw cursor (inverted colors)
                    term.setBackgroundColor(colors.lime)
                    term.setTextColor(colors.black)
                    term.write(curChar)
                    term.setBackgroundColor(colors.black)
                    term.setTextColor(colors.lime)
                    -- Draw after cursor
                    term.write(after)
                    -- Fill to end of line if needed
                    if #before + #curChar + #after < w then
                        term.write(string.rep(" ", w - (#before + #curChar + #after)))
                    end
                else
                    if #line > w then
                        term.write(line:sub(1, w))
                    else
                        term.write(line .. string.rep(" ", w - #line))
                    end
                end
            else
                term.write(string.rep(" ", w))
            end
        end
        -- Status bar
        term.setCursorPos(1, h-2)
        term.setTextColor(statusColor)
        term.write(statusMsg .. string.rep(" ", w - #statusMsg))
        term.setTextColor(colors.lime)
        -- Draw buttons
        drawEditorButtons()
        -- Cursor (set terminal cursor position for blinking if supported)
        local cx = cursorX
        local cy = cursorY - scroll
        local line = lines[cursorY] or ""
        if cx < 1 then cx = 1 end
        if cx > #line + 1 then cx = #line + 1 end
        if cy >= 1 and cy <= h-3 then
            term.setCursorPos(cx, cy+1)
            safeSetCursorBlink(true)
        else
            safeSetCursorBlink(false)
        end
    end

    local function setStatus(msg, color)
        statusMsg = msg or ""
        statusColor = color or colors.lime
    end

    local function saveFile()
        local f = safeOpen(filepath, "w")
        if not f then
            setStatus("Error: Cannot write file!", colors.red)
            return
        end
        for i=1, #lines do
            f.writeLine(lines[i])
        end
        f.close()
        setStatus("Saved!", colors.yellow)
    end

    local function clampCursor()
        if cursorY < 1 then cursorY = 1 end
        if cursorY > #lines then cursorY = #lines end
        if not lines[cursorY] then lines[cursorY] = "" end
        local line = lines[cursorY]
        if cursorX < 1 then cursorX = 1 end
        if cursorX > #line + 1 then cursorX = #line + 1 end
    end

    setStatus("Use mouse to Save/Exit. Arrows: Move | Enter: New line | Backspace: Del", colors.lime)
    safeSetCursorBlink(false)
    redraw()
    while editing do
        redraw()
        local event, p1, p2, p3 = os.pullEvent()
        if event == "char" then
            local line = lines[cursorY] or ""
            lines[cursorY] = line:sub(1, cursorX-1) .. p1 .. line:sub(cursorX)
            cursorX = cursorX + 1
        elseif event == "key" then
            if p1 == keys.left then
                if cursorX > 1 then
                    cursorX = cursorX - 1
                end
            elseif p1 == keys.right then
                local line = lines[cursorY] or ""
                if cursorX <= #line then
                    cursorX = cursorX + 1
                end
            elseif p1 == keys.up then
                if cursorY > 1 then
                    cursorY = cursorY - 1
                    local line = lines[cursorY] or ""
                    if cursorX > #line+1 then cursorX = #line+1 end
                    if cursorY - scroll < 1 then scroll = scroll - 1 end
                end
            elseif p1 == keys.down then
                if cursorY < #lines then
                    cursorY = cursorY + 1
                    local line = lines[cursorY] or ""
                    if cursorX > #line+1 then cursorX = #line+1 end
                    if cursorY - scroll > h-3 then scroll = scroll + 1 end
                end
            elseif p1 == keys.backspace then
                local line = lines[cursorY] or ""
                if cursorX > 1 then
                    lines[cursorY] = line:sub(1, cursorX-2) .. line:sub(cursorX)
                    cursorX = cursorX - 1
                elseif cursorY > 1 then
                    local prevLine = lines[cursorY-1] or ""
                    local prevLen = #prevLine
                    lines[cursorY-1] = prevLine .. line
                    table.remove(lines, cursorY)
                    cursorY = cursorY - 1
                    cursorX = prevLen + 1
                end
            elseif p1 == keys.enter then
                local line = lines[cursorY] or ""
                local before = line:sub(1, cursorX-1)
                local after = line:sub(cursorX)
                lines[cursorY] = before
                table.insert(lines, cursorY+1, after)
                cursorY = cursorY + 1
                cursorX = 1
                if cursorY - scroll > h-3 then scroll = scroll + 1 end
            end
        elseif event == "mouse_click" and p1 == 1 then
            -- Проверяем кнопки Save/Exit
            local mx, my = p2, p3
            if my == btnY then
                if mx >= saveX and mx < saveX + #saveLabel then
                    saveFile()
                elseif mx >= exitX and mx < exitX + #exitLabel then
                    editing = false
                end
            end
            -- Клик по тексту: переместить курсор
            if my >= 2 and my <= h-3+1 then
                local lineIdx = my-1 + scroll
                if lines[lineIdx] then
                    cursorY = lineIdx
                    local line = lines[cursorY]
                    cursorX = math.min(mx, #line+1)
                end
            end
        end
        clampCursor()
    end
    safeSetCursorBlink(false)
end

-- === MENU UTILS ===
local function drawMenu(menu, w)
    for _, item in ipairs(menu) do
        local x = math.floor((w-#item.label)/2)+1
        drawClickableText(x, item.y, item.label, false)
    end
end

local function getMenuClick(menu, mx, my, w)
    for _, item in ipairs(menu) do
        local x = math.floor((w-#item.label)/2)+1
        if isInClickable(mx, my, x, item.y, item.label) then
            return item.label
        end
    end
    return nil
end

-- === USER MANAGER ===
local function userManagerScreen(currentUser)
    local w, h = term.getSize()
    local shouldExit = false
    local selectedUser = nil
    local users = UserManager.load()
    local currentUserObj = UserManager.get(users, currentUser)
    local isAdmin = currentUserObj and currentUserObj.admin

    while not shouldExit do
        clearScreen()
        centerText(1, OS_NAME .. " - User Manager", PALETTE.accent)
        users = UserManager.load()
        table.sort(users, function(a, b) return a.name < b.name end)
        local yStart = 4
        local btns = {}
        for i, user in ipairs(users) do
            local label = user.name
            if user.admin then label = label .. " [admin]" end
            if user.pass == "" then label = label .. " (no pass)" end
            local x = 4
            local y = yStart + i - 1
            drawClickableText(x, y, label, selectedUser == user.name)
            table.insert(btns, {x=x, y=y, label=label, name=user.name})
        end

        -- Кнопки управления 
        local adminButtons = {
            {label="Add",    action="add"},
            {label="Del",    action="del"},
            {label="Set Pass",action="pass"},
            {label="+Admin", action="admin"},
        }
        local userButtons = {
            {label="Set Pass",action="pass"},
        }

        local buttons = isAdmin and adminButtons or userButtons
        local maxBtnLen = 0
        for _, btn in ipairs(buttons) do
            if #btn.label > maxBtnLen then maxBtnLen = #btn.label end
        end
        local btnX = w - maxBtnLen - 4 
        local btnYStart = yStart
        for i, btn in ipairs(buttons) do
            btn.x = btnX
            btn.y = btnYStart + (i-1)*2
            drawClickableText(btn.x, btn.y, btn.label, false)
        end

        -- Нижние кнопки: Exit и Add 
        local bottomBtns = {}
        local bottomY = h-2
        local exitLabel = "Exit"
        local addLabel = "Add"
        local exitX = 4
        drawClickableText(exitX, bottomY, exitLabel, false)
        table.insert(bottomBtns, {x=exitX, y=bottomY, label=exitLabel, action="exit"})
        if isAdmin then
            local addX = exitX + #exitLabel + 6
            drawClickableText(addX, bottomY, addLabel, false)
            table.insert(bottomBtns, {x=addX, y=bottomY, label=addLabel, action="add"})
        end

        -- Инструкция
        if isAdmin then
            centerText(h-1, "Admins: Select user, then action.", PALETTE.border)
        else
            centerText(h-1, "Select yourself and Set Pass. Other actions unavailable.", PALETTE.border)
        end

        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            -- Select user
            for i, btn in ipairs(btns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    selectedUser = btn.name
                end
            end
            users = UserManager.load()
            -- Обработка вертикальных кнопок справа
            for i, btn in ipairs(buttons) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    if btn.action == "add" then
                        centerText(h-3, "Enter new username:", PALETTE.select)
                        term.setCursorPos(2, h-2)
                        local uname = inputBox(2, h-2, 16, false)
                        if uname == "" then
                            centerText(h-3, "Username cannot be empty!", PALETTE.error)
                            sleep(1)
                        elseif uname:find("[^%w_]") then
                            centerText(h-3, "ASCII letters, digits, _ only!", PALETTE.error)
                            sleep(1)
                        elseif UserManager.exists(users, uname) then
                            centerText(h-3, "User already exists!", PALETTE.error)
                            sleep(1)
                        else
                            centerText(h-3, "Enter password (empty = no pass):", PALETTE.select)
                            term.setCursorPos(2, h-2)
                            local upass = inputBox(2, h-2, 16, true)
                            local isFirst = #users == 0
                            table.insert(users, {name=uname, pass=UserManager.hashPassword(upass), admin=isFirst})
                            UserManager.save(users)
                            UserManager.createUserDir(uname)
                            centerText(h-3, "User added!", PALETTE.accent)
                            sleep(1)
                        end
                    elseif btn.action == "del" then
                        if not selectedUser then
                            centerText(h-3, "Select user to delete!", PALETTE.error)
                            sleep(1)
                        elseif selectedUser == currentUser then
                            centerText(h-3, "Cannot delete yourself!", PALETTE.error)
                            sleep(1)
                        else
                            local userToDel = UserManager.get(users, selectedUser)
                            if userToDel and userToDel.admin and UserManager.countAdmins(users) == 1 then
                                centerText(h-3, "Cannot delete last admin!", PALETTE.error)
                                sleep(1)
                            else
                                UserManager.remove(users, selectedUser)
                                UserManager.save(users)
                                UserManager.deleteUserDir(selectedUser)
                                centerText(h-3, "User deleted!", PALETTE.accent)
                                sleep(1)
                                selectedUser = nil
                            end
                        end
                    elseif btn.action == "pass" then
                        if not selectedUser then
                            centerText(h-3, "Select user to set password!", PALETTE.error)
                            sleep(1)
                        elseif not isAdmin and selectedUser ~= currentUser then
                            centerText(h-3, "Can only change your own password!", PALETTE.error)
                            sleep(1)
                        else
                            centerText(h-3, "Enter new password (empty = no pass):", PALETTE.select)
                            term.setCursorPos(2, h-2)
                            local upass = inputBox(2, h-2, 16, true)
                            UserManager.setPassword(users, selectedUser, upass)
                            UserManager.save(users)
                            centerText(h-3, "Password changed!", PALETTE.accent)
                            sleep(1)
                        end
                    elseif btn.action == "admin" then
                        if not selectedUser then
                            centerText(h-3, "Select user to toggle admin!", PALETTE.error)
                            sleep(1)
                        elseif selectedUser == currentUser then
                            centerText(h-3, "Cannot change your own admin status!", PALETTE.error)
                            sleep(1)
                        else
                            local userObj = UserManager.get(users, selectedUser)
                            if userObj then
                                if userObj.admin and UserManager.countAdmins(users) == 1 then
                                    centerText(h-3, "Cannot remove last admin!", PALETTE.error)
                                    sleep(1)
                                else
                                    UserManager.setAdmin(users, selectedUser, not userObj.admin)
                                    UserManager.save(users)
                                    centerText(h-3, "Admin status toggled!", PALETTE.accent)
                                    sleep(1)
                                end
                            end
                        end
                    end
                end
            end
            -- Обработка нижних кнопок
            for _, btn in ipairs(bottomBtns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    if btn.action == "exit" then
                        shouldExit = true
                    elseif btn.action == "add" then
                        -- Дублируем add user для удобства
                        centerText(h-3, "Enter new username:", PALETTE.select)
                        term.setCursorPos(2, h-2)
                        local uname = inputBox(2, h-2, 16, false)
                        if uname == "" then
                            centerText(h-3, "Username cannot be empty!", PALETTE.error)
                            sleep(1)
                        elseif uname:find("[^%w_]") then
                            centerText(h-3, "ASCII letters, digits, _ only!", PALETTE.error)
                            sleep(1)
                        elseif UserManager.exists(users, uname) then
                            centerText(h-3, "User already exists!", PALETTE.error)
                            sleep(1)
                        else
                            centerText(h-3, "Enter password (empty = no pass):", PALETTE.select)
                            term.setCursorPos(2, h-2)
                            local upass = inputBox(2, h-2, 16, true)
                            local isFirst = #users == 0
                            table.insert(users, {name=uname, pass=UserManager.hashPassword(upass), admin=isFirst})
                            UserManager.save(users)
                            UserManager.createUserDir(uname)
                            centerText(h-3, "User added!", PALETTE.accent)
                            sleep(1)
                        end
                    end
                end
            end
        end
    end
end

-- === FILE MANAGER ===

local function isTextFile(filename)
    -- Только текстовые файлы, не .lua/.exe
    return filename:match("%.txt$") or filename:match("%.cfg$") or filename:match("%.log$") or filename:match("%.json$") or not filename:find("%.[^%.]+$")
end

local function isExecutableFile(filename)
    return filename:match("%.lua$") or filename:match("%.exe$")
end

local function openWithMenu(filePath, isText, isExec)
    local w, h = term.getSize()
    local menu = {}
    if isExec then
        menu = {
            {label="Run", y=math.floor(h/2)-1},
            {label="Open in text editor", y=math.floor(h/2)+1}
        }
    else
        menu = {
            {label="Open in text editor", y=math.floor(h/2)-1}
        }
    end
    clearScreen()
    centerText(math.floor(h/2)-3, "Open file: " .. fs.getName(filePath), PALETTE.accent)
    drawMenu(menu, w)
    while true do
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            local clickedLabel = getMenuClick(menu, mx, my, w)
            if clickedLabel then
                if clickedLabel == "Run" then
                    clearScreen()
                    shell.run(filePath)
                    centerText(2, "Press any key to return...", PALETTE.select)
                    os.pullEvent("key")
                    break
                elseif clickedLabel == "Open in text editor" then
                    textEditorScreen(filePath)
                    break
                end
            end
        elseif event == "key" then
            if b == keys.escape then break end
        end
    end
end

local function createFileDialog(currentPath)
    local w, h = term.getSize()
    clearScreen()
    centerText(math.floor(h/2)-2, "Create file:", PALETTE.accent)
    term.setCursorPos(math.floor(w/2)-10, math.floor(h/2))
    term.write("Filename: ")
    local filename = inputBox(math.floor(w/2), math.floor(h/2), 20, false)
    if filename and filename ~= "" then
        local fullPath = fs.combine(currentPath, filename)
        if fs.exists(fullPath) then
            centerText(math.floor(h/2)+2, "File already exists!", PALETTE.error)
            sleep(1.5)
            return
        end
        -- Create empty file
        local f = fs.open(fullPath, "w")
        if f then f.close() end
        centerText(math.floor(h/2)+2, "File created: " .. filename, PALETTE.accent)
        sleep(1)
    end
end

local function fileManagerScreen(user)
    local w, h = term.getSize()
    local userRoot = fs.combine(USERS_DIR, user.name)
    if not fs.exists(userRoot) then fs.makeDir(userRoot) end
    local currentPath = user.admin and "/" or userRoot
    local shouldExit = false
    local selectedIdx = nil
    local files = {}
    local btns = {}

    local function refreshFiles()
        files = fs.list(currentPath)
        table.sort(files)
        btns = {}
        local yStart = 5
        for i, file in ipairs(files) do
            local isDir = fs.isDir(fs.combine(currentPath, file))
            local label = isDir and ("[D] "..file) or file
            local x = 4
            local y = yStart + i - 1
            btns[i] = {x=x, y=y, label=label, file=file, isDir=isDir, idx=i}
        end
    end

    local function drawFileManager()
        clearScreen()
        centerText(1, OS_NAME .. " - File Manager", PALETTE.accent)
        term.setCursorPos(2,3)
        term.setTextColor(PALETTE.border)
        term.write("Current path: " .. currentPath)
        term.setTextColor(PALETTE.fg)
        -- Draw files
        for i, btn in ipairs(btns) do
            drawClickableText(btn.x, btn.y, btn.label, selectedIdx == i)
        end
        -- Draw bottom buttons
        local plusLabel = "+"
        local openWithLabel = "Open With..."
        local upLabel = "Up"
        local exitLabel = "Exit"
        -- Left bottom: Exit, Up
        local exitX = 2
        local upX = exitX + #exitLabel + 4
        local btnY = h-2
        drawClickableText(exitX, btnY, exitLabel, false)
        drawClickableText(upX, btnY, upLabel, false)
        -- Right bottom: Open With..., +
        local plusX = w - (#plusLabel + 2)
        local openWithX = plusX - (#openWithLabel + 2)
        drawClickableText(openWithX, btnY, openWithLabel, selectedIdx ~= nil)
        drawClickableText(plusX, btnY, plusLabel, false)
    end

    while not shouldExit do
        refreshFiles()
        drawFileManager()
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            local handled = false
            -- Check file buttons
            for i, btn in ipairs(btns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    if selectedIdx == i then
                        -- Second click: open by default
                        if btn.isDir then
                            local nextPath = fs.combine(currentPath, btn.file)
                            -- Ограничение для обычных пользователей: нельзя выйти за пределы своей папки
                            if not user.admin then
                                local normNext = "/"..fs.combine(currentPath, btn.file)
                                local normRoot = "/"..userRoot
                                if normNext:sub(1, #normRoot) ~= normRoot then
                                    centerText(h-3, "Access denied!", PALETTE.error)
                                    sleep(1)
                                else
                                    currentPath = nextPath
                                    selectedIdx = nil
                                end
                            else
                                currentPath = nextPath
                                selectedIdx = nil
                            end
                        else
                            local filePath = fs.combine(currentPath, btn.file)
                            if isExecutableFile(btn.file) then
                                clearScreen()
                                shell.run(filePath)
                                centerText(2, "Press any key to return...", PALETTE.select)
                                os.pullEvent("key")
                            elseif isTextFile(btn.file) then
                                textEditorScreen(filePath)
                            else
                                textEditorScreen(filePath)
                            end
                        end
                    else
                        selectedIdx = i
                    end
                    handled = true
                    break
                end
            end
            -- Bottom buttons
            local plusLabel = "+"
            local openWithLabel = "Open With..."
            local upLabel = "Up"
            local exitLabel = "Exit"
            local exitX = 2
            local upX = exitX + #exitLabel + 4
            local btnY = h-2
            local plusX = w - (#plusLabel + 2)
            local openWithX = plusX - (#openWithLabel + 2)
            -- "+" button
            if not handled and isInClickable(mx, my, plusX, btnY, plusLabel) then
                createFileDialog(currentPath)
                handled = true
            end
            -- "Open With..." button
            if not handled and isInClickable(mx, my, openWithX, btnY, openWithLabel) and selectedIdx then
                local btn = btns[selectedIdx]
                if btn and not btn.isDir then
                    openWithMenu(
                        fs.combine(currentPath, btn.file),
                        isTextFile(btn.file),
                        isExecutableFile(btn.file)
                    )
                end
                handled = true
            end
            -- "Up" button
            if not handled and isInClickable(mx, my, upX, btnY, upLabel) then
                local rootPath = user.admin and "/" or userRoot
                -- Проверяем, не находимся ли уже в корне
                if currentPath ~= rootPath then
                    local parent = fs.getDir(currentPath)
                    -- Если parent пустой строки, значит мы в "/" и не двигаемся выше
                    if parent == "" then
                        currentPath = rootPath
                        selectedIdx = nil
                    else
                        -- Ограничение для обычных пользователей: нельзя выйти за пределы своей папки
                        if not user.admin then
                            local normParent = "/"..parent
                            local normRoot = "/"..userRoot
                            if normParent:sub(1, #normRoot) ~= normRoot then
                                centerText(h-3, "Access denied!", PALETTE.error)
                                sleep(1)
                            else
                                currentPath = parent
                                selectedIdx = nil
                            end
                        else
                            currentPath = parent
                            selectedIdx = nil
                        end
                    end
                end
                handled = true
            end
            -- "Exit" button
            if not handled and isInClickable(mx, my, exitX, btnY, exitLabel) then
                shouldExit = true
                handled = true
            end
        end
    end
end

-- === OS DELETE UTILS ===
local function deleteSandTecOS()
    local function safeDelete(path)
        if fs.exists(path) then
            if fs.isDir(path) then
                for _, f in ipairs(fs.list(path)) do
                    safeDelete(fs.combine(path, f))
                end
                fs.delete(path)
            else
                fs.delete(path)
            end
        end
    end
    -- Удаляем все файлы и папки SandTecOS
    safeDelete(USERS_FILE)
    safeDelete(USERS_DIR)
    safeDelete(shell.getRunningProgram()) -- startup.lua
    -- Можно добавить другие связанные файлы, если есть
end

-- === DESKTOP ===
local function desktopScreen(user)
    while true do
        clearScreen()
        local w, h = term.getSize()
        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
        centerText(4, "User: " .. user.name .. (user.admin and " [admin]" or ""), PALETTE.border)
        local menu = {
            {label="File Manager", y=7},
            {label="Users", y=9},
            {label="Logout", y=11}
        }
        drawMenu(menu, w)
        -- Admin-only: красная кнопка "Delete OS"
        local deleteLabel = "Delete OS"
        local deleteX = w - #deleteLabel - 2
        local deleteY = h
        if user.admin then
            term.setCursorPos(deleteX, deleteY)
            term.setTextColor(PALETTE.error)
            term.write(deleteLabel)
            term.setTextColor(PALETTE.fg)
        end
        local waiting = true
        local lastActivity = os.clock()
        while waiting do
            local timeout = SESSION_TIMEOUT - (os.clock() - lastActivity)
            if timeout <= 0 then
                centerText(h, "Session timed out. Returning to login...", PALETTE.error)
                sleep(2)
                return
            end
            local event, b, mx, my = os.pullEventRaw()
            if event == "terminate" then error("Terminated") end
            if event == "mouse_click" or event == "key" then
                lastActivity = os.clock()
            end
            if event == "mouse_click" and b == 1 then
                -- Проверка нажатия на обычные пункты меню
                local clickedLabel = getMenuClick(menu, mx, my, w)
                if clickedLabel then
                    if clickedLabel == "File Manager" then
                        fileManagerScreen(user)
                        clearScreen()
                        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                        centerText(4, "User: " .. user.name .. (user.admin and " [admin]" or ""), PALETTE.border)
                        drawMenu(menu, w)
                        if user.admin then
                            term.setCursorPos(deleteX, deleteY)
                            term.setTextColor(PALETTE.error)
                            term.write(deleteLabel)
                            term.setTextColor(PALETTE.fg)
                        end
                    elseif clickedLabel == "Users" then
                        userManagerScreen(user.name)
                        clearScreen()
                        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                        centerText(4, "User: " .. user.name .. (user.admin and " [admin]" or ""), PALETTE.border)
                        drawMenu(menu, w)
                        if user.admin then
                            term.setCursorPos(deleteX, deleteY)
                            term.setTextColor(PALETTE.error)
                            term.write(deleteLabel)
                            term.setTextColor(PALETTE.fg)
                        end
                    elseif clickedLabel == "Logout" then
                        return
                    end
                end
                -- Проверка нажатия на красную кнопку удаления ОС
                if user.admin and mx >= deleteX and mx < deleteX + #deleteLabel and my == deleteY then
                    -- Новый диалог подтверждения
                    local confirm = false
                    while true do
                        clearScreen()
                        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                        centerText(4, "User: " .. user.name .. (user.admin and " [admin]" or ""), PALETTE.border)
                        drawMenu(menu, w)
                        -- Кнопка Delete OS
                        term.setCursorPos(deleteX, deleteY)
                        term.setTextColor(PALETTE.error)
                        term.write(deleteLabel)
                        term.setTextColor(PALETTE.fg)
                        -- Диалог подтверждения
                        local dialogY = math.max(deleteY - 4, 13)
                        centerText(dialogY, "Are you sure?", PALETTE.error)
                        local yesLabel = "Yes"
                        local noLabel = "No"
                        local btnY = dialogY + 2
                        local yesX = math.floor(w/2) - 5
                        local noX = math.floor(w/2) + 3
                        -- Yes (красная)
                        term.setCursorPos(yesX, btnY)
                        term.setTextColor(PALETTE.error)
                        term.write(yesLabel)
                        -- No (обычная)
                        term.setCursorPos(noX, btnY)
                        term.setTextColor(PALETTE.fg)
                        term.write(noLabel)
                        term.setTextColor(PALETTE.fg)
                        -- Ждём клик
                        local ev, btn, mx2, my2 = os.pullEvent("mouse_click")
                        if my2 == btnY then
                            if mx2 >= yesX and mx2 < yesX + #yesLabel then
                                confirm = true
                                break
                            elseif mx2 >= noX and mx2 < noX + #noLabel then
                                confirm = false
                                break
                            end
                        end
                    end
                    if confirm then
                        clearScreen()
                        centerText(math.floor(h/2), "Deleting SandTecOS...", PALETTE.error)
                        sleep(1)
                        deleteSandTecOS()
                        centerText(math.floor(h/2)+2, "System deleted. Rebooting...", PALETTE.error)
                        sleep(2)
                        os.reboot()
                    else
                        centerText(h-1, "Cancelled.", PALETTE.accent)
                        sleep(1)
                        -- Перерисовать экран
                        clearScreen()
                        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                        centerText(4, "User: " .. user.name .. (user.admin and " [admin]" or ""), PALETTE.border)
                        drawMenu(menu, w)
                        if user.admin then
                            term.setCursorPos(deleteX, deleteY)
                            term.setTextColor(PALETTE.error)
                            term.write(deleteLabel)
                            term.setTextColor(PALETTE.fg)
                        end
                    end
                end
            end
        end
    end
end

-- === AUTH ===
local function authScreen()
    while true do
        clearScreen()
        local w, h = term.getSize()
        centerText(2, OS_NAME, PALETTE.accent)
        centerText(4, "Welcome!", PALETTE.fg)
        local users = UserManager.load()
        table.sort(users, function(a, b) return a.name < b.name end)
        local menu = {}
        local yStart = 7
        if #users == 0 then
            menu = {
                {label="Register", y=yStart}
            }
        else
            -- Список пользователей
            for i, user in ipairs(users) do
                local label = user.name
                if user.admin then label = label .. " [admin]" end
                if user.pass == "" then label = label .. " (no pass)" end
                table.insert(menu, {label=label, y=yStart+i-1, username=user.name})
            end
            table.insert(menu, {label="Register", y=yStart+#users+2})
        end
        drawMenu(menu, w)
        while true do
            local event, b, mx, my = os.pullEvent()
            if event == "mouse_click" and b == 1 then
                for _, item in ipairs(menu) do
                    local x = math.floor((w-#item.label)/2)+1
                    if isInClickable(mx, my, x, item.y, item.label) then
                        if item.label == "Register" then
                            registerScreen()
                            break -- <--- Важно! После регистрации возвращаемся к authScreen
                        elseif item.username then
                            -- Выбран пользователь
                            local users = UserManager.load()
                            local user = UserManager.get(users, item.username)
                            if user.pass == "" then
                                centerText(item.y+2, "Login successful!", PALETTE.accent)
                                sleep(1)
                                return user
                            else
                                centerText(item.y+2, "Enter password:", PALETTE.select)
                                term.setCursorPos(math.floor(w/2)-8, item.y+3)
                                term.write("Password: ")
                                local password = inputBox(math.floor(w/2)+2, item.y+3, 16, true)
                                if user.pass == UserManager.hashPassword(password) then
                                    centerText(item.y+5, "Login successful!", PALETTE.accent)
                                    sleep(1)
                                    return user
                                else
                                    centerText(item.y+5, "Invalid password!", PALETTE.error)
                                    sleep(1.5)
                                    break
                                end
                            end
                        end
                    end
                end
            end
        end
    end
end

function registerScreen()
    clearScreen()
    local w, h = term.getSize()
    centerText(2, OS_NAME .. " - Register", PALETTE.accent)
    centerText(4, "Create a new user", PALETTE.fg)
    term.setCursorPos(math.floor(w/2)-10, 6)
    term.write("Username: ")
    local username = inputBox(math.floor(w/2), 6, 16, false)
    term.setCursorPos(math.floor(w/2)-10, 8)
    term.write("Password: ")
    local password = inputBox(math.floor(w/2), 8, 16, true)
    local users = UserManager.load()
    if username == "" then
        centerText(10, "Username cannot be empty!", PALETTE.error)
        sleep(1.5)
        return false
    end
    if username:find("[^%w_]") then
        centerText(10, "ASCII letters, digits, _ only!", PALETTE.error)
        sleep(1.5)
        return false
    end
    if UserManager.exists(users, username) then
        centerText(10, "User already exists!", PALETTE.error)
        sleep(1.5)
        return false
    end
    -- Первый пользователь всегда admin
    local isFirst = #users == 0
    table.insert(users, {name=username, pass=UserManager.hashPassword(password), admin=isFirst})
    UserManager.save(users)
    UserManager.createUserDir(username)
    centerText(10, "User registered!", PALETTE.accent)
    centerText(12, "Перезапустите компьютер для применения", PALETTE.select)
    sleep(3)
end

-- === MAIN LOOP ===
local function main()
    while true do
        local user = authScreen()
        desktopScreen(user)
    end
end

-- === START OS WITH ERROR HANDLING ===
local function safeMain()
    local ok, err = pcall(main)
    if not ok then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.clear()
        term.setCursorPos(1,1)
        print("SandTecOS crashed with error:")
        print(err)
        print("\nPress any key to reboot...")
        os.pullEvent("key")
        os.reboot()
    end
end

safeMain()