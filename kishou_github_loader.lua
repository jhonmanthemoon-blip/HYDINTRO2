--// CONFIG ---------------------------------------------------------------
-- 1) Upload the "kishou" folder (001.jpg ... 532.jpg + audio.mp3) to a PUBLIC GitHub repo
-- 2) Fill in the 4 lines below
-- 3) Upload THIS file to the same repo, then run:
--    loadstring(game:HttpGet("https://raw.githubusercontent.com/YOUR_USERNAME/YOUR_REPO/main/kishou_github_loader.lua"))()
local GITHUB_USER   = "jhonmanthemoon-blip"
local GITHUB_REPO   = "HYDINTRO2"
local GITHUB_BRANCH = "main"
local REPO_FOLDER   = "kishou"     -- folder inside the repo that holds the frames + audio

local FOLDER       = "kishou/"     -- local workspace folder (frames are cached here, so the 2nd run is instant)
local SHEET_COUNT  = 532           -- number of image files
local COLS         = 1
local ROWS         = 1
local FPS          = 30
local TOTAL_FRAMES = 532
local LOOP         = false
local AUDIO        = true          -- plays audio.mp3 and keeps the video in sync with it
local RING         = 24            -- images kept in memory at once
local AHEAD        = 20            -- images loaded ahead of the playhead
local WORKERS      = 12            -- parallel downloads

--// SERVICES
local RunService   = game:GetService("RunService")
local Players      = game:GetService("Players")
local SoundService = game:GetService("SoundService")

local framesPerSheet = COLS * ROWS
local BASE = ("https://raw.githubusercontent.com/%s/%s/%s/%s/"):format(GITHUB_USER, GITHUB_REPO, GITHUB_BRANCH, REPO_FOLDER)

local function sheetName(i)
    return FOLDER .. string.format("%03d.jpg", i)
end

--// GUI (full screen)
local playerGui = Players.LocalPlayer:WaitForChild("PlayerGui")
local old = playerGui:FindFirstChild("SheetPlayer")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SheetPlayer"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.DisplayOrder = 999999
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = playerGui

local bg = Instance.new("Frame")
bg.Size = UDim2.fromScale(1, 1)
bg.BackgroundColor3 = Color3.new(0, 0, 0)
bg.BorderSizePixel = 0
bg.Parent = gui

local status = Instance.new("TextLabel")
status.Size = UDim2.fromScale(1, 0.1)
status.Position = UDim2.fromScale(0, 0.45)
status.BackgroundTransparency = 1
status.TextColor3 = Color3.new(1, 1, 1)
status.TextSize = 24
status.Font = Enum.Font.GothamBold
status.Text = "Loading..."
status.ZIndex = 5
status.Parent = bg

local close = Instance.new("TextButton")
close.Size = UDim2.fromOffset(50, 50)
close.Position = UDim2.new(1, -50, 0, 0)
close.Text = "X"
close.TextSize = 24
close.BackgroundColor3 = Color3.fromRGB(200, 40, 40)
close.TextColor3 = Color3.new(1, 1, 1)
close.ZIndex = 10
close.Parent = bg

local conn, sound
local cancelled = false

local function stop()
    cancelled = true
    if conn then conn:Disconnect() end
    if sound then sound:Stop() sound:Destroy() end
    gui:Destroy()
end
close.MouseButton1Click:Connect(stop)

--// DOWNLOAD FROM GITHUB (only files that are not cached yet)
local function httpGet(url)
    local ok, body = pcall(function() return game:HttpGet(url, true) end)
    if ok and type(body) == "string" then return body end
    local req = (syn and syn.request) or (http and http.request) or http_request or request
    if req then
        local ok2, res = pcall(req, {Url = url, Method = "GET"})
        if ok2 and res and res.StatusCode == 200 then return res.Body end
    end
    return nil
end

local folderName = FOLDER:gsub("/$", "")
if not isfolder(folderName) then makefolder(folderName) end

local files = {}
for i = 1, SHEET_COUNT do
    files[#files + 1] = string.format("%03d.jpg", i)
end
if AUDIO then files[#files + 1] = "audio.mp3" end

local need = {}
for _, name in ipairs(files) do
    if not isfile(FOLDER .. name) then need[#need + 1] = name end
end

if #need > 0 then
    local done, failed, nextIdx, running = 0, 0, 1, 0

    local function worker()
        while not cancelled do
            local name = need[nextIdx]
            nextIdx += 1
            if not name then return end

            local body
            for attempt = 1, 4 do
                local b = httpGet(BASE .. name)
                if b and #b > 100 and b:sub(1, 3) ~= "404" then
                    body = b
                    break
                end
                task.wait(0.5 * attempt)
            end

            if body then
                writefile(FOLDER .. name, body)
            else
                failed += 1
                warn("Could not download " .. BASE .. name)
            end
            done += 1
            status.Text = ("Downloading %d / %d"):format(done, #need)
        end
    end

    for _ = 1, WORKERS do
        running += 1
        task.spawn(function()
            worker()
            running -= 1
        end)
    end
    while running > 0 and not cancelled do task.wait(0.1) end
    if cancelled then return end

    if failed > 0 then
        status.Text = ("%d files failed to download - check your repo name/folder and that it is public"):format(failed)
        task.wait(5)
        stop()
        return
    end
end

status:Destroy()

--// IMAGE LABELS
local labels = {}
for i = 1, RING do
    local l = Instance.new("ImageLabel")
    l.Size = UDim2.fromScale(1, 1)
    l.BackgroundTransparency = 1
    l.BorderSizePixel = 0
    l.ScaleType = Enum.ScaleType.Fit
    l.ImageTransparency = 1
    l.Parent = bg
    labels[i] = l
end
close.Parent = nil
close.Parent = bg -- keep the X on top

--// SHEET LOADING
local slotSheet = {}
local slotTime  = {}

local function slotFor(sheet)
    return (sheet % RING) + 1
end

local function assign(sheet)
    if sheet < 1 or sheet > SHEET_COUNT then return end
    local slot = slotFor(sheet)
    if slotSheet[slot] == sheet then return end
    local ok, asset = pcall(getcustomasset, sheetName(sheet))
    if ok and asset and asset ~= "" then
        labels[slot].Image = asset
    else
        warn("Failed to load " .. sheetName(sheet) .. ": " .. tostring(asset))
    end
    slotSheet[slot] = sheet
    slotTime[slot] = os.clock()
end

local function isReady(slot)
    local l = labels[slot]
    return l.IsLoaded or l.ContentImageSize.X > 0 or (slotTime[slot] and os.clock() - slotTime[slot] > 0.05)
end

-- load the first images before starting so playback never waits
for s = 1, AHEAD + 1 do assign(s) end

-- measure the real image size (waits at most 0.3 seconds)
local first = labels[slotFor(1)]
local t0 = os.clock()
while first.ContentImageSize.X == 0 and os.clock() - t0 < 0.3 do task.wait() end

local sheetSize = first.ContentImageSize
if sheetSize.X == 0 then sheetSize = Vector2.new(1024, 576) end
local cellW = math.floor(sheetSize.X / COLS)
local cellH = math.floor(sheetSize.Y / ROWS)

for _, l in ipairs(labels) do
    l.ImageRectSize = Vector2.new(cellW, cellH)
end

--// AUDIO
if AUDIO then
    local ok, asset = pcall(getcustomasset, FOLDER .. "audio.mp3")
    if ok and asset and asset ~= "" then
        sound = Instance.new("Sound")
        sound.SoundId = asset
        sound.Volume = 1
        sound.Parent = SoundService
        local t1 = os.clock()
        while not sound.IsLoaded and os.clock() - t1 < 2 do task.wait() end
        if sound.IsLoaded then
            sound:Play()
        else
            warn("audio.mp3 did not load, playing without sound")
            sound:Destroy()
            sound = nil
        end
    else
        warn("Could not load " .. FOLDER .. "audio.mp3")
    end
end

--// PLAYBACK
local frame = 0

conn = RunService.RenderStepped:Connect(function(dt)
    frame += math.min(dt, 0.1) * FPS

    -- the audio is the master clock, so picture and sound stay in sync
    if sound and sound.IsPlaying then
        local audioFrame = sound.TimePosition * FPS
        if math.abs(frame - audioFrame) > 3 then
            frame = audioFrame
        end
    end

    local f = math.floor(frame)
    if f >= TOTAL_FRAMES then
        if LOOP then
            frame, f = 0, 0
            if sound then sound.TimePosition = 0 end
        else
            stop()
            return
        end
    end

    local sheet = math.floor(f / framesPerSheet) + 1
    local idx = f % framesPerSheet
    local col = idx % COLS
    local row = math.floor(idx / COLS)

    assign(sheet)
    local slot = slotFor(sheet)
    local cur = labels[slot]

    if isReady(slot) then
        cur.ImageRectOffset = Vector2.new(col * cellW, row * cellH)
        cur.ImageTransparency = 0
        for i = 1, RING do
            if i ~= slot then labels[i].ImageTransparency = 1 end
        end
    end

    -- keep the next images loaded ahead of time
    for k = 1, AHEAD do
        assign(sheet + k)
    end
end)
