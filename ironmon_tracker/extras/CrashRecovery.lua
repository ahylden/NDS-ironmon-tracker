local function CrashRecovery(settings)
	local self = {}

	-- INTERNAL VARS
	local _crashReportFormat = "crashedOccurred:%s|gameName:%s|romHash:%s"
	local _crashReportPattern = "crashedOccurred:([^|]*)|gameName:([^|]*)|romHash:([^|]*)"
	local _crashReportFile = Paths.CURRENT_DIRECTORY .. Paths.SLASH .. "ironmon_tracker" .. Paths.SLASH .. "crashreport.txt"
	local _backupFolder = Paths.CURRENT_DIRECTORY .. Paths.SLASH .. "savedData" .. Paths.SLASH .. "crashRecovery" .. Paths.SLASH
	local _hasStarted = false -- Started later, only after the player begins the game
	local _undoTempSaveState = nil -- Once a save is recovered, this holds a save state at the point in time right before that
	local _crashReport = {}

	-- INTERNAL FUNCTIONS
	local function tryAppendSlash(path)
		if (path or "") == "" or path:find("[/\\]$") then
			return path
		end
		return path .. Paths.SLASH
	end
	local function trimSlash(path)
		if (path or "") == "" or not path:find("[/\\]$") then
			return path
		end
		return path:sub(1, -2)
	end
	local function folderExists(path)
		if path == nil or #path == 0 then return false end
		path = tryAppendSlash(path)
		-- A hacky yet simple way to check if a folder exists: try to rename it
		-- The "code" return value only exists in Lua 5.2+, but not required to use here
		local exists, err, code = os.rename(path, path)
		-- Code 13 = Permission denied, but it exists
		if exists or (not exists and code == 13) then
			return true
		end
		return false
	end
	local function createFolder(path)
		if path == nil or #path == 0 then return end
		path = trimSlash(path)
		local command
		if Paths.SLASH == "\\" then -- Windows
			command = string.format('mkdir "%s"', path)
		else -- Linux
			command = string.format('mkdir -p "%s"', path)
		end
		os.execute(command)
	end
	local function getSaveStateFile()
		return _backupFolder .. gameinfo.getromname() .. ".State"
	end

	-- EXTERNAL FUNCTIONS
	function self.initialize()
		-- Make sure the backup save folder exists before using it later
		if not folderExists(_backupFolder) then
			createFolder(_backupFolder)
		end
		_hasStarted = false
		_undoTempSaveState = nil
		_crashReport = {}
	end

	function self.isEnabled()
		return settings.extras.RECOVERY_ENABLED ~= false -- Enabled if setting absent or set to true
	end

	function self.checkCrashStatus()
		_crashReport = self.readCrashReport()

		-- Always establish a new crash report; treat status as "crashed" until emulator safely exits
		self.writeCrashReport(true)

		-- If a crash did occur for this same rom, inform the player and see if they want to recover
		if self.isEnabled() and _crashReport.crashedOccurred and _crashReport.romHash == gameinfo.getromhash() then
			self.openPromptCrashOccurred()
		end
	end

	function self.startSavingBackups()
		if not self.isEnabled() then return end
		_hasStarted = true
	end

	function self.stopSavingBackups()
		_hasStarted = false
	end

	function self.writeCrashReport(crashedOccurred)
		if not self.isEnabled() then return end
		local reportAsString = string.format(_crashReportFormat,
			tostring(crashedOccurred == true),
			gameinfo.getromname(),
			gameinfo.getromhash()
		)
		MiscUtils.writeStringToFile(_crashReportFile, reportAsString)
	end

	function self.readCrashReport()
		-- Default: no crash occurred
		local crashReport = {
			crashedOccurred = false,
			gameName = gameinfo.getromname(),
			romHash = gameinfo.getromhash(),
		}
		if not self.isEnabled() then
			return crashReport
		end

		-- No crash occurred if the file doesn't exist or is empty (was never previously used)
		local reportAsString = MiscUtils.readStringFromFile(_crashReportFile) or ""
		if #reportAsString == 0 then
			return crashReport
		end

		local crash, game, rom = reportAsString:match(_crashReportPattern)
		crashReport.crashedOccurred = (crash == "true")
		if (game or "") ~= "" then
			crashReport.gameName = game
		end
		if (rom or "") ~= "" then
			crashReport.romHash = rom
		end
		return crashReport
	end

	function self.createBackupSaveState()
		if not _hasStarted then return end
		local filepath = getSaveStateFile()
        if not folderExists(_backupFolder) then
			return
		end
		---@diagnostic disable-next-line: undefined-global
		savestate.save(filepath, true) -- true: suppresses the on-screen display message
	end

	function self.recoverSave()
		local filepath = getSaveStateFile()
		if not FormsUtils.fileExists(filepath) then
			return
		end

		-- First create a temporary save state as a way to undo the recovery, if needed
		_undoTempSaveState = {
			id = memorysavestate.savecorestate(),
			timestamp = os.time(),
		}
		-- Then restore the game to the last known crash recovery save state
		---@diagnostic disable-next-line: undefined-global
		savestate.load(filepath, false) -- false: will show the on-screen display message
	end

	function self.undoRecoverSave()
		if type(_undoTempSaveState) ~= "table" or _undoTempSaveState.id == nil then
			return
		end
		memorysavestate.loadcorestate(_undoTempSaveState.id)
		_undoTempSaveState = nil
	end

	function self.openPromptCrashOccurred()
		local form = forms.newform(350, 190, "Crash Detected!", function()
			client.unpause()
		end)
		local clientCenter = FormsUtils.getCenter(350, 190)
		forms.setlocation(form, clientCenter.xPos, clientCenter.yPos)

		local x, y, lineHeight = 20, 20, 20
		local lb1 = forms.label(form, "An emulator or game crash has been detected.", x, y)
		y = y + lineHeight
		local lb2 = forms.label(form, "The Tracker has a recovery save available prior to the crash.", x, y)
		y = y + lineHeight
		local lb3 = forms.label(form, "Load the recovery save?", x, y)
		y = y + lineHeight
		-- Bottom row buttons
		y = y + 10
		local btn1, btn2, btn3, btn4
		btn1 = forms.button(form, "Yes (Recover)", function()
			self.recoverSave()
			forms.setproperty(btn3, "Enabled", true)
		end, 21, y)
		btn2 = forms.button(form, "No (Dismiss)", function()
			forms.destroy(form)
			client.unpause()
		end, 130, y)
		btn3 = forms.button(form, "Undo Recovery", function()
			self.undoRecoverSave()
			forms.setproperty(btn3, "Enabled", false)
		end, 230, y)
		y = y + lineHeight + 15
		btn4 = forms.button(form, "Close / Cancel", function()
			forms.destroy(form)
			client.unpause()
		end, 130, y)

		-- Disable the "Undo" button by default
		forms.setproperty(btn3, "Enabled", false)

		-- Autosize form control elements
		forms.setproperty(lb1, "AutoSize", true)
		forms.setproperty(lb2, "AutoSize", true)
		forms.setproperty(lb3, "AutoSize", true)
		forms.setproperty(btn1, "AutoSize", true)
		forms.setproperty(btn2, "AutoSize", true)
		forms.setproperty(btn3, "AutoSize", true)
		forms.setproperty(btn4, "AutoSize", true)
	end

	return self
end
return CrashRecovery