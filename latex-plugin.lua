VERSION = "0.3.2"


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
		local truncFileName = string.sub(fileName, 0, string.len(fileName) - 4)
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
		if isBufferModified then
			errorMessage = compile(bp)
		end
		synctexForward(bp)
	end
end


function synctexForward(bp)
	local fileName = bp.Buf:GetName()
	local truncFileName = string.sub(fileName, 0, string.len(fileName) - 4)
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
	
	bp:GotoCmd({string.sub(pos, 0, string.len(pos) - 1)})
end


function compile(bp)
	local fileName = bp.Buf:GetName()
	shell.RunCommand("pdflatex -synctex 0 -interaction nonstopmode -draftmode " .. fileName)
	local output = shell.RunCommand("pdflatex -synctex 15 -interaction nonstopmode -file-line-error " .. fileName)
	
	local error = string.match(output, "[^\n/]+:%w+:[^\n]+")
	local time = string.match(output, "[^\nreal ]:%w+:[^\n]+")
	if error then
		micro.InfoBar():Message(error)
	else
		micro.InfoBar():Message("ok!")
	end
end


function preQuit(bp)
	if isTex then
		local fileName = bp.Buf:GetName()
		local truncFileName = string.sub(fileName, 0, string.len(fileName) - 4)
		local syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
		local scriptFifoWriteFileName = truncFileName .. ".fifo-writer.sh"

		shell.JobStop(jobFifoRead)
		shell.RunCommand("rm " .. syncFileName)
		shell.RunCommand("rm " .. scriptFifoWriteFileName)
	end
end


function dummyFunc()

end
