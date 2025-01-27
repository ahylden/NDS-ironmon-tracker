NetworkUtils = {}

local JSON_FILENAME = "Json.lua"

---@return string guid
function NetworkUtils.newGUID()
	local template ='xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
	return (string.gsub(template, '[xy]', function (c)
		local v = (c == 'x') and math.random(0, 0xf) or math.random(8, 0xb)
		return string.format('%x', v)
	end))
end

---Does a simple check to see if a folder at `folderpath` exists on the file system
---@param folderpath string
---@return boolean
function NetworkUtils.folderExists(folderpath)
	if (folderpath or "") == "" then return false end
	if not folderpath:find("[/\\]$") then
		folderpath = folderpath .. Paths.SLASH
	end

	-- Hacky but simply way to check if a folder exists: try to rename it
	-- The "code" return value only exists in Lua 5.2+, but not required to use here
	local exists, err, code = os.rename(folderpath, folderpath)
	-- Code 13 = Permission denied, but it exists
	return exists or (not exists and code == 13)
end

---Checks if some text contains some other text; ignores case by default
---@param text? string
---@param searchString? string
---@param matchCase? boolean
---@return boolean
function NetworkUtils.containsText(text, searchString, matchCase)
	if text == nil or text == "" or searchString == nil then
		return false
	end
	if not matchCase then
		text = text:lower()
		searchString = searchString:lower()
	end
	-- Check whole word for matches, not just the start
	return text:find(searchString, 1, true) ~= nil
end

---Searches `wordlist` for the closest matching `word` based on Levenshtein distance.
---If the minimum distance is greater than the `threshold`, the original 'word' is returned and key is nil
---https://stackoverflow.com/questions/42681501/how-do-you-make-a-string-dictionary-function-in-lua
---@param word string
---@param wordlist table
---@param threshold number
---@return any key
---@return any result
---@return number distance
function NetworkUtils.getClosestWord(word, wordlist, threshold)
	if word == nil or word == "" then
		return word, nil, -1
	end
	threshold = threshold or 3
	local function min(a, b, c) return math.min(math.min(a, b), c) end
	local function matrix(row, col)
		local m = {}
		for i = 1, row do
			m[i] = {}
			for j = 1, col do
				m[i][j] = 0
			end
		end
		return m
	end
	local function lev(strA, strB)
		local M = matrix(#strA + 1, #strB + 1)
		local cost
		local row, col = #M, #M[1]
		for i = 1, row do M[i][1] = i - 1 end
		for j = 1, col do M[1][j] = j - 1 end
		for i = 2, row do
			for j = 2, col do
				if (strA:sub(i-1, i-1) == strB:sub(j-1, j-1)) then cost = 0
				else cost = 1
				end
				M[i][j] = min(M[i-1][j] + 1, M[i][j-1] + 1, M[i-1][j-1] + cost)
			end
		end
		return M[row][col]
	end
	local closestDistance = 9999999
	local closestWordKey
	for key, val in pairs(wordlist) do
		local levRes = lev(word, val)
		if levRes < closestDistance then
			closestDistance = levRes
			closestWordKey = key
			if closestDistance == 0 then -- exact match
				break
			end
		end
	end
	if closestDistance <= threshold then
		return closestWordKey, wordlist[closestWordKey], closestDistance
	end
	return nil, word, closestDistance
end

--- Alters the string by changing the first character of each word to uppercase
---@param str string?
---@return string?
function NetworkUtils.firstToUpperEachWord(str)
	if str == nil or str == "" then return str end
	str = string.gsub(" " .. str, "[%s%.%-]%l", string.upper):sub(2)
	return str
end

--- Loads the external Json library into NetworkUtils.JsonLibrary
---@param forceLoad? boolean Optional, if true, forces the file to get reloaded even if already loaded
function NetworkUtils.setupJsonLibrary(forceLoad)
	-- Skip loading if already loaded
	if type(NetworkUtils.JsonLibrary) == "table" and not forceLoad then
		return
	end
	local filepath = Paths.FOLDERS.NETWORK_FOLDER .. Paths.SLASH .. JSON_FILENAME
	if FormsUtils.fileExists(filepath) then
		NetworkUtils.JsonLibrary = dofile(filepath)
		if type(NetworkUtils.JsonLibrary) ~= "table" then
			NetworkUtils.JsonLibrary = nil
		end
	end
end

--- Returns true if data is written to file, false if resulting json is empty, or nil if no file
---@param filepath string
---@param data table
---@return boolean|nil dataWritten
function NetworkUtils.encodeToJsonFile(filepath, data)
	local file = filepath and io.open(filepath, "w")
	if not file then
		return nil
	end
	if not NetworkUtils.JsonLibrary then
		return false
	end
	-- Empty Json is "[]"
	local output = "[]"
	pcall(function()
		output = NetworkUtils.JsonLibrary.encode(data) or "[]"
	end)
	file:write(output)
	file:close()
	return (#output > 2)
end

--- Returns a lua table of the decoded json string from a file, or nil if no file
---@param filepath string
---@return table|nil data
function NetworkUtils.decodeJsonFile(filepath)
	local file = filepath and io.open(filepath, "r")
	if not file then
		return nil
	end
	if not NetworkUtils.JsonLibrary then
		return {}
	end
	local input = file:read("*a") or ""
	file:close()
	local decodedTable = {}
	if #input > 0 then
		pcall(function()
			decodedTable = NetworkUtils.JsonLibrary.decode(input) or {}
		end)
	end
	return decodedTable
end