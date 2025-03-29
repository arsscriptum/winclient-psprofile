#╔════════════════════════════════════════════════════════════════════════════════╗
#║                                                                                ║
#║   ProcessData.ps1                                                              ║
#║                                                                                ║
#╟────────────────────────────────────────────────────────────────────────────────╢
#║   Guillaume Plante <codegp@icloud.com>                                         ║
#║   Code licensed under the GNU GPL v3.0. See the LICENSE file for details.      ║
#╚════════════════════════════════════════════════════════════════════════════════╝


function Get-ScriptEncodeAppCredentials {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $false)]
        [switch]$TestMode
    )
    $ErrorOccured = $false

    try {
        $cmd = Get-Command 'Get-AppCredentials' -ErrorAction Stop
        $id = 'scripts-encode'
        if($TestMode){
            $id += '-test'
        }
        $Data = & $cmd -Id $id
        if ($Data -eq $Null) {
           Write-Warning "You are missing the `"$id`" App Credentials registration..."
        }  
        return $Data
    }catch {
        Write-Warning "You are missing the function `"Get-AppCredentials`" load the Core module..."
        $ErrorOccured = $true
    }

    return $Null
}

function Update-VersionNumber {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    $RootPath = (Resolve-Path -Path "$PSScriptRoot\..").Path
    $VerFilePath = Join-Path $RootPath 'version.nfo'
    $pattern_version = "(?<fullver>(?<major>\d+)+\.((?<minor>\d+))+\.((?<patch>\d+))*(\.(?<build>\d+))*)"
    [string[]]$data = (Get-Content -Path $VerFilePath)
    if ($data[0] -match $pattern_version) {
        [version]$VersionNum = $Matches.fullver
        [version]$NewVersion = [version]::new($VersionNum.Major, $VersionNum.Minor, $VersionNum.Build + 1)

        $NewVersion.ToString() | Set-Content -Path $VerFilePath

        [version]$VersionNum = Get-Content -Path $VerFilePath -Raw
        Write-Host "Updated Version To $($VersionNum.ToString())"

    } else {
        Write-Error "No Version in versin file"
    }
}

function Invoke-AutoUpdateProgress_FileUtils {
    [int32]$PercentComplete = (($Script:StepNumber / $Script:TotalSteps) * 100)
    if ($PercentComplete -gt 100) { $PercentComplete = 100 }
    Write-Progress -Activity $Script:ProgressTitle -Status $Script:ProgressMessage -PercentComplete $PercentComplete
    if ($Script:StepNumber -lt $Script:TotalSteps) { $Script:StepNumber++ }
}

function Invoke-SplitDataFile {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $false)]
        [int64]$Newsize = 1MB,
        [Parameter(Mandatory = $false)]
        [string]$OutPath,
        [Parameter(Mandatory = $false)]
        [string]$Extension = "cpp",
        [Parameter(Mandatory = $false)]
        [switch]$AsString
    )

    if ($Newsize -le 0)
    {
        Write-Error "Only positive sizes allowed"
        return
    }

    $FileSize = (Get-Item $Path).Length
    $SyncStopWatch = [System.Diagnostics.Stopwatch]::StartNew()
    $Script:ProgressTitle = "Split Files"
    $TotalTicks = 0
    $Count = [math]::Round($FileSize / $Newsize)
    $Script:StepNumber = 1
    $Script:TotalSteps = $Count + 3
    if ($PSBoundParameters.ContainsKey('OutPath') -eq $False) {
        $OutPath = [IO.Path]::GetDirectoryName($Path)

        Write-Verbose "Using OutPath from Path $Path"
    } else {
        Write-Verbose "Using OutPath $OutPath"
    }
    $OutPath = $OutPath.TrimEnd('\')

    if (-not (Test-Path -Path "$OutPath")) {
        Write-Verbose "CREATING $OutPath"
        $Null = New-Item $OutPath -ItemType Directory -Force -ErrorAction Ignore
    }

    $FILENAME = [IO.Path]::GetFileNameWithoutExtension($Path)


    $MAXVALUE = 1GB # Hard maximum limit for Byte array for 64-Bit .Net 4 = [INT32]::MaxValue - 56, see here https://stackoverflow.com/questions/3944320/maximum-length-of-byte
    # but only around 1.5 GB in 32-Bit environment! So I chose 1 GB just to be safe
    $PASSES = [math]::Floor($Newsize / $MAXVALUE)
    $REMAINDER = $Newsize % $MAXVALUE
    if ($PASSES -gt 0) { $BUFSIZE = $MAXVALUE } else { $BUFSIZE = $REMAINDER }

    $OBJREADER = New-Object System.IO.BinaryReader ([System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read))
    [Byte[]]$BUFFER = New-Object Byte[] $BUFSIZE
    $NUMFILE = 1

    do {
        $Extension = $Extension.TrimStart('.')
        $NEWNAME = "{0}\{1}{2,2:00}.{3}" -f $OutPath, $FILENAME, $NUMFILE, $Extension
        $Script:ProgressMessage = "Split {0} of {1} files" -f $Script:StepNumber, $Script:TotalSteps
        Invoke-AutoUpdateProgress_FileUtils
        $Script:StepNumber++
        $COUNT = 0
        $OBJWRITER = $NULL
        [int32]$BYTESREAD = 0
        while (($COUNT -lt $PASSES) -and (($BYTESREAD = $OBJREADER.Read($BUFFER, 0, $BUFFER.Length)) -gt 0))
        {
            Write-Verbose " << READING $BYTESREAD bytes"
            if ($AsString) {
                $DataString = [convert]::ToBase64String($BUFFER, 0, $BYTESREAD)
                Write-Verbose "   >>> WRITING DataString to $NEWNAME"
                Set-Content $NEWNAME $DataString
            } else {
                if (!$OBJWRITER)
                {
                    $OBJWRITER = New-Object System.IO.BinaryWriter ([System.IO.File]::Create($NEWNAME))
                    Write-Verbose " + CREATING $NEWNAME"
                }
                Write-Verbose "   >>> WRITING $BYTESREAD bytes to $NEWNAME"
                $OBJWRITER.Write($BUFFER, 0, $BYTESREAD)
            }
            $COUNT++
        }
        if (($REMAINDER -gt 0) -and (($BYTESREAD = $OBJREADER.Read($BUFFER, 0, $REMAINDER)) -gt 0))
        {
            Write-Verbose " << READING $BYTESREAD bytes"
            if ($AsString) {
                $DataString = [convert]::ToBase64String($BUFFER, 0, $BYTESREAD)
                Write-Verbose "   >>> WRITING DataString to $NEWNAME"
                Set-Content $NEWNAME $DataString
            } else {
                if (!$OBJWRITER)
                {
                    $OBJWRITER = New-Object System.IO.BinaryWriter ([System.IO.File]::Create($NEWNAME))
                    Write-Verbose " + CREATING $NEWNAME"
                }
                Write-Verbose "   >>> WRITING $BYTESREAD bytes to $NEWNAME"
                $OBJWRITER.Write($BUFFER, 0, $BYTESREAD)
            }
        }

        if ($OBJWRITER) { $OBJWRITER.Close() }
        ++ $NUMFILE
    } while ($BYTESREAD -gt 0)

    $OBJREADER.Close()
}

function Split-DataFile {

    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [string]$FilePath,
        [Parameter(Position = 1, Mandatory = $true)]
        [string]$DestinationPath,
        [Parameter(Mandatory = $false)]
        [ValidateSet("Binary", "Base64")]
        [string]$OutputType = "Base64",
        [Parameter(Mandatory = $false)]
        [uint32]$Size = 0
    )

    begin {
        if (-not (Test-Path -Path "$DestinationPath" -PathType Container)) {
            $Null = New-Item -Path "$DestinationPath" -ItemType Directory -Force -ErrorAction Ignore
        }
        $ArchiveDataPath = Join-Path $DestinationPath '.dat'
        $ArchiveDataFile = Join-Path $ArchiveDataPath 'validate'

        $Hash = (Get-FileHash $FilePath -Algorithm SHA1).Hash
        $FileLength = (gi -Path "$FilePath").Length

        Write-Verbose "File Hash  $Hash"
        Write-Verbose "FileLength $FileLength"

        if ($Size -eq 0) {
            $Size = $FileLength / 10
            Write-Verbose "Size not set, using $Size bytes"
        }
    }
    process {
        try {
            [string]$strdata = '{0}|{1}' -f $FileLength, $Hash
            New-Item -Path $ArchiveDataFile -ItemType File -Value $strdata -Force -ErrorAction Ignore | Out-Null
            $IsString = $False
            if ($OutputType -eq "Base64") { $IsString = $True }
            Invoke-SplitDataFile -Path "$FilePath" -Newsize $Size -OutPath "$DestinationPath" -AsString:$IsString
        } catch {
            Write-Error "$_"
        }
    }
}


function Import-DataFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateScript({ if (Test-Path $_ -PathType Container) { $true } else { throw "Path $_ is not valid" } })]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$OutFile,

        [Parameter(Position = 2, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key,

        [Parameter(Mandatory = $False)]
        [string]$Filter = "*", # Default: all files

        [Parameter(Mandatory = $False)]
        [string[]]$Exclude = @() # Default: no exclusions
    )

    try {
        # Generate a temporary archive file
        $TempArchive = [System.IO.Path]::GetTempFileName() + ".zip"

        # Get files based on filter and exclusions
        $files = Get-ChildItem -Path $Path -Filter $Filter -File | Where-Object {
            $Exclude -notcontains $_.Name
        }

        $NumFiles = $files.Count

        if ($NumFiles -eq 0) {
            Write-Error " ❌ No matching files found in the directory."
            return
        }

        Write-Host "Packaging $NumFiles files from $Path"

        # Compress files into the archive
        Compress-Archive -Path $files.FullName -DestinationPath $TempArchive -Force

        # Convert the key into a byte array
        $KeyBytes = [System.Text.Encoding]::UTF8.GetBytes($Key)

        # Ensure key is 32 bytes for AES-256
        if ($KeyBytes.Length -lt 32) {
            $KeyBytes = $KeyBytes + (New-Object byte[] (32 - $KeyBytes.Length))
        } elseif ($KeyBytes.Length -gt 32) {
            $KeyBytes = $KeyBytes[0..31]
        }

        $IV = New-Object byte[] 16 # Create a byte array of 16 bytes for the IV
        [System.Security.Cryptography.RNGCryptoServiceProvider]::Create().GetBytes($IV)

        Write-Host " ⚡ Encrypt the archive using AES-256"
        $Aes = [System.Security.Cryptography.AesManaged]::new()
        $Aes.Key = $KeyBytes
        $Aes.IV = $IV
        $Aes.Mode = [System.Security.Cryptography.CipherMode]::CBC
        $Aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7

        $Encryptor = $Aes.CreateEncryptor()
        $FileBytes = [System.IO.File]::ReadAllBytes($TempArchive)
        $EncryptedBytes = $Encryptor.TransformFinalBlock($FileBytes, 0, $FileBytes.Length)

        # Write IV and encrypted data to output file
        $FinalBytes = $IV + $EncryptedBytes
        [System.IO.File]::WriteAllBytes($OutFile, $FinalBytes)

        # Cleanup temporary archive
        Remove-Item -Path $TempArchive -Force

        Write-Host " ✔️ Encryption complete!" -f DarkGreen
    }
    catch {
        Show-ExceptionDetails ($_) -ShowStack
    }
}




function Invoke-EncodeFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Position = 0, Mandatory = $true)]
        [ValidateScript({ if (Test-Path $_ -PathType Container) { $true } else { throw "Path $_ is not valid" } })]
        [string]$Path,

        [Parameter(Position = 1, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$DestinationPath,

        [Parameter(Position = 2, Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Key
    )

    $RootPath = (Resolve-Path -Path "$PSScriptRoot\..").Path
    $TmpPath = Join-Path $RootPath '_tmp'
    $TmpArchiveFilePath = Join-Path $TmpPath 'archive.enc'

    Remove-Item -Path $TmpPath -Recurse -Force -ErrorAction Ignore | Out-Null
    New-Item -Path $TmpPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null

    Remove-Item -Path $DestinationPath -Recurse -Force -ErrorAction Ignore | Out-Null
    New-Item -Path $DestinationPath -ItemType Directory -Force -ErrorAction Ignore | Out-Null
    Import-DataFiles -Path "$Path" -OutFile "$TmpArchiveFilePath" -Key "$Key" -Filter "*.ps1"


    Split-DataFile -FilePath "$TmpArchiveFilePath" -DestinationPath $DestinationPath -Size 5KB
    Write-Host "Cleaning temporary folder..."
    $TmpPath = Join-Path $RootPath '_tmp'
    Remove-Item -Path $TmpPath -Recurse -Force -ErrorAction Ignore | Out-Null

}



function Start-EncodeFiles {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory = $False)]
        [string]$OptionalPassword
    )
    

    $Data = Get-ScriptEncodeAppCredentials
    if ($Data -eq $Null) {
        Write-Error "missing app reg"
    }

    $GlobalScriptsDirectory = $Data.UserName
    $DataClearPath = $GlobalScriptsDirectory


    $RootPath = (Resolve-Path -Path "$PSScriptRoot\..").Path
    $DataCipherPath = Join-Path $RootPath 'data'
    if ($OptionalPassword) {
        $Password = $OptionalPassword
    } else {
        $Password = $Data.GetNetworkCredential().Password
    }
    Invoke-EncodeFiles -Path "$GlobalScriptsDirectory" -DestinationPath "$DataCipherPath" -Key "$Password"
}

function Invoke-EncodeAllNewScripts {
    [CmdletBinding(SupportsShouldProcess)]
    param()
    $RootPath = (Resolve-Path -Path "$PSScriptRoot\..").Path
    $DataCipherPath = Join-Path $RootPath 'data'
    pushd $RootPath

    Start-EncodeFiles
    Update-VersionNumber
    try{
      $cmd = Get-Command 'Push-Changes' -ErrorAction Stop
      & $cmd 
    }catch{
       Write-Error "Missing Push Command: Load the Github module"
    }
}

set-alias -Name DoEncodeNewScripts -Value 'Invoke-EncodeAllNewScripts' -Option AllScope -Force -ErrorAction Ignore
