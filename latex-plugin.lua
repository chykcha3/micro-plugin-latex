VERSION = "0.2.0"


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
		fileName = buf:GetName()
		truncFileName = string.sub(fileName, 0, string.len(fileName) - 4)
		syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
		scriptFifoWriteFileName = truncFileName .. ".fifo-writer.sh"
		local scriptFifoWrite = "echo \"$@\" > " .. syncFileName
		local scriptFifoRead = "while true;do if read line; then echo $line; fi;sleep 1; done < " .. syncFileName
		
		shell.ExecCommand("mkfifo", syncFileName)
		local f = io.open(scriptFifoWriteFileName, "w")
		f:write(scriptFifoWrite)
		f:close()
		shell.RunCommand("chmod 755 " .. scriptFifoWriteFileName)

		shell.JobStart(scriptFifoRead, synctexBackward, nil, dummyFunc)
	end
end


function onSave(bp)
	if isTex then
		if bp.Buf:Modified() then
			compile(bp)
		end
		synctexForward(bp, nil)
	end
end


function synctexForward(bp)
	local syncFileName = truncFileName .. ".synctex.from-zathura-to-micro"
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

end


function dummyFunc()

end
