VERSION = "0.4.1"


local micro = import("micro")
local config = import("micro/config")
local shell = import("micro/shell")
local buffer = import("micro/buffer")
local util = import("micro/util")
local utf8 = import("unicode/utf8")


function init()
    config.MakeCommand("synctex-forward", synctexForward, config.NoComplete)
    config.AddRuntimeFile("latex-plugin-help", config.RTHelp, "help/latex-plugin.md")
end

 

function testHandler(text)
	micro.InfoBar():Message(text)
end


function onBufferOpen(buf)
	isTex = (buf:FileType() == "tex")
	if isTex then
		local fileName = buf:GetName()
		local truncFileName = string.sub(fileName, 1, -5)
		local syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
		local scriptFifoWriteFileName = truncFileName .. ".fifo-writer.sh"
		local scriptFifoWrite = "echo \"$@\" > " .. syncFileName
		local scriptFifoRead = "while true;do if read line; then echo $line; fi;sleep 0.5; done < " .. syncFileName
		
		shell.ExecCommand("mkfifo", syncFileName)
		local f = io.open(scriptFifoWriteFileName, "w")
		f:write(scriptFifoWrite)
		f:close()
		shell.RunCommand("chmod 755 " .. scriptFifoWriteFileName)

		jobFifoRead = shell.JobStart(scriptFifoRead, synctexBackward, nil, dummyFunc)
	end
end


function preSave(bp)
	if isTex then
		isBufferModified = bp.Buf:Modified()
	end
end


function onSave(bp)
	if isTex then
		local isError = lint(bp)
		if not isError then
			if isBufferModified then
				errorMessage = compile(bp)
			end
			synctexForward(bp)
		end
	end
end


function synctexForward(bp)
	local fileName = bp.Buf:GetName()
	local truncFileName = string.sub(fileName, 1, -5)
	local syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
	local scriptFifoWriteFileName = truncFileName .. ".fifo-writer.sh"
	local pdfFileName = truncFileName .. ".pdf"

	local cursor = bp.Buf:GetActiveCursor()
	local zathuraArgPos = string.format(" --synctex-forward=%i:%i:%s", cursor.Y, cursor.X, fileName)
	local zathuraArgSynctexBackward = " --synctex-editor-command=\'" .. scriptFifoWriteFileName .." %{line}\'"
	local zathuraArgFile = " " .. pdfFileName;

	shell.JobStart("zathura" .. zathuraArgSynctexBackward .. zathuraArgPos .. zathuraArgFile, nil, nil, dummyFunc)
end


function synctexBackward(pos)
	local bp = micro.CurPane()
	
	bp:GotoCmd({string.sub(pos, 1, -2)})
end


function lint(bp)
	local fileName = bp.Buf:GetName()
	local truncFileName = string.sub(fileName, 1, -5)

	-- syncex=15 added because otherwise pdflatex cleans up synctex files as well
	local output = shell.RunCommand("pdflatex -synctex 15 -interaction nonstopmode -draftmode -file-line-error " .. truncFileName)
	local error = string.match(output, "[^\n/]+:%w+:[^\n]+")
	if error then
		micro.InfoBar():Message(error)
		local errorPos = string.sub(string.match(error, ":%w+:"), 2, -2)
		micro.CurPane():GotoCmd({errorPos})
		return true
	else
		return false
	end
end


function compile(bp)
	local fileName = bp.Buf:GetName()
	local truncFileName = string.sub(fileName, 1, -5)
	
	shell.RunCommand("bibtex " .. truncFileName)
	shell.RunCommand("pdflatex -synctex 15 -interaction nonstopmode -draftmode " .. truncFileName)
	shell.RunCommand("pdflatex -synctex 15 -interaction nonstopmode " .. truncFileName)
end


function preQuit(bp)
	if isTex then
		local fileName = bp.Buf:GetName()
		local truncFileName = string.sub(fileName, 1, -5)
		local syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
		local scriptFifoWriteFileName = truncFileName .. ".fifo-writer.sh"

		shell.JobStop(jobFifoRead)
		shell.RunCommand("rm " .. syncFileName)
		shell.RunCommand("rm " .. scriptFifoWriteFileName)
	end
end


function dummyFunc()

end
