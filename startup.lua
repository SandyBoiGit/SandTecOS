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

-- === FILE MOVE UTILS ===
local function moveFileOrDir(src, dst)
    if not fs.exists(src) then
        return false, "Source does not exist"
    end
    if fs.exists(dst) then
        return false, "Destination already exists"
    end
    local function recursiveCopy(s, d)
        if fs.isDir(s) then
            fs.makeDir(d)
            for _, f in ipairs(fs.list(s)) do
                local ok, err = recursiveCopy(fs.combine(s, f), fs.combine(d, f))
                if not ok then return false, err end
            end
        else
            local ok, err = pcall(fs.copy, s, d)
            if not ok then return false, "Copy failed: " .. tostring(err) end
        end
        return true
    end
    local ok, err = recursiveCopy(src, dst)
    if not ok then return false, err end
    local ok2, err2 = pcall(fs.delete, src)
    if not ok2 then return false, "Delete failed: " .. tostring(err2) end
    return true
end

-- === DIRECTORY SELECTOR ===
local function selectDirectoryDialog(startPath, user, userRoot)
    local w, h = term.getSize()
    local currentPath = startPath
    while true do
        clearScreen()
        centerText(2, "Select destination directory", PALETTE.accent)
        term.setCursorPos(2, 4)
        term.setTextColor(PALETTE.border)
        term.write("Current: " .. currentPath)
        term.setTextColor(PALETTE.fg)
        local dirs = {}
        local yStart = 6
        for _, file in ipairs(fs.list(currentPath)) do
            local full = fs.combine(currentPath, file)
            if fs.isDir(full) then
                table.insert(dirs, file)
            end
        end
        table.sort(dirs)
        local btns = {}
        for i, dir in ipairs(dirs) do
            local x = 4
            local y = yStart + i - 1
            drawClickableText(x, y, dir, false)
            btns[i] = {x=x, y=y, label=dir, dir=dir}
        end
        -- Bottom buttons
        local selectLabel = "Select"
        local upLabel = "Up"
        local cancelLabel = "Cancel"
        local selectX = 2
        local upX = selectX + #selectLabel + 4
        local cancelX = upX + #upLabel + 4
        local btnY = h-2
        drawClickableText(selectX, btnY, selectLabel, false)
        drawClickableText(upX, btnY, upLabel, false)
        drawClickableText(cancelX, btnY, cancelLabel, false)
        -- Wait for input
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            -- Directory click
            for i, btn in ipairs(btns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    local nextPath = fs.combine(currentPath, btn.dir)
                    -- User restriction
                    if not user.admin then
                        local normNext = "/"..fs.combine(currentPath, btn.dir)
                        local normRoot = "/"..userRoot
                        if normNext:sub(1, #normRoot) ~= normRoot then
                            centerText(h-3, "Access denied!", PALETTE.error)
                            sleep(1)
                        else
                            currentPath = nextPath
                        end
                    else
                        currentPath = nextPath
                    end
                end
            end
            -- Select
            if isInClickable(mx, my, selectX, btnY, selectLabel) then
                return currentPath
            end
            -- Up
            if isInClickable(mx, my, upX, btnY, upLabel) then
                local rootPath = user.admin and "/" or userRoot
                if currentPath ~= rootPath then
                    local parent = fs.getDir(currentPath)
                    if parent == "" then
                        currentPath = rootPath
                    else
                        -- User restriction
                        if not user.admin then
                            local normParent = "/"..parent
                            local normRoot = "/"..userRoot
                            if normParent:sub(1, #normRoot) ~= normRoot then
                                centerText(h-3, "Access denied!", PALETTE.error)
                                sleep(1)
                            else
                                currentPath = parent
                            end
                        else
                            currentPath = parent
                        end
                    end
                end
            end
            -- Cancel
            if isInClickable(mx, my, cancelX, btnY, cancelLabel) then
                return nil
            end
        end
    end
end

-- === FILE MANAGER ===
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
        local moveLabel = "Move"
        local upLabel = "Up"
        local exitLabel = "Exit"
        -- Left bottom: Exit, Up
        local exitX = 2
        local upX = exitX + #exitLabel + 4
        local btnY = h-2
        drawClickableText(exitX, btnY, exitLabel, false)
        drawClickableText(upX, btnY, upLabel, false)
        -- Right bottom: Open With..., Move, +
        local plusX = w - (#plusLabel + 2)
        local moveX = plusX - (#moveLabel + 2)
        local openWithX = moveX - (#openWithLabel + 2)
        drawClickableText(openWithX, btnY, openWithLabel, selectedIdx ~= nil)
        drawClickableText(moveX, btnY, moveLabel, selectedIdx ~= nil)
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
            local moveLabel = "Move"
            local upLabel = "Up"
            local exitLabel = "Exit"
            local exitX = 2
            local upX = exitX + #exitLabel + 4
            local btnY = h-2
            local plusX = w - (#plusLabel + 2)
            local moveX = plusX - (#moveLabel + 2)
            local openWithX = moveX - (#openWithLabel + 2)
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
            -- "Move" button
            if not handled and isInClickable(mx, my, moveX, btnY, moveLabel) and selectedIdx then
                local btn = btns[selectedIdx]
                local srcPath = fs.combine(currentPath, btn.file)
                -- Выбор директории назначения
                local dstDir = selectDirectoryDialog(user.admin and "/" or userRoot, user, userRoot)
                if dstDir then
                    local dstPath = fs.combine(dstDir, btn.file)
                    if dstPath == srcPath then
                        centerText(h-3, "Cannot move to same location!", PALETTE.error)
                        sleep(1)
                    elseif fs.exists(dstPath) then
                        centerText(h-3, "Destination exists!", PALETTE.error)
                        sleep(1)
                    else
                        centerText(h-3, "Moving...", PALETTE.select)
                        local ok, err = moveFileOrDir(srcPath, dstPath)
                        if ok then
                            centerText(h-3, "Moved successfully!", PALETTE.accent)
                            selectedIdx = nil
                        else
                            centerText(h-3, "Move failed: "..(err or ""), PALETTE.error)
                        end
                        sleep(1)
                    end
                end
                handled = true
            end
            -- "Up" button
            if not handled and isInClickable(mx, my, upX, btnY, upLabel) then
                local rootPath = user.admin and "/" or userRoot
                if currentPath ~= rootPath then
                    local parent = fs.getDir(currentPath)
                    if parent == "" then
                        currentPath = rootPath
                        selectedIdx = nil
                    else
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

-- === CREATE FILE DIALOG ===
local function createFileDialog(currentPath)
    local w, h = term.getSize()
    clearScreen()
    centerText(2, "Create File or Directory", PALETTE.accent)
    centerText(4, "Enter name (end with / for folder):", PALETTE.fg)
    term.setCursorPos(4, 6)
    term.write("Name: ")
    local name = inputBox(11, 6, 24, false)
    if name == "" then
        centerText(8, "Name cannot be empty!", PALETTE.error)
        sleep(1.5)
        return
    end
    if name:find("[/\\]") and name:sub(-1) ~= "/" then
        centerText(8, "Invalid character in name!", PALETTE.error)
        sleep(1.5)
        return
    end
    local fullPath = fs.combine(currentPath, name)
    if fs.exists(fullPath) then
        centerText(8, "File or folder already exists!", PALETTE.error)
        sleep(1.5)
        return
    end
    if name:sub(-1) == "/" then
        -- Create directory
        pcall(fs.makeDir, fullPath)
        centerText(8, "Directory created!", PALETTE.accent)
        sleep(1)
    else
        -- Create file
        local f = fs.open(fullPath, "w")
        if f then f.close() end
        centerText(8, "File created!", PALETTE.accent)
        sleep(1)
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

-- === APPVIEW SCREEN ===
local function appViewScreen(user)
    local APPS_DIR = "/Apps"
    local function getAppsList()
        local apps = {}
        if fs.exists(APPS_DIR) and fs.isDir(APPS_DIR) then
            for _, file in ipairs(fs.list(APPS_DIR)) do
                local path = fs.combine(APPS_DIR, file)
                if not fs.isDir(path) and (file:match("%.lua$") or file:match("%.exe$")) then
                    table.insert(apps, {
                        name = file:gsub("%.lua$", ""):gsub("%.exe$", ""),
                        file = file,
                        path = path
                    })
                end
            end
        end
        table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)
        return apps
    end

    local function drawAppButtons(apps, selectedIdx)
        local w, h = term.getSize()
        local btnSize = 12
        local btnPad = 3
        local cols = math.floor((w - btnPad) / (btnSize + btnPad))
        if cols < 1 then cols = 1 end
        local rows = math.ceil(#apps / cols)
        local startY = 4
        local startX = math.floor((w - (cols * btnSize + (cols-1)*btnPad)) / 2) + 1

        clearScreen()
        centerText(2, OS_NAME .. " - AppView", PALETTE.accent)
        centerText(3, "Click an app to launch", PALETTE.border)
        for i, app in ipairs(apps) do
            local col = ((i-1) % cols)
            local row = math.floor((i-1) / cols)
            local x = startX + col * (btnSize + btnPad)
            local y = startY + row * (btnSize + btnPad)
            -- Draw button background
            for dy = 0, btnSize-1 do
                term.setCursorPos(x, y+dy)
                if selectedIdx == i then
                    term.setBackgroundColor(PALETTE.select)
                else
                    term.setBackgroundColor(PALETTE.bg)
                end
                term.write(string.rep(" ", btnSize))
            end
            -- Draw app name centered
            local label = app.name
            local labelY = y + math.floor(btnSize/2)
            term.setCursorPos(x + math.floor((btnSize-#label)/2), labelY)
            term.setTextColor(PALETTE.fg)
            term.write(label)
            term.setTextColor(PALETTE.fg)
            term.setBackgroundColor(PALETTE.bg)
        end
        -- Draw Exit button
        local exitLabel = "Exit"
        local exitX = 2
        local exitY = h-2
        drawClickableText(exitX, exitY, exitLabel, false)
    end

    local function getAppByCoords(apps, mx, my)
        local w, h = term.getSize()
        local btnSize = 12
        local btnPad = 3
        local cols = math.floor((w - btnPad) / (btnSize + btnPad))
        if cols < 1 then cols = 1 end
        local startY = 4
        local startX = math.floor((w - (cols * btnSize + (cols-1)*btnPad)) / 2) + 1
        for i, app in ipairs(apps) do
            local col = ((i-1) % cols)
            local row = math.floor((i-1) / cols)
            local x = startX + col * (btnSize + btnPad)
            local y = startY + row * (btnSize + btnPad)
            if mx >= x and mx < x + btnSize and my >= y and my < y + btnSize then
                return i, app
            end
        end
        return nil, nil
    end

    local apps = getAppsList()
    local selectedIdx = nil
    drawAppButtons(apps, selectedIdx)
    while true do
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            -- Exit button
            local w, h = term.getSize()
            if my == h-2 and mx >= 2 and mx < 2 + #"Exit" then
                break
            end
            -- App buttons
            local idx, app = getAppByCoords(apps, mx, my)
            if idx and app then
                selectedIdx = idx
                drawAppButtons(apps, selectedIdx)
                clearScreen()
                centerText(2, "Launching: " .. app.name, PALETTE.accent)
                sleep(0.5)
                shell.run(app.path)
                centerText(h-2, "Press any key to return to AppView...", PALETTE.select)
                os.pullEvent("key")
                selectedIdx = nil
                drawAppButtons(apps, selectedIdx)
            end
        elseif event == "key" and b == keys.escape then
            break
        end
    end
end

-- === APPVIEW SCREEN ===
local function appViewScreen(user)
    local APPS_DIR = "/Apps"
    local function getAppsList()
        local apps = {}
        if fs.exists(APPS_DIR) and fs.isDir(APPS_DIR) then
            for _, file in ipairs(fs.list(APPS_DIR)) do
                local path = fs.combine(APPS_DIR, file)
                if not fs.isDir(path) and (file:match("%.lua$") or file:match("%.exe$")) then
                    table.insert(apps, {
                        name = file:gsub("%.lua$", ""):gsub("%.exe$", ""),
                        file = file,
                        path = path
                    })
                end
            end
        end
        table.sort(apps, function(a, b) return a.name:lower() < b.name:lower() end)
        return apps
    end

    local function drawAppButtons(apps, selectedIdx)
        local w, h = term.getSize()
        local btnSize = 12
        local btnPad = 3
        local cols = math.floor((w - btnPad) / (btnSize + btnPad))
        if cols < 1 then cols = 1 end
        local rows = math.ceil(#apps / cols)
        local startY = 4
        local startX = math.floor((w - (cols * btnSize + (cols-1)*btnPad)) / 2) + 1

        clearScreen()
        centerText(2, OS_NAME .. " - AppView", PALETTE.accent)
        centerText(3, "Click an app to launch", PALETTE.border)
        for i, app in ipairs(apps) do
            local col = ((i-1) % cols)
            local row = math.floor((i-1) / cols)
            local x = startX + col * (btnSize + btnPad)
            local y = startY + row * (btnSize + btnPad)
            -- Draw button background
            for dy = 0, btnSize-1 do
                term.setCursorPos(x, y+dy)
                if selectedIdx == i then
                    term.setBackgroundColor(PALETTE.select)
                else
                    term.setBackgroundColor(PALETTE.bg)
                end
                term.write(string.rep(" ", btnSize))
            end
            -- Draw app name centered
            local label = app.name
            local labelY = y + math.floor(btnSize/2)
            term.setCursorPos(x + math.floor((btnSize-#label)/2), labelY)
            term.setTextColor(PALETTE.fg)
            term.write(label)
            term.setTextColor(PALETTE.fg)
            term.setBackgroundColor(PALETTE.bg)
        end
        -- Draw Exit button
        local exitLabel = "Exit"
        local exitX = 2
        local exitY = h-2
        drawClickableText(exitX, exitY, exitLabel, false)
    end

    local function getAppByCoords(apps, mx, my)
        local w, h = term.getSize()
        local btnSize = 12
        local btnPad = 3
        local cols = math.floor((w - btnPad) / (btnSize + btnPad))
        if cols < 1 then cols = 1 end
        local startY = 4
        local startX = math.floor((w - (cols * btnSize + (cols-1)*btnPad)) / 2) + 1
        for i, app in ipairs(apps) do
            local col = ((i-1) % cols)
            local row = math.floor((i-1) / cols)
            local x = startX + col * (btnSize + btnPad)
            local y = startY + row * (btnSize + btnPad)
            if mx >= x and mx < x + btnSize and my >= y and my < y + btnSize then
                return i, app
            end
        end
        return nil, nil
    end

    local apps = getAppsList()
    local selectedIdx = nil
    drawAppButtons(apps, selectedIdx)
    while true do
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            -- Exit button
            local w, h = term.getSize()
            if my == h-2 and mx >= 2 and mx < 2 + #"Exit" then
                break
            end
            -- App buttons
            local idx, app = getAppByCoords(apps, mx, my)
            if idx and app then
                selectedIdx = idx
                drawAppButtons(apps, selectedIdx)
                clearScreen()
                centerText(2, "Launching: " .. app.name, PALETTE.accent)
                sleep(0.5)
                shell.run(app.path)
                centerText(h-2, "Press any key to return to AppView...", PALETTE.select)
                os.pullEvent("key")
                selectedIdx = nil
                drawAppButtons(apps, selectedIdx)
            end
        elseif event == "key" and b == keys.escape then
            break
        end
    end
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
            {label="AppView", y=9},
            {label="Users", y=11},
            {label="Logout", y=13}
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
                    elseif clickedLabel == "AppView" then
                        appViewScreen(user)
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
                            break 
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
    centerText(12, "Please reboot the computer to apply changes", PALETTE.select)
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