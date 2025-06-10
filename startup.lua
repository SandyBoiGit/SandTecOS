-- SandTecOS - Fallout Terminal Style OS for CC:Tweaked (GUI Edition, universal user manager)
-- Author: [Your Name]
-- File: startup.lua

-- === CONFIGURATION ===
local OS_NAME = "SandTecOS"
local USERS_FILE = "/sandtecos_users"
local PALETTE = {
    bg = colors.black,
    fg = colors.lime,
    accent = colors.yellow,
    border = colors.green,
    error = colors.red,
    select = colors.orange
}

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
            if #input < w then
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
local function loadUsers()
    if not fs.exists(USERS_FILE) then return {} end
    local f = fs.open(USERS_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

local function saveUsers(users)
    local f = fs.open(USERS_FILE, "w")
    f.write(textutils.serialize(users))
    f.close()
end

local function hashPassword(password)
    return string.reverse(password) .. "s@nd"
end

local function userExists(users, username)
    for _, user in ipairs(users) do
        if user.name == username then return true end
    end
    return false
end

local function getUser(users, username)
    for _, user in ipairs(users) do
        if user.name == username then return user end
    end
    return nil
end

local function removeUser(users, username)
    for i, user in ipairs(users) do
        if user.name == username then
            table.remove(users, i)
            return true
        end
    end
    return false
end

local function setUserPassword(users, username, newPassword)
    for i, user in ipairs(users) do
        if user.name == username then
            users[i].pass = hashPassword(newPassword)
            return true
        end
    end
    return false
end

-- === TEXT EDITOR (Improved, with robust bounds protection) ===
local function textEditorScreen(filepath)
    clearScreen()
    local w, h = term.getSize()
    local lines = {}
    if fs.exists(filepath) then
        local f = fs.open(filepath, "r")
        for line in f.readLine, f do
            table.insert(lines, line)
        end
        f.close()
    end
    if #lines == 0 then lines = {""} end

    local cursorX, cursorY = 1, 1
    local scroll = 0
    local editing = true

    local saveLabel = "Save"
    local exitLabel = "Exit"
    local saveX = 2
    local saveY = h-2
    local exitX = 10
    local exitY = h-2

    local function redraw()
        clearScreen()
        centerText(1, OS_NAME .. " - Text Editor", PALETTE.accent)
        term.setCursorPos(2, 2)
        term.setTextColor(PALETTE.border)
        term.write("File: " .. filepath)
        term.setTextColor(PALETTE.fg)
        -- Draw lines with cropping
        for i=1, h-6 do
            term.setCursorPos(2, i+2)
            local idx = i + scroll
            if lines[idx] then
                local line = lines[idx]
                if #line > w-2 then
                    term.write(line:sub(1, w-2))
                else
                    term.write(line)
                end
            else
                term.write("")
            end
        end
        -- Draw buttons
        drawClickableText(saveX, saveY, saveLabel, false)
        drawClickableText(exitX, exitY, exitLabel, false)
        -- Draw hotkey hint
        term.setCursorPos(2, h-4)
        term.setTextColor(PALETTE.border)
        term.write("Ctrl+S: Save   Ctrl+Q: Exit")
        term.setTextColor(PALETTE.fg)
        -- Set cursor
        local cx = cursorX
        local cy = cursorY - scroll
        local line = lines[cursorY] or ""
        if cx < 1 then cx = 1 end
        if cx > #line + 1 then cx = #line + 1 end
        if cy >= 1 and cy <= h-6 then
            term.setCursorPos(cx+1, cy+2)
            term.setCursorBlink(true)
        else
            term.setCursorBlink(false)
        end
    end

    local function saveFile()
        local f = fs.open(filepath, "w")
        for i=1, #lines do
            f.writeLine(lines[i])
        end
        f.close()
        centerText(h-5, "Saved!", PALETTE.accent)
        sleep(0.5)
    end

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
                    if cursorY - scroll > h-6 then scroll = scroll + 1 end
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
                if cursorY - scroll > h-6 then scroll = scroll + 1 end
            elseif p1 == keys.s and (p2 and p2 == true or (p3 and p3 == true)) then -- Ctrl+S
                saveFile()
            elseif p1 == keys.q and (p2 and p2 == true or (p3 and p3 == true)) then -- Ctrl+Q
                editing = false
            end
        elseif event == "mouse_click" and p1 == 1 then
            if isInClickable(p2, p3, saveX, saveY, saveLabel) then
                saveFile()
            elseif isInClickable(p2, p3, exitX, exitY, exitLabel) then
                editing = false
            elseif p3 >= 3 and p3 <= h-4 and p2 >= 2 then
                local ly = p3 - 2 + scroll
                if ly >= 1 and ly <= #lines then
                    cursorY = ly
                    local line = lines[cursorY] or ""
                    cursorX = math.min(#line+1, p2-1)
                end
            end
        end
        -- === Robust bounds protection ===
        if cursorY < 1 then cursorY = 1 end
        if cursorY > #lines then cursorY = #lines end
        if not lines[cursorY] then lines[cursorY] = "" end
        local line = lines[cursorY]
        if cursorX < 1 then cursorX = 1 end
        if cursorX > #line + 1 then cursorX = #line + 1 end
    end
    term.setCursorBlink(false)
end

-- === USER MANAGER (universal, cannot delete self) ===
local function userManagerScreen(currentUser)
    local w, h = term.getSize()
    local shouldExit = false
    local selectedUser = nil
    while not shouldExit do
        clearScreen()
        centerText(1, OS_NAME .. " - User Manager", PALETTE.accent)
        local users = loadUsers()
        table.sort(users, function(a, b) return a.name < b.name end)
        local yStart = 4
        local btns = {}
        for i, user in ipairs(users) do
            local label = user.name
            local x = 4
            local y = yStart + i - 1
            drawClickableText(x, y, label, selectedUser == user.name)
            table.insert(btns, {x=x, y=y, label=label, name=user.name})
        end
        local addLabel = "Add User"
        local delLabel = "Delete User"
        local passLabel = "Set Password"
        local exitLabel = "Exit"
        local addX, addY = 2, h-4
        local delX, delY = 14, h-4
        local passX, passY = 30, h-4
        local exitX, exitY = 2, h-2
        drawClickableText(addX, addY, addLabel, false)
        drawClickableText(delX, delY, delLabel, false)
        drawClickableText(passX, passY, passLabel, false)
        drawClickableText(exitX, exitY, exitLabel, false)
        centerText(h-1, "Select user above, then Delete/Set Password. Add creates new user.", PALETTE.border)

        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            -- Select user
            for i, btn in ipairs(btns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    selectedUser = btn.name
                end
            end
            -- Add User
            if isInClickable(mx, my, addX, addY, addLabel) then
                centerText(h-3, "Enter new username:", PALETTE.select)
                term.setCursorPos(2, h-2)
                local uname = inputBox(2, h-2, 16, false)
                if uname == "" then
                    centerText(h-3, "Username cannot be empty!", PALETTE.error)
                    sleep(1)
                elseif userExists(users, uname) then
                    centerText(h-3, "User already exists!", PALETTE.error)
                    sleep(1)
                else
                    centerText(h-3, "Enter password:", PALETTE.select)
                    term.setCursorPos(2, h-2)
                    local upass = inputBox(2, h-2, 16, true)
                    table.insert(users, {name=uname, pass=hashPassword(upass)})
                    saveUsers(users)
                    centerText(h-3, "User added!", PALETTE.accent)
                    sleep(1)
                end
            -- Delete User
            elseif isInClickable(mx, my, delX, delY, delLabel) then
                if not selectedUser then
                    centerText(h-3, "Select user to delete!", PALETTE.error)
                    sleep(1)
                elseif selectedUser == currentUser then
                    centerText(h-3, "Cannot delete yourself!", PALETTE.error)
                    sleep(1)
                else
                    removeUser(users, selectedUser)
                    saveUsers(users)
                    centerText(h-3, "User deleted!", PALETTE.accent)
                    sleep(1)
                    selectedUser = nil
                end
            -- Set Password
            elseif isInClickable(mx, my, passX, passY, passLabel) then
                if not selectedUser then
                    centerText(h-3, "Select user to set password!", PALETTE.error)
                    sleep(1)
                else
                    centerText(h-3, "Enter new password:", PALETTE.select)
                    term.setCursorPos(2, h-2)
                    local upass = inputBox(2, h-2, 16, true)
                    setUserPassword(users, selectedUser, upass)
                    saveUsers(users)
                    centerText(h-3, "Password changed!", PALETTE.accent)
                    sleep(1)
                end
            -- Exit
            elseif isInClickable(mx, my, exitX, exitY, exitLabel) then
                shouldExit = true
            end
        end
    end
end

-- === FILE MANAGER ===
local function fileManagerScreen()
    local w, h = term.getSize()
    local currentPath = "/"
    local shouldExit = false
    while not shouldExit do
        clearScreen()
        centerText(1, OS_NAME .. " - File Manager", PALETTE.accent)
        term.setCursorPos(2,3)
        term.setTextColor(PALETTE.border)
        term.write("Current path: " .. currentPath)
        term.setTextColor(PALETTE.fg)
        local files = fs.list(currentPath)
        table.sort(files)
        local btns = {}
        local yStart = 5
        for i, file in ipairs(files) do
            local isDir = fs.isDir(fs.combine(currentPath, file))
            local label = isDir and ("[D] "..file) or file
            local x = 4
            local y = yStart + i - 1
            drawClickableText(x, y, label, false)
            table.insert(btns, {x=x, y=y, label=label, file=file, isDir=isDir})
        end
        local upLabel = "Up"
        local exitLabel = "Exit"
        local upX = 2
        local upY = h-2
        local exitX = 8
        local exitY = h-2
        drawClickableText(upX, upY, upLabel, false)
        drawClickableText(exitX, exitY, exitLabel, false)
        local event, b, mx, my = os.pullEvent()
        if event == "mouse_click" and b == 1 then
            local handled = false
            for i, btn in ipairs(btns) do
                if isInClickable(mx, my, btn.x, btn.y, btn.label) then
                    local fpath = fs.combine(currentPath, btn.file)
                    if btn.isDir then
                        currentPath = fpath
                    else
                        if btn.file:match("%.txt$") then
                            textEditorScreen(fpath)
                        else
                            clearScreen()
                            shell.run(fpath)
                            centerText(2, "Press any key to return...", PALETTE.select)
                            os.pullEvent("key")
                        end
                    end
                    handled = true
                    break
                end
            end
            if not handled and isInClickable(mx, my, upX, upY, upLabel) then
                if currentPath ~= "/" then
                    currentPath = fs.getDir(currentPath)
                end
            elseif not handled and isInClickable(mx, my, exitX, exitY, exitLabel) then
                shouldExit = true
            end
        end
    end
end

-- === DESKTOP ===
local function desktopScreen(user)
    while true do
        clearScreen()
        local w, h = term.getSize()
        centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
        centerText(4, "User: " .. user.name, PALETTE.border)
        local menu = {
            {label="File Manager", y=7},
            {label="Users", y=9},
            {label="Logout", y=11}
        }
        for _, item in ipairs(menu) do
            drawClickableText(math.floor((w-#item.label)/2)+1, item.y, item.label, false)
        end
        local waiting = true
        while waiting do
            local event, b, mx, my = os.pullEvent()
            if event == "mouse_click" and b == 1 then
                for _, item in ipairs(menu) do
                    local x = math.floor((w-#item.label)/2)+1
                    if isInClickable(mx, my, x, item.y, item.label) then
                        if item.label == "File Manager" then
                            fileManagerScreen()
                            clearScreen()
                            centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                            centerText(4, "User: " .. user.name, PALETTE.border)
                            for _, item2 in ipairs(menu) do
                                drawClickableText(math.floor((w-#item2.label)/2)+1, item2.y, item2.label, false)
                            end
                        elseif item.label == "Users" then
                            userManagerScreen(user.name)
                            clearScreen()
                            centerText(2, OS_NAME .. " - Desktop", PALETTE.accent)
                            centerText(4, "User: " .. user.name, PALETTE.border)
                            for _, item2 in ipairs(menu) do
                                drawClickableText(math.floor((w-#item2.label)/2)+1, item2.y, item2.label, false)
                            end
                        elseif item.label == "Logout" then
                            return
                        end
                        break
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
        local users = loadUsers()
        local menu
        if #users == 0 then
            -- Первый запуск: разрешить регистрацию
            menu = {
                {label="Register", y=7},
                {label="Exit", y=11}
            }
        else
            -- После первого пользователя: только логин
            menu = {
                {label="Login", y=7},
                {label="Exit", y=11}
            }
        end
        for _, item in ipairs(menu) do
            drawClickableText(math.floor((w-#item.label)/2)+1, item.y, item.label, false)
        end
        while true do
            local event, b, mx, my = os.pullEvent()
            if event == "mouse_click" and b == 1 then
                for _, item in ipairs(menu) do
                    local x = math.floor((w-#item.label)/2)+1
                    if isInClickable(mx, my, x, item.y, item.label) then
                        if item.label == "Login" then
                            local user = loginScreen()
                            if user then return user end
                        elseif item.label == "Register" then
                            registerScreen()
                            -- После регистрации обновляем список пользователей и предлагаем войти
                            local user
                            repeat
                                user = loginScreen()
                            until user
                            return user
                        elseif item.label == "Exit" then
                            clearScreen()
                            error("Exiting SandTecOS")
                        end
                        break
                    end
                end
            end
        end
    end
end

function loginScreen()
    clearScreen()
    local w, h = term.getSize()
    centerText(2, OS_NAME .. " - Login", PALETTE.accent)
    centerText(4, "Enter your credentials", PALETTE.fg)
    term.setCursorPos(math.floor(w/2)-10, 6)
    term.write("Username: ")
    local username = inputBox(math.floor(w/2), 6, 16, false)
    term.setCursorPos(math.floor(w/2)-10, 8)
    term.write("Password: ")
    local password = inputBox(math.floor(w/2), 8, 16, true)
    local users = loadUsers()
    local user = getUser(users, username)
    if user and user.pass == hashPassword(password) then
        centerText(10, "Login successful!", PALETTE.accent)
        sleep(1)
        return user
    else
        centerText(10, "Invalid credentials!", PALETTE.error)
        sleep(1.5)
        return nil
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
    local users = loadUsers()
    if userExists(users, username) then
        centerText(10, "User already exists!", PALETTE.error)
        sleep(1.5)
        return
    end
    table.insert(users, {name=username, pass=hashPassword(password)})
    saveUsers(users)
    centerText(10, "User registered!", PALETTE.accent)
    sleep(1.5)
end

-- === MAIN LOOP ===
local function main()
    while true do
        local user = authScreen()
        desktopScreen(user)
    end
end

-- === START OS ===
main()
