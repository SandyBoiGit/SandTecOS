local NOTE_FILE = "notes.json"
local USER_FILE = "auth.txt"

local function hash(str)
    local sum = 0
    for i = 1, #str do
        sum = (sum + string.byte(str, i)) % 65536
    end
    return tostring(sum)
end

local function getTimestamp()
    return os.date("%Y-%m-%d %H:%M:%S")
end

local function loadUsers()
    if fs.exists(USER_FILE) then
        local f = fs.open(USER_FILE, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        return data or {}
    end
    return {}
end

local function saveUsers(users)
    local f = fs.open(USER_FILE, "w")
    f.write(textutils.serialize(users))
    f.close()
end

local function setupUser()
    local users = loadUsers()
    if next(users) == nil then
        term.clear()
        term.setCursorPos(1,1)
        print("=== First launch ===")
        write("Username: ")
        local name = read()
        write("Password: ")
        local pass = read("*")
        users[name] = hash(pass)
        saveUsers(users)
        print("User created.")
        sleep(1)
    end
end

local function guiInput(x, y, w, hidden)
    local input = ""
    while true do
        term.setCursorPos(x, y)
        term.write(string.rep(" ", w))
        term.setCursorPos(x, y)
        if hidden then
            term.write(string.rep("*", #input))
        else
            term.write(input)
        end
        local event, key = os.pullEvent()
        if event == "char" and #input < w then
            input = input .. key
        elseif event == "key" then
            if key == keys.enter then
                break
            elseif key == keys.backspace then
                input = input:sub(1, -2)
            end
        end
    end
    return input
end

local function loginScreen()
    while true do
        term.setBackgroundColor(colors.gray)
        term.clear()
        term.setTextColor(colors.white)
        local w, h = term.getSize()
        term.setCursorPos(math.floor(w/2) - 5, math.floor(h/2) - 3)
        print("Authorization")
        -- Добавил пробелы после меток для отделения от поля ввода
        term.setCursorPos(math.floor(w/2) - 10, math.floor(h/2) - 1)
        write("Username: ")
        local name = guiInput(math.floor(w/2) - 10 + 10, math.floor(h/2) - 1, 14, false)
        term.setCursorPos(math.floor(w/2) - 10, math.floor(h/2))
        write("Password: ")
        local pass = guiInput(math.floor(w/2) - 10 + 10, math.floor(h/2), 14, true)

        local users = loadUsers()
        if users[name] and users[name] == hash(pass) then
            term.setBackgroundColor(colors.black)
            term.clear()
            return name
        else
            term.setCursorPos(math.floor(w/2) - 8, math.floor(h/2) + 2)
            term.setTextColor(colors.red)
            print("Invalid credentials!")
            sleep(1.5)
        end
    end
end

local function loadNotes()
    if not fs.exists(NOTE_FILE) then
        return {}
    end
    local f = fs.open(NOTE_FILE, "r")
    local data = textutils.unserialize(f.readAll())
    f.close()
    return data or {}
end

local function saveNotes(notes)
    local f = fs.open(NOTE_FILE, "w")
    f.write(textutils.serialize(notes))
    f.close()
end

local function createNote()
    term.clear()
    term.setCursorPos(1,1)
    write("Note title: ")
    local name = read()
    print("Enter text (empty line to finish):")
    local lines = {}
    while true do
        local line = read()
        if line == "" then break end
        table.insert(lines, line)
    end
    local notes = loadNotes()
    notes[name] = {
        text = lines,
        time = getTimestamp()
    }
    saveNotes(notes)
    print("Saved.")
    sleep(1)
end

local function readNote()
    local notes = loadNotes()
    term.clear()
    print("Notes list:")
    for k, _ in pairs(notes) do
        print(" - " .. k)
    end
    write("Note title to read: ")
    local name = read()
    if notes[name] then
        local pageSize = 8
        local page = 1
        local total = math.ceil(#notes[name].text / pageSize)
        while true do
            term.clear()
            print("=== " .. name .. " ===")
            print("Created: " .. notes[name].time .. "\n")
            for i = (page - 1) * pageSize + 1, math.min(page * pageSize, #notes[name].text) do
                print(notes[name].text[i])
            end
            print(string.format("\n[Page %d/%d] ←/→ or q", page, total))
            local e, key = os.pullEvent("key")
            if key == keys.left and page > 1 then
                page = page - 1
            elseif key == keys.right and page < total then
                page = page + 1
            elseif key == keys.q then
                break
            end
        end
    else
        print("Note not found.")
        sleep(1)
    end
end

local function deleteNote()
    local notes = loadNotes()
    write("Note title to delete: ")
    local name = read()
    if notes[name] then
        notes[name] = nil
        saveNotes(notes)
        print("Deleted.")
    else
        print("Note not found.")
    end
    sleep(1)
end

local function drawButton(x, y, label)
    term.setCursorPos(x, y)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.write("[" .. label .. "]")
    term.setBackgroundColor(colors.black)
end

local function manageUsers()
    local users = loadUsers()
    local actions = { "Add", "Delete", "Change password", "Back" }

    while true do
        term.clear()
        term.setCursorPos(2,1)
        term.setTextColor(colors.cyan)
        print("User management")

        for i, a in ipairs(actions) do
            drawButton(4, 2 + i * 2, a)
        end

        local event, button, x, y = os.pullEvent("mouse_click")
        for i, a in ipairs(actions) do
            if y == 2 + i * 2 and x >= 4 and x <= 4 + #a + 1 then
                if a == "Add" then
                    term.clear()
                    term.setCursorPos(1,1)
                    write("New username: ")
                    local name = read()
                    if users[name] then
                        print("Already exists.")
                    else
                        write("Password: ")
                        local pass = read("*")
                        users[name] = hash(pass)
                        saveUsers(users)
                        print("Added.")
                    end
                    sleep(1)

                elseif a == "Delete" then
                    term.clear()
                    term.setCursorPos(1,1)
                    write("Username to delete: ")
                    local name = read()
                    if users[name] then
                        users[name] = nil
                        saveUsers(users)
                        print("Deleted.")
                    else
                        print("Not found.")
                    end
                    sleep(1)

                elseif a == "Change password" then
                    term.clear()
                    term.setCursorPos(1,1)
                    write("Username: ")
                    local name = read()
                    if users[name] then
                        write("New password: ")
                        local pass = read("*")
                        users[name] = hash(pass)
                        saveUsers(users)
                        print("Updated.")
                    else
                        print("User not found.")
                    end
                    sleep(1)

                elseif a == "Back" then
                    return
                end
            end
        end
    end
end

local function mainMenu(user)
    local options = { "Create", "Read", "Delete", "Users", "Exit" }
    while true do
        term.clear()
        term.setCursorPos(2,1)
        term.setTextColor(colors.yellow)
        print("Welcome, " .. user)
        for i, opt in ipairs(options) do
            drawButton(4, 2 + i * 2, opt)
        end
        while true do
            local event, button, x, y = os.pullEvent("mouse_click")
            for i, opt in ipairs(options) do
                if y == 2 + i * 2 and x >= 4 and x <= 4 + #opt + 1 then
                    if opt == "Create" then
                        createNote()
                    elseif opt == "Read" then
                        readNote()
                    elseif opt == "Delete" then
                        deleteNote()
                    elseif opt == "Users" then
                        manageUsers()
                    elseif opt == "Exit" then
                        os.reboot()
                    end
                    break
                end
            end
            break
        end
    end
end

term.setCursorBlink(false)
setupUser()
local user = loginScreen()
mainMenu(user)
