function paschwords ($database, $keyfile, [switch]$noclip) {# Password Manager.

function initialize {# Load the user configuration.
$script:database = $database; $script:keyfile = $keyfile; $script:powershell = Split-Path $profile; $basemodulepath = Join-Path $script:powershell "Modules\Paschwords"; $script:configpath = Join-Path $basemodulepath "Paschwords.psd1"

if (!(Test-Path $script:configpath)) {throw "Config file not found at $script:configpath"}
$config = Import-PowerShellDataFile -Path $configpath

# Initialize Hash, Key and Database directories.
$script:keydir = $config.PrivateData.keydir; $script:defaultkey = $config.PrivateData.defaultkey; $script:keydir = $script:keydir -replace 'DefaultPowerShellDirectory', [regex]::Escape($powershell); $script:defaultkey = Join-Path $script:keydir $script:defaultkey

$script:databasedir = $config.PrivateData.databasedir; $script:defaultdatabase = $config.PrivateData.defaultdatabase; $script:databasedir = $script:databasedir -replace 'DefaultPowerShellDirectory', [regex]::Escape($powershell); $script:defaultdatabase = Join-Path $script:databasedir $script:defaultdatabase

$script:privilegedir = $config.PrivateData.privilegedir; $script:privilegedir = $script:privilegedir -replace 'DefaultPowerShellDirectory', [regex]::Escape($powershell)

# Import PSD1 settings.
$script:version = $config.ModuleVersion
$script:delayseconds = $config.PrivateData.delayseconds
$script:timeoutseconds = $config.PrivateData.timeoutseconds; if ([int]$script:timeoutseconds -gt 5940 -or [int]$script:timeoutseconds -lt 0) {$script:timeoutseconds = 5940}
$script:timetobootlimit = $config.PrivateData.timetobootlimit; if ([int]$script:timetobootlimit -gt 120 -or [int]$script:timetobootlimit -lt 0) {$script:timetobootlimit = 120}
$script:expirywarning = $config.PrivateData.expirywarning; if ([int]$script:expirywarning -gt 365 -or [int]$script:expirywarning -lt 0) {$script:expirywarning = 365}
$script:logretention = $config.PrivateData.logretention; if ([int]$script:logretention -lt 30) {$script:logretention = 30}
$script:dictionaryfile = $config.PrivateData.dictionaryfile; $script:dictionaryfile = Join-Path $basemodulepath $script:dictionaryfile
$script:backupfrequency = $config.PrivateData.backupfrequency
$script:archiveslimit = $config.PrivateData.archiveslimit
$script:useragent = $config.PrivateData.useragent

# Initialize privilege settings.
$script:rootKeyFile = "$privilegedir\root.key"; $script:hashFile = "$privilegedir\password.hash"; $script:registryFile = Join-Path $privilegedir "registry.db"; $script:loggedinuser = $null

# Initialize non-PSD1 variables.
$script:failedmaster = 0; $script:lockoutmaster = $false; $script:keypasscount = Get-Random -Minimum 3 -Maximum 50; $script:message = $null; $script:warning = $null; neuralizer; $script:sessionstart = Get-Date; $script:lastrefresh = 1000; $script:management = $false; $script:quit = $false; $script:timetoboot = $null; $script:noclip = $noclip; $script:disablelogging = $false; $script:logdir = Join-Path $PSScriptRoot 'logs'; $script:thisscript = (Get-FileHash -Algorithm SHA256 -Path $PSCommandPath).Hash; $hashcheck = $true; $script:ntpscript = (Get-FileHash -Algorithm SHA256 -Path $PSScriptRoot\CheckNTPTime.ps1).Hash}

function setdefaults {# Set Key and Database defaults.
# Check database validity.
if (-not $script:database -or -not (Test-Path $script:database -ea SilentlyContinue)) {$script:database = $script:defaultdatabase}
if ($script:database) {if (-not [System.IO.Path]::IsPathRooted($script:database)) {$script:database = Join-Path $script:databasedir $script:database}}

# Check key validity, but allow the menu to load, even if there is no default key.
$script:keyexists = $true
if ($script:keyfile -and -not [System.IO.Path]::IsPathRooted($script:keyfile)) {$script:keyfile = Join-Path $script:keydir $script:keyfile}
if (-not $script:keyfile -or -not (Test-Path $script:keyfile -ea SilentlyContinue)) {$script:keyfile = $script:defaultkey}
if (-not (Test-Path $script:keyfile -ea SilentlyContinue) -and -not (Test-Path $script:defaultkey -ea SilentlyContinue)) {$script:keyexists = $false; $script:keyfile = $null; $script:database = $null}}

function verify {# Check the current time and current file hash against all valid versions.
$hashFile = Join-Path $privilegedir 'validhashes.sha256'

if (-not (Test-Path $hashFile)) {Write-Host -f red "`n`t    WARNING: " -n; Write-Host -f white "Hash file not found.`n`t    Cannot verify script integrity." -n}
else {$validHashes = Get-Content $hashFile | ForEach-Object { $_.Trim()} | Where-Object {$_ -ne ''}
if ($validHashes -notcontains $script:thisscript) {Write-Host -f red "`nWARNING: " -n; Write-Host -f yellow "This script has been tampered with. Do not trust it!`n"; return $false}
if ($validHashes -notcontains $script:ntpscript) {Write-Host -f red "`nWARNING: " -n; Write-Host -f yellow "The NTP script used to validate the current time has been tampered with. Do not trust it!`n"; return $false}
else {Write-Host -f green "`nFirst stage of validation complete."}}

if (Test-Path $PSScriptRoot\CheckNTPTime.ps1) {$timecheck = & "$PSScriptRoot\CheckNTPTime.ps1"}
if ($timecheck) {Write-Host -f green "Second stage of validation complete."}
else {Write-Host -f red "Aborting due to untrusted system clock.`n"; return $false}

return $true}

function resizewindow {# Attempt to set window size if it's too small and the environment is not running inside Terminal.
$minWidth = 130; $minHeight = 50; $buffer = $Host.UI.RawUI.BufferSize; $window = $Host.UI.RawUI.WindowSize
if ($env:WT_SESSION -and ($window.Width -lt $minWidth -or $window.Height -lt $minHeight)) {Write-Host -f red "`nWarning:" -n; Write-Host -f white " You are running PowerShell inside Windows Terminal and this module is therefore unable to resize the window. Please manually resize it to at least $minWidth by $minHeight for best performance. Your current window size is $($window.Width) by $($window.Height)."; return}
if ($buffer.Width -lt $minWidth) {$buffer.Width = $minWidth}
if ($buffer.Height -lt $minHeight) {$buffer.Height = $minHeight}
$Host.UI.RawUI.BufferSize = $buffer
try {if ($window.Width -lt $minWidth) {$window.Width = $minWidth}
if ($window.Height -lt $minHeight){$window.Height = $minHeight}
$Host.UI.RawUI.WindowSize = $window}
catch {Write-Host -f red "`nWarning:" -n; Write-Host -f white " Unable to resize window. Please manually resize to at least $minWidth x $minHeight."}
$window = $Host.UI.RawUI.WindowSize
if ($window.Width -lt $minWidth -or $window.Height -lt $minHeight) {Write-Host -f red "`nWarning:" -n; Write-Host -f white " This module works best when the screen size is at least $minWidth characters wide by $minHeight lines.`n Current window size is $($window.Width) x $($window.Height). Output may wrap or scroll unexpectedly.`n"}}

function clearclipboard ($delayseconds = 30) {# Fill the clipboard with junk and then clear it after a delay.
Start-Job -ScriptBlock {param($delay, $length); Start-Sleep -Seconds $delay; $junk = -join ((33..126) | Get-Random -Count $length | ForEach-Object {[char]$_}); Set-Clipboard -Value $junk; Start-Sleep -Milliseconds 500; Set-Clipboard -Value $null} -ArgumentList $delayseconds, 64 | Out-Null}

function nowarning {# Set global warning field to null.
$script:warning = $null}

function nomessage {# Set global message field to null.
$script:message = $null}

function wordwrap ($field, [int]$maximumlinelength = 65) {# Modify fields sent to it with proper word wrapping.
if ($null -eq $field -or $field.Length -eq 0) {return $null}
$breakchars = ',.;?!\/ '; $wrapped = @()

foreach ($line in $field -split "`n") {if ($line.Trim().Length -eq 0) {$wrapped += ''; continue}
$remaining = $line.Trim()
while ($remaining.Length -gt $maximumlinelength) {$segment = $remaining.Substring(0, $maximumlinelength); $breakIndex = -1

foreach ($char in $breakchars.ToCharArray()) {$index = $segment.LastIndexOf($char)
if ($index -gt $breakIndex) {$breakChar = $char; $breakIndex = $index}}
if ($breakIndex -lt 0) {$breakIndex = $maximumlinelength - 1; $breakChar = ''}
$chunk = $segment.Substring(0, $breakIndex + 1).TrimEnd(); $wrapped += $chunk; $remaining = $remaining.Substring($breakIndex + 1).TrimStart()}

if ($remaining.Length -gt 0) {$wrapped += $remaining}}
return ($wrapped -join "`n")}

function indent ($field, $colour = 'white', [int]$indent = 2) {# Set a default indent for a field.
if ($field.length -eq 0) {return}
$prefix = (' ' * $indent)
foreach ($line in $field -split "`n") {Write-Host -f $colour "$prefix$line"}}

function helptext {# Detailed help.

function scripthelp ($section) {# (Internal) Generate the help sections from the comments section of the script.
""; Write-Host -f yellow ("-" * 100); $pattern = "(?ims)^## ($section.*?)(##|\z)"; $match = [regex]::Match($scripthelp, $pattern); $lines = $match.Groups[1].Value.TrimEnd() -split "`r?`n", 2; Write-Host $lines[0] -f yellow; Write-Host -f yellow ("-" * 100)
if ($lines.Count -gt 1) {wordwrap $lines[1] 100| Out-String | Out-Host -Paging}; Write-Host -f yellow ("-" * 100)}

$scripthelp = Get-Content -Raw -Path $PSCommandPath; $sections = [regex]::Matches($scripthelp, "(?im)^## (.+?)(?=\r?\n)")
if ($sections.Count -eq 1) {cls; Write-Host "$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) Help:" -f cyan; scripthelp $sections[0].Groups[1].Value; ""; return}
$selection = $null

do {cls; Write-Host "$([System.IO.Path]::GetFileNameWithoutExtension($PSCommandPath)) Help Sections:`n" -f cyan; for ($i = 0; $i -lt $sections.Count; $i++) {"{0}: {1}" -f ($i + 1), $sections[$i].Groups[1].Value}
if ($selection) {scripthelp $sections[$selection - 1].Groups[1].Value}
Write-Host -f white "`nEnter a section number to view " -n; $input = Read-Host
if ($input -match '^\d+$') {$index = [int]$input
if ($index -ge 1 -and $index -le $sections.Count) {$selection = $index}
else {$selection = $null}} else {""; return}}
while ($true); return}

#---------------------------------------------USER MANAGEMENT--------------------------------------

function usermanagementmenu {# Render user management menu.
cls
Write-Host -f yellow "User Management:"
Write-Host -f cyan ("-" * 50)
Write-Host -f white "  [A]dd    user"
Write-Host -f white "  [R]emove user"
Write-Host -f white "  [U]pdate user"
Write-Host -f white "  [V]iew   user registry"
Write-Host -f white "  [B]ackup privlege settings"
Write-Host -f white "↩️[RETURN]"
Write-Host -f cyan ("-" * 50)
if ($script:userresult) {$script:userresult = wordwrap $script:userresult 50; Write-Host -f white $script:userresult; Write-Host -f cyan ("-" * 50)} else {""}
Write-Host -f yellow "`nChoose an option from above: " -n; $useraction = Read-Host; return $useraction}

function usermanagement {# User management interface.
$script:userresult = $null; nomessage; nowarning
do {$useraction = usermanagementmenu; $logchoices = "." + $useraction; $logchoices = $logchoices -replace ". ", "."; if ($logchoices.length -gt 1) {logchoices $logchoices}
switch ($useraction.ToUpper()) {'A' {addregistryuser}
'R' {removeregistryuser}
'U' {updateregistryuser}
'V' {viewuser}
'B' {backupprivilege}
default  {if ($useraction.Length -gt 0) {$script:userresult = "Invalid choice."}
else {$script:management = $false; logchoices '.q'; rendermenu; return}}}}
while ($true)}

function loadregistry {# Load the user registry.
if (-not (Test-Path $script:registryFile)) {$script:users = @(); return}

try {$raw = [IO.File]::ReadAllBytes($script:registryFile); $decompressed = [IO.Compression.GzipStream]::new([IO.MemoryStream]::new((unprotectbytesaeshmac $raw $script:key)), [IO.Compression.CompressionMode]::Decompress); $reader = [IO.StreamReader]::new($decompressed); $json = $reader.ReadToEnd(); $reader.Close(); $decompressed.Close()

$entries = $json | ConvertFrom-Json -Depth 5
if ($null -eq $entries) {$script:users = @(); return}
elseif ($entries -isnot [System.Collections.IEnumerable]) {$entries = @($entries)}}
catch {$script:warning = "❌ Failed to load registry."; $script:users = @(); return}

$script:users = @()
foreach ($entry in $entries) {$data = [PSCustomObject]@{Username = $entry.data.Username
Password = $entry.data.Password
Role = $entry.data.Role
Created = $entry.data.Created
Expires = $entry.data.Expires
Active = $entry.data.Active}
$fixedEntry = [PSCustomObject]@{data = $data; hmac = $entry.hmac}

if (verifyentryhmac $fixedEntry) {$script:users += $fixedEntry}
else {$script:warning = "⚠️ Registry entry failed HMAC check. Ignored."}}}

function saveregistry {# Save the user registry.
if (-not $script:users) {return}

$wrapped = foreach ($entry in $script:users) {$data = $entry.data; $hmac = createperentryhmac $data $script:key; [PSCustomObject]@{data = $data; hmac = $hmac}}

$json = $wrapped | ConvertTo-Json -Depth 5 -Compress; $bytes = [Text.Encoding]::UTF8.GetBytes($json); $ms = New-Object IO.MemoryStream; $gz = New-Object IO.Compression.GzipStream($ms, [IO.Compression.CompressionLevel]::Optimal); $gz.Write($bytes, 0, $bytes.Length); $gz.Close(); $final = protectbytesaeshmac $ms.ToArray() $script:key; [IO.File]::WriteAllBytes($script:registryFile, $final)}

function addregistryuser {# Add to the user registry.
loadregistry

# Ask for username.
Write-Host -f white "`n👤 Enter new username " -n; $username = Read-Host
if (-not ($username -match '^[a-zA-Z]{6,12}[0-9]{0,3}$')) {$script:userresult = "❌ Invalid username format. Must be 6–12 letters, optionally ending in 0–3 digits."; return}

if ($script:users | Where-Object {$_.data.Username -eq $username}) {$script:userresult = "⚠️ User already exists."; return}

# Ask for password.
Write-Host -f white "🔐 Enter password " -n; $secure1 = Read-Host -AsSecureString
Write-Host -f white "🔁 Re-enter password " -n; $secure2 = Read-Host -AsSecureString
$plain1 = [System.Net.NetworkCredential]::new("", $secure1).Password; $plain2 = [System.Net.NetworkCredential]::new("", $secure2).Password; $secure1.Dispose(); $secure2.Dispose()
if ($plain1 -ne $plain2) {$script:userresult = "❌ Passwords do not match."; return}
if ($plain1.Length -lt 8 -or $plain1 -notmatch '[a-z]' -or $plain1 -notmatch '[A-Z]' -or $plain1 -notmatch '[0-9]' -or $plain1 -notmatch '[^a-zA-Z0-9]') {$script:userresult = "❌ Password must be 8+ characters and include upper, lower, digit, and special character."; return}

# Ask for role.
Write-Host -f white "`n👥 Role? [standard/privileged] " -n; $role = Read-Host
if ($role -notin @('standard','privileged')) {$script:userresult = "❌ Role must be 'standard' or 'privileged'."; return}

# Ask for Expiration date.
Write-Host -f white "⏳ Expiration date (yyyy-MM-dd) (leave blank or invalid = today + 365) " -n; $expires = Read-Host
if (-not $expires) {$expiry = (Get-Date).AddDays(365)}
else {try {$expiry = [datetime]::ParseExact($expires, 'yyyy-MM-dd', $null)}
catch {$script:userresult = "❌ Invalid expiration format. Using default (today + 365 days)."; $expiry = (Get-Date).AddDays(365)}}

# Ask for Active status.
Write-Host -f white "🔘 Active? [true/false] (leave blank or invalid = true) " -n; $active = Read-Host
if ($active.ToLower() -eq 'false') {$activeStatus = $false}
else {if ($active -ne '' -and $active.ToLower() -ne 'true') {$script:userresult = "❌ Invalid active status. Defaulting to active."}
$activeStatus = $true}

$salt = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt); $derived = derivekeyfrompassword $plain1 $salt; $sha256 = [Security.Cryptography.SHA256]::Create(); $hash = $sha256.ComputeHash($derived); $sha256.Dispose(); $encoded = [Convert]::ToBase64String($salt + $hash)

$data = [PSCustomObject]@{Username = $username
Password = $encoded
Role     = $role
Created  = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd")
Expires  = $expiry.ToUniversalTime().ToString("yyyy-MM-dd")
Active   = $activeStatus}
$hmac = createperentryhmac $data $script:key
$entry = [PSCustomObject]@{data = $data; hmac = $hmac}
$script:users += $entry; saveregistry; $script:userresult = "✅ User '$username' added as $role."}

function updateregistryuser {# Update a user entry.
loadregistry
if (-not $script:users -or $script:users.Count -eq 0) {$script:userresult = "📭 No users found in registry."; return}

Write-Host -f white "`n👤 Enter username to update: " -n; $username = Read-Host
$entry = $script:users | Where-Object {$_.data.Username -eq $username}
if (-not $entry) {$script:userresult = "❌ User '$username' not found."; return}

# Update password
Write-Host -f white "🔐 Enter new password (leave blank to keep current): " -n; $secure1 = Read-Host -AsSecureString
if ($secure1.Length -gt 0) {Write-Host -f white "🔁 Re-enter new password: " -n; $secure2 = Read-Host -AsSecureString
$plain1 = [System.Net.NetworkCredential]::new("", $secure1).Password; $plain2 = [System.Net.NetworkCredential]::new("", $secure2).Password; $secure1.Dispose(); $secure2.Dispose()
if ($plain1 -ne $plain2) {$script:userresult = "❌ Passwords do not match."; return}
if ($plain1.Length -lt 8 -or $plain1 -notmatch '[a-z]' -or $plain1 -notmatch '[A-Z]' -or $plain1 -notmatch '[0-9]' -or $plain1 -notmatch '[^a-zA-Z0-9]') {$script:userresult = "❌ Password must be 8+ characters and include upper, lower, digit, and special character."; return}

$salt = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt); $derived = derivekeyfrompassword $plain1 $salt; $sha256 = [Security.Cryptography.SHA256]::Create(); $hash = $sha256.ComputeHash($derived); $sha256.Dispose(); $encoded = [Convert]::ToBase64String($salt + $hash); $entry.data.Password = $encoded}

# Update role
Write-Host -f white "👥 Role? [standard/privileged] (leave blank to keep current) " -n; $role = Read-Host
if ($role) {if ($role -notin @('standard','privileged')) {$script:userresult = "❌ Role must be 'standard' or 'privileged'."; return}
$entry.data.Role = $role}

# Update expiration date
Write-Host -f white "⏳ Expiration date (yyyy-MM-dd) (leave blank to keep current) " -n; $expires = Read-Host
if ($expires) {try {$expiry = [datetime]::ParseExact($expires, 'yyyy-MM-dd', $null); $entry.data.Expires = $expiry.ToString('yyyy-MM-dd')}
catch {$script:userresult = "❌ Invalid expiration format."; return}}

# Update active status
Write-Host -f white "🔘 Active? [true/false] (leave blank to keep current) " -n; $active = Read-Host
if ($active) {if ($active.ToLower() -in @('true','false')) {$entry.data.Active = [bool]::Parse($active)}
else {$script:userresult = "❌ Active status must be 'true' or 'false'. Leaving unmodified."}}

# Refresh HMAC and save
$entry.hmac = createperentryhmac $entry.data $script:key; saveregistry; $script:userresult = "✅ User '$username' updated."}

function removeregistryuser {# Remove a registered user.
loadregistry
if (-not $script:users -or $script:users.Count -eq 0) {$script:userresult = "📭 No users found in registry."; return}

Write-Host -f white "`n👤 Enter username to remove: " -n; $username = Read-Host
$entry = $script:users | Where-Object {$_.data.Username -eq $username}
if (-not $entry) {$script:userresult = "❌ User '$username' not found."; return}

Write-Host -f red "`nConfirm removal of user '$username': (Y/N) " -n; $confirm = Read-Host
if ($confirm -match '^[Yy]') {$script:users = $script:users | Where-Object {$_.data.Username -ne $username}; saveregistry; $script:userresult = "✅ User '$username' removed."}
else {$script:userresult = "Aborted."}}

function viewuser {# View registered users.
loadregistry

if (-not $script:users -or $script:users.Count -eq 0) {$script:userresult = "📭 No users found in registry."; return}

Write-Host -f white "`n📋 Registered Users:`n"

foreach ($entry in $script:users) {if (-not (verifyentryhmac $entry)) {Write-Host -f red "⚠️  Skipping tampered or invalid user entry."; continue}
$user = $entry.data; $status = if ($user.Active) {"✅ Active"} else {"🚫 Inactive"}
Write-Host -f yellow ("-" * 50)
Write-Host "👤 User:    $($user.Username)"
Write-Host "🔑 Role:    $($user.Role)"
Write-Host "🕓 Created: $($user.Created)"
Write-Host "📅 Expires: $($user.Expires)"
Write-Host "📌 Status:  $status"}
Write-Host -f yellow ("-" * 50)
Write-Host -f white "`n↩️[RETURN] " -n; Read-Host}

function backupprivilege {# Zip all contents of $privilegedir.
if (-not (Test-Path $privilegedir)) {Write-Host -f yellow "📁 Privilege directory not found. Creating..."; New-Item -ItemType Directory -Path $privilegedir -Force | Out-Null}

$timestamp = (Get-Date).ToString("MM-dd-yyyy @ HH_mm_ss"); $backupName = "privileges ($timestamp).zip"; $backupPath = Join-Path $privilegedir $backupName; $tempDir = Join-Path $privilegedir ".tempbackup"
if (Test-Path $tempDir) {Remove-Item -Recurse -Force -Path $tempDir -ErrorAction SilentlyContinue}
New-Item -ItemType Directory -Path $tempDir -Force | Out-Null

# Copy only direct contents, skip .zip and temp folder
Get-ChildItem -Path $privilegedir -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -ne '.zip' } | ForEach-Object {Copy-Item -Path $_.FullName -Destination (Join-Path $tempDir $_.Name) -Force}

Compress-Archive -Path "$tempDir\*" -DestinationPath $backupPath -Force; Remove-Item $tempDir -Recurse -Force

# Keep only 5 newest backups
$backups = Get-ChildItem -Path $privilegedir -Filter 'privileges (*.zip)' | Sort-Object LastWriteTime -Descending
if ($backups.Count -gt 5) {$backups | Select-Object -Skip $script:archiveslimit | Remove-Item -Force}

$script:userresult = "✅ Privilege backup created:`n$backupName`n`nManual restore required. This was intentional, due to the volatile nature of these files. A user with sufficient access to the privilege directory will need to complete the restore activities, if required."}

function authenticateuser {# Authentication mechanism.
$maxFailures = 3; $lockoutDuration = [TimeSpan]::FromMinutes(30); $attemptsFilePrefix = ".locked.flag"; $script:standarduser = $false

loadregistry

if (-not $script:users -or $script:users.Count -eq 0) {Write-Host -f red "`t    No users found in registry."; return $false}

while ($true) {Write-Host -f green "`t 👤 Username: " -n; $username = Read-Host
if (-not $username) {Write-Host -f red "`t    Username required."; continue}
$userEntry = $script:users | Where-Object {$_.data.Username -eq $username}
if (-not $userEntry) {Write-Host -f red "`t    User not found."; continue}

# Check account active and expiration date
$expiresDate = [datetime]::ParseExact($userEntry.data.Expires, 'yyyy-MM-dd', $null); $nowDate = (Get-Date).ToUniversalTime().Date
if (-not $userEntry.data.Active -or $nowDate -gt $expiresDate) {Write-Host -f red "`t    Account expired or inactive."; return $false}

# Lock file path
$lockFile = Join-Path $privilegedir "$username$attemptsFilePrefix"

# Check lockout
if (Test-Path $lockFile) {$lastWrite = (Get-Item $lockFile).LastWriteTimeUtc; $elapsed = (Get-Date).ToUniversalTime() - $lastWrite
if ($elapsed -lt $lockoutDuration) {$remaining = $lockoutDuration - $elapsed; Write-Host -f red "`t    Account locked.`n`t    Try again in $([int]$remaining.TotalMinutes) minutes."; return $false}
else {Remove-Item $lockFile -ea SilentlyContinue}}

# Track login attempts count
$failCount = 0
if (Test-Path $lockFile) {$failCount = [int](Get-Content $lockFile -ea SilentlyContinue)}

while ($true) {Write-Host -f green "`t 🔐 Password: " -n; $securePass = Read-Host -AsSecureString
if (-not $securePass -or $securePass.Length -eq 0) {Write-Host -f red "`t    Password required."; continue}
try {$plainPass = [System.Net.NetworkCredential]::new("", $securePass).Password
if (-not $plainPass) {Write-Host -f red "`t    Password required."; continue}}
catch {Write-Host -f red "`t    Invalid password input."; continue}

$saltAndHash = [Convert]::FromBase64String($userEntry.data.Password); $salt = $saltAndHash[0..15]; $storedHash = $saltAndHash[16..($saltAndHash.Length - 1)]; $derived = [byte[]](derivekeyfrompassword $plainPass $salt); $sha256 = [Security.Cryptography.SHA256]::Create(); $computedHash = $sha256.ComputeHash($derived); $sha256.Dispose()

$match = ($computedHash.Length -eq $storedHash.Length) -and (-not (Compare-Object $computedHash $storedHash))
if ($match) {if (Test-Path $lockFile) {Remove-Item $lockFile -ea SilentlyContinue}
$script:standarduser = ($userEntry.data.Role -eq 'standard'); $script:message = "✅ Authentication successful for user '$username'."; $script:loggedinuser = $username; return $true}

$failCount++; Set-Content -Path $lockFile -Value $failCount; (Get-Item $lockFile).LastWriteTimeUtc = (Get-Date).ToUniversalTime(); $remainingAttempts = $maxFailures - $failCount
if ($remainingAttempts -le 0) {Write-Host -f red "`t    Account locked.`n`t    Try again in 30 minutes."; return $false}
Write-Host -f red "`t    Invalid password. $remainingAttempts attempt(s) remaining."}}}

#---------------------------------------------PRIVILEGE FUNCTIONS----------------------------------

function masterlockout {# Master password failure lockout.
$flagfile = Join-Path $script:privilegedir 'masterfailed.flag'
if (Test-Path $flagfile) {$lastWrite = (Get-Item $flagfile).LastWriteTime
if ((Get-Date) - $lastWrite -lt [TimeSpan]::FromMinutes(30)) {$script:lockoutmaster = $true}}
if ($script:failedmaster -gt 3 -or $script:lockoutmaster) {Set-Content -Path $flagfile -Value "Too many failed attempts: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Encoding UTF8; $script:warning = "❌ Too many failed attempts. Access locked for 30 minutes."; nomessage; rendermenu; $script:lockoutmaster = $true; return $true}
$script:lockoutmaster = $false; return $false}

function initializeprivilege ([byte[]]$Key, [string]$Master) {# Generate random AES key if not provided
if (-not $Key) {$Key = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($Key)}

# Prompt for master password if not provided
if (-not $Master) {$secure1 = Read-Host -AsSecureString "Create master password"; 
$str = [System.Net.NetworkCredential]::new("", $secure1).Password
if ($str -notmatch '^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z\d]).{8,}$') {$script:warning = "Password must be at least 8 characters long and include upper-case and lower-case letters, digits and symbols."; rendermenu; return}
$secure2 = Read-Host -AsSecureString "Confirm password"
if (-not (Compare-SecureString $secure1 $secure2)) {$script:warning = "Passwords do not match."; rendermenu; return}
$Master = [System.Net.NetworkCredential]::new("", $secure1).Password}
if (Test-Path $rootKeyFile) {$script:warning = "Privilege system already initialized."; rendermenu; return}

# Generate random 16-byte salt for key wrapping
$wrapSalt = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($wrapSalt); $wrapKey = derivekeyfrompassword -Password $Master -Salt $wrapSalt

# Encrypt the AES key with the wrap key
$encRoot = protectbytesaeshmac $Key $wrapKey

# Save the keyfile: prepend salt + encrypted root key
New-Item -ItemType Directory -Force -Path $privilegedir | Out-Null; [IO.File]::WriteAllBytes($rootKeyFile, $wrapSalt + $encRoot)

# Generate random salt for verification hash
$verifSalt = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($verifSalt)

# Derive verification key from master password + verification salt
$verifKey = derivekeyfrompassword -Password $Master -Salt $verifSalt

# Store verification salt + SHA256 hash of verification key
$hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($verifKey); [System.IO.File]::WriteAllBytes($hashFile, $verifSalt + $hash)

$script:message = "Master password and privilege key initialized with random salt."; rendermenu; return}

function createperentryhmac ([object]$entry, [byte[]]$key) {# Individual Entry HMAC.
$json = $entry | ConvertTo-Json -Compress -Depth 5; $bytes = [System.Text.Encoding]::UTF8.GetBytes($json); $hmac = [System.Security.Cryptography.HMACSHA256]::new($key)
try {$hash = $hmac.ComputeHash($bytes); $result = [Convert]::ToBase64String($hash)}
finally {$hmac.Dispose()}
return $result}

function verifyentryhmac ([object]$entry) {# Verify individual entry HMAC.
if (-not $entry.data -or -not $entry.hmac) {return $false}
$expected = createperentryhmac -entry $entry.data -key $script:key; return (comparebytearrays ([Convert]::FromBase64String($entry.hmac)) ([Convert]::FromBase64String($expected)))}

function comparebytearrays ([byte[]]$a, [byte[]]$b) {# HMAC verification.
if ($a.Length -ne $b.Length) {return $false}
$diff = 0; for ($i = 0; $i -lt $a.Length; $i++) {$diff = $diff -bor ($a[$i] -bxor $b[$i])}; return ($diff -eq 0)}

function verifymasterpassword ($Password) {# Verify master password.
if (-not (Test-Path $script:hashFile)) {return $false}

[byte[]]$bytes = [System.IO.File]::ReadAllBytes($script:hashFile)
if (-not $bytes -or $bytes.Length -lt 48) {return $false}

$salt = $bytes[0..15]; $storedHash = $bytes[16..47]; $derivedKey = derivekeyfrompassword -Password $Password -Salt $salt; $sha = [System.Security.Cryptography.SHA256]::Create(); $computedHash = $sha.ComputeHash($derivedKey); $sha.Dispose()
return (comparebytearrays -a $computedHash -b $storedHash)}

function rotatemasterpassword {# Allow changing master password.

if (masterlockout) {return}
$oldPwd = Read-Host -AsSecureString "`n`nEnter current master password"

if (-not (verifymasterpassword $oldPwd)) {$script:failedmaster ++; $script:warning = "Wrong master password. $([math]::Max(0,4 - $script:failedmaster)) attempts remain before lockout."; nomessage; rendermenu; return}

function loadprivilegekey ($Password) {# Load privileged key.
[byte[]]$enc = [System.IO.File]::ReadAllBytes($script:rootKeyFile); $wrapSalt = $enc[0..15]; $encRoot = $enc[16..($enc.Length - 1)]; $wrapKey = derivekeyfrompassword -Password $Password -Salt $wrapSalt; return unprotectbytesaeshmac $encRoot $wrapKey}

function comparesecurestring ($a, $b) {if (-not ($a -is [SecureString] -and $b -is [SecureString])) {return $false}
$bstr1 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($a); $bstr2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($b)
try {$str1 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr1); $str2 = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr2)
$bytes1 = [Text.Encoding]::Unicode.GetBytes($str1); $bytes2 = [Text.Encoding]::Unicode.GetBytes($str2)
if ($bytes1.Length -ne $bytes2.Length) {return $false}
$diff = 0
for ($i = 0; $i -lt $bytes1.Length; $i++) {$diff = $diff -bor ($bytes1[$i] -bxor $bytes2[$i])}
return ($diff -eq 0)}
finally {[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr1); [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr2)}}

$rootKey = loadprivilegekey $oldPwd; $newPwd = Read-Host -AsSecureString "New password"; $plainPwd = [System.Net.NetworkCredential]::new("", $newPwd).Password
if ($plainPwd -notmatch '^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z\d]).{8,}$') {$script:warning = "Password must be at least 8 characters long and include upper-case and lower-case letters, digits and symbols."; rendermenu; return}
$newPwd2 = Read-Host -AsSecureString "Confirm new password"
if (-not (comparesecurestring $newPwd $newPwd2)) {$script:warning = "Password mismatch."; nomessage; rendermenu; return}

$newWrapSalt = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($newWrapSalt); $newWrapKey = derivekeyfrompassword -Password $newPwd -Salt $newWrapSalt; $encRoot = Protect-Bytes $rootKey $newWrapKey; [System.IO.File]::WriteAllBytes($script:rootKeyFile, $encRoot); $salt = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt); $verifKey = derivekeyfrompassword -Password $newPwd -Salt $salt; $hash = [System.Security.Cryptography.SHA256]::Create().ComputeHash($verifKey); [System.IO.File]::WriteAllBytes($script:hashFile, $salt + $hash); $script:message = "Master password rotated successfully."; nowarning; rendermenu; return}

function derivekeyfrompassword ([object]$Password, [byte[]]$Salt) {# Derive a key from the provided password.

# Convert string to SecureString if needed
if ($Password -is [string]) {$secure = ConvertTo-SecureString $Password -AsPlainText -Force}
elseif ($Password -is [SecureString]) {$secure = $Password}
else {$script:warning = "Password must be string or SecureString."; nomessage; return}

# Extract plaintext password from SecureString
$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
try {$plain = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)}
finally {[System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)}

# Derive key
$pbkdf2 = [System.Security.Cryptography.Rfc2898DeriveBytes]::new($plain, $Salt, 100000)
try {return $pbkdf2.GetBytes(64)}
finally {$pbkdf2.Dispose()}}

function protectbytesaeshmac ([byte[]]$PlainBytes, [byte[]]$Key) {# Derived from password, split into encryption & HMAC keys.
$aesKey = $Key[0..31]; $hmacKey = $Key[32..63]

$iv = New-Object byte[] 16; [Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($iv)

$aes = [System.Security.Cryptography.Aes]::Create(); $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC; $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7; $aes.Key = $aesKey; $aes.IV = $iv; $encryptor = $aes.CreateEncryptor(); $cipherText = $encryptor.TransformFinalBlock($PlainBytes, 0, $PlainBytes.Length)

$hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey); $hmacData = $iv + $cipherText; $hmacBytes = $hmac.ComputeHash($hmacData); 

$encryptor.Dispose(); $aes.Dispose(); $hmac.Dispose()
return $hmacBytes + $hmacData}

function unprotectbytesaeshmac ([byte[]]$ProtectedBytes, [byte[]]$Key) {# Decode both keys. 
$aesKey = $Key[0..31]; $hmacKey = $Key[32..63]; $hmacBytes = $ProtectedBytes[0..31]; $hmacBytes = [byte[]]$hmacBytes; $iv = $ProtectedBytes[32..47]; $cipherText = $ProtectedBytes[48..($ProtectedBytes.Length - 1)]

$hmac = [System.Security.Cryptography.HMACSHA256]::new($hmacKey); $hmacData = $iv + $cipherText; $computedHmac = $hmac.ComputeHash($hmacData); $hbLen = $hmacBytes.Length; $chLen = $computedHmac.Length; $hbType = $hmacBytes.GetType().FullName; $chType = $computedHmac.GetType().FullName
if (-not [System.Linq.Enumerable]::SequenceEqual($hmacBytes, $computedHmac)) {$script:warning = "`nHMAC validation failed. Data may have been tampered with or corrupted. Proceed with caution!"; return}

$aes = [System.Security.Cryptography.Aes]::Create(); $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC; $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7; $aes.Key = $aesKey; $aes.IV = $iv; $decryptor = $aes.CreateDecryptor(); $plainBytes = $decryptor.TransformFinalBlock($cipherText, 0, $cipherText.Length)

$decryptor.Dispose(); $aes.Dispose(); $hmac.Dispose()
return [byte[]]$plainBytes}

function fulldbexport {# Export the current database with all passwords in plaintext.

if (masterlockout) {return}
Write-Host -f green  "`n`t 👑 Master Password " -n; $master = Read-Host -AsSecureString
if (-not (verifymasterpassword $master)) {$script:failedmaster ++; $script:warning = "Wrong master password. $([math]::Max(0,4 - $script:failedmaster)) attempts remain before lockout."; nomessage; rendermenu; return}

# Verify database password
$script:key = $null; decryptkey $script:keyfile
if (-not $script:key) {$script:warning += "Wrong database password. Aborting export."; nomessage; rendermenu; return}

# Decrypt full database contents
$databasename = [System.IO.Path]::GetFileNameWithoutExtension($script:database)
$fullexport = Join-Path $script:privilegedir "fullexport_$databasename.csv"
$decrypted = @()

$exporterrors = 0; ""
foreach ($entry in $script:jsondatabase) {try {$plaintext = @{Title = $entry.data.Title
Username = $entry.data.Username
Password = if (decryptpassword $entry.data.Password) {$entry.data.Password} else {"[DECRYPTION FAILED]"}
URL = $entry.data.URL
Tags = $entry.data.Tags -join ', '
Notes = $entry.data.Notes
Created = $entry.data.Created
Expires = $entry.data.Expires}
$decrypted += [pscustomobject]$plaintext}
catch {Write-Host "'$($entry.data.Title)' encountered an error, but will be exported, if possible: $_"; $exporterrors ++; $decrypted += [pscustomobject]$plaintext}}

if ($exporterrors -gt 0) {Write-Host -f yellow "`nPress [ENTER] once you have reviewed the errors. " -n; Read-Host}
# Export to CSV
$decrypted | Sort-Object Title | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $fullexport
$script:message = "$databasename exported to fullexport_$databasename.csv"; nowarning; rendermenu; return}

#---------------------------------------------SECURE FILE MANAGEMENT FUNCTIONS---------------------

function decryptkey ($keyfile = $script:keyfile) {# Decrypt a keyfile and start session.
nomessage; nowarning
if (-not (Test-Path $keyfile -ea SilentlyContinue)) {$script:warning = "Encrypted key file not found."; nomessage; return}

# Load entire keyfile bytes
$raw = [IO.File]::ReadAllBytes($keyfile)

# Extract the first 16 bytes as the salt
$salt = $raw[0..15]

# Remaining bytes are the encrypted key
$encKey = $raw[16..($raw.Length - 1)]

# Prompt for master password
Write-Host -ForegroundColor Green "`n`t 🔐 Database Password: " -n; $secureMaster = Read-Host -AsSecureString; $master = [System.Net.NetworkCredential]::new("", $secureMaster).Password; $secureMaster.Dispose()
try {$wrapKey = derivekeyfrompassword -Password $master -Salt $salt; $script:key = [byte[]](unprotectbytesaeshmac $encKey $wrapKey)[0..31]; $script:unlocked = $true; $script:sessionstart = Get-Date; $script:timetoboot = $null}
catch {$script:warning = "Incorrect master password or corrupted key file. Clearing key and database settings."; $script:keyfile = $null; $script:database = $null; $script:unlocked = $false; nomessage}}

function encryptpassword ($plaintext) {# Encrypt using AES-HMAC and Base64
$bytes = [Text.Encoding]::UTF8.GetBytes($plaintext); return [Convert]::ToBase64String((protectbytesaeshmac $bytes $script:key))}

function decryptpassword ($base64) {# Decrypt AES-HMAC Base64 password
$bytes = unprotectbytesaeshmac ([Convert]::FromBase64String($base64)) $script:key; 
return [Text.Encoding]::UTF8.GetString($bytes).TrimStart([char]0x00..[char]0x1F)}

function loadjson {# Load and decrypt the database (without passwords)
if (-not (Test-Path $script:database -ea SilentlyContinue)) {$script:warning = "Database file not found: $script:database"; nomessage; return}
if (-not (Test-Path $script:keyfile -ea SilentlyContinue)) {$script:warning += "Keyfile not found: $script:keyfile"; nomessage; return}
if (-not $script:key) {$script:warning = "Key not loaded. You must call decryptkey first."; nomessage; return}

try {$bytes = [System.IO.File]::ReadAllBytes($script:database); $hmacStored = $bytes[-32..-1]; $ivPlusCipher = $bytes[0..($bytes.Length - 33)]; $hmac = [System.Security.Cryptography.HMACSHA256]::new($script:key); $hmacActual = $hmac.ComputeHash($ivPlusCipher)

if (-not (comparebytearrays $hmacStored $hmacActual)) {$script:warning = "⚠️  HMAC verification failed. The file may have been modified."; nomessage; return}

# Extract IV and Ciphertext
$iv = $ivPlusCipher[0..15]; $cipherBytes = $ivPlusCipher[16..($ivPlusCipher.Length - 1)]

# AES decrypt
$aes = [System.Security.Cryptography.Aes]::Create()
try {$aes.Key = $script:key; $aes.IV = $iv; $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC; $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7; $decryptor = $aes.CreateDecryptor(); $decryptedBytes = $decryptor.TransformFinalBlock($cipherBytes, 0, $cipherBytes.Length); $decryptor.Dispose()}
finally {$aes.Dispose()}

# Decompress
$ms = [System.IO.MemoryStream]::new($decryptedBytes); $gzip = [System.IO.Compression.GzipStream]::new($ms, [System.IO.Compression.CompressionMode]::Decompress); $reader = [System.IO.StreamReader]::new($gzip); $jsonText = $reader.ReadToEnd(); $reader.Close()

$script:jsondatabase = $jsonText | ConvertFrom-Json; $script:message = "Database loaded."; nowarning}
catch {$script:warning = "Failed to load database: $_"; nomessage}}

function savetodisk {# Save to disk (Serialize JSON → Compress → Encrypt → Append HMAC)
try {$jsonText = ,$script:jsondatabase | ConvertTo-Json -Depth 5 -Compress; $jsonBytes = [System.Text.Encoding]::UTF8.GetBytes($jsonText)

# Compress
$ms = [System.IO.MemoryStream]::new(); $gzip = [System.IO.Compression.GzipStream]::new($ms, [System.IO.Compression.CompressionMode]::Compress); $gzip.Write($jsonBytes, 0, $jsonBytes.Length); $gzip.Close(); $compressedBytes = $ms.ToArray()

# Encrypt
$aes = [System.Security.Cryptography.Aes]::Create()
try {$aes.Key = $script:key; $aes.GenerateIV(); $aes.Mode = [System.Security.Cryptography.CipherMode]::CBC; $aes.Padding = [System.Security.Cryptography.PaddingMode]::PKCS7; $encryptor = $aes.CreateEncryptor()
try {$cipherBytes = $encryptor.TransformFinalBlock($compressedBytes, 0, $compressedBytes.Length)}
finally {$encryptor.Dispose()}

$ivPlusCipher = $aes.IV + $cipherBytes

# Compute HMAC
$hmac = [System.Security.Cryptography.HMACSHA256]::new($script:key); $hmacBytes = $hmac.ComputeHash($ivPlusCipher)

# Final bytes = IV + Cipher + HMAC
$finalBytes = $ivPlusCipher + $hmacBytes}
finally {$aes.Dispose()}

# Write file
[System.IO.File]::WriteAllBytes($script:database, $finalBytes); $script:message = "✅ Updated database saved successfully to disk."; nowarning}
catch {$script:warning = "❌ Failed to save updated database: $_"; nomessage}}

function showentries ($entries, $pagesize = 30, [switch]$expired, [switch]$search, $keywords, [switch]$ips, [switch]$invalidurls, [switch]$validurls) {# Browse entire database.
$sortField = $null; $descending = $false; $ippattern = "(?i)(\d{1,3}\.){3}\d{1,3}"; $urlpattern = "(?i)(\w+?:\/\/|www\.|^[A-Z\d-]{3,}\.[A-Z\d-]{2,})"

# Expired filter.
if ($expired) {$entries = $entries | Where-Object {[datetime]$_.data.Expires -le $(Get-Date)}}

# Search filter.
if ($search) {$filtered = @()
foreach ($entry in $entries) {if ($entry.data.Title -match $keywords -or $entry.data.Username -match $keywords -or $entry.data.URL -match $keywords -or $entry.data.Tags -match $keywords -or $entry.data.Notes -match $keywords) {if (-not (verifyentryhmac $entry)) {$script:warning += "Entry $($entry.data.title) has an invalid HMAC and will be ignored. "; continue}
$filtered += $entry}}
$entries = $filtered}

# Find IP filter.
if ($ips) {$filtered = @()
foreach ($entry in $entries) {$url = $entry.data.URL
if ($url -match $ippattern) {$filtered += $entry}}
$entries = $filtered}

# Invalid URL filter.
if ($invalidurls) {$filtered = @()
foreach ($entry in $entries) {$url = $entry.data.URL
if ($url -notmatch $ippattern -and $url -notmatch $urlpattern) {$filtered += $entry}}
$entries = $filtered}

# Valid URL filter.
if ($validurls) {$filtered = @()
foreach ($entry in $entries) {$url = $entry.data.URL
if ($url -match $urlpattern) {$filtered += $entry}}
$entries = $filtered}

# Bail out if no entries
$total = $entries.Count
if ($total -eq 0) {$script:warning = "No entries to view."; nomessage; rendermenu; return}
if ($entries -isnot [System.Collections.IEnumerable] -or $entries -is [string]) {$entries = @($entries); $exportset = @($entries)}

$page = 0
while ($true) {cls; if ($sortField) {$entries = @(if ($descending) {$entries | Sort-Object $sortField -Descending} else {$entries | Sort-Object $sortField})}
$start = $page * $pagesize; $end = [math]::Min($start + $pagesize - 1, $total - 1); $chunk = $entries[$start..$end]

# Show expired entries header if filtered by expired
if ($expired) {Write-Host -f White "Expired Entries: " -n; Write-Host -f Gray "The following entries are older than their expiry date since last update."; Write-Host -f Yellow ("-" * 130)}

# Display the entries in a formatted table
$chunk | Select-Object `
@{Name='Title'; Expression = {if ($_.data.Title.Length -gt 25) {$_.data.Title.Substring(0,22) + '...'} else {$_.data.Title}}}, `
@{Name='Username'; Expression = {if ($_.data.Username.Length -gt 25) {$_.data.Username.Substring(0,22) + '...'} else {$_.data.Username}}}, `
@{Name='URL'; Expression = {if ($_.data.URL.Length -gt 40) {$_.data.URL.Substring(0,37) + '...'} else {$_.data.URL}}}, `
@{Name='Tags'; Expression = {if ($_.data.Tags.Length -gt 15) {$_.data.Tags.Substring(0,12) + '...'} else {$_.data.Tags}}}, `
@{Name='Created'; Expression = {Get-Date $_.data.Created -Format 'yyyy-MM-dd'}}, `
@{Name='Expires'; Expression = {Get-Date $_.data.Expires -Format 'yyyy-MM-dd'}} | Format-Table | Write-Output

# Sorting arrow indicator
$arrow = if ($descending) {"▾"} else {if (-not $sortField) {""} else {"▴"}}

# Footer UI with paging and sorting controls
Write-Host -f Yellow ("-" * 130)
Write-Host -f Cyan ("📑 Page $($page + 1)/$([math]::Ceiling($total / $pagesize))".PadRight(16)) -n
Write-Host -f Yellow "| ⏮️(F)irst (P)revious (N)ext (L)ast⏭️ |" -n
Write-Host -f Green " Sort by: 📜(T)itle 🆔(U)ser 🔗(W)eb URL 🏷 Ta[G]s" -n
Write-Host -f Yellow "| " -n
Write-Host -f Green "$arrow $sortField".PadRight(10) -n
Write-Host -f Yellow " | " -n
Write-Host -f Cyan "↩️[ESC] " -n
if ($validurls -and -not $script:standarduser) {Write-Host -f Green "`n`n[X]port valid URLs " -n}
if (-not $validurls -and -not $script:standarduser) {Write-Host -f Green "`n`n[X]port current search results " -n}

# User input for navigation and sorting
$key = [Console]::ReadKey($true)

switch ($key.Key) {'F' {$page = 0}
'Home' {$page = 0}
'N' {if (($start + $pagesize) -lt $total) {$page++}}
'PageDown' {if (($start + $pagesize) -lt $total) {$page++}}
'DownArrow' {if (($start + $pagesize) -lt $total) {$page++}}
'RightArrow' {if (($start + $pagesize) -lt $total) {$page++}}
'Enter' {if (($start + $pagesize) -lt $total) {$page++}}
'P' {if ($page -gt 0) {$page--}}
'PageUp' {if ($page -gt 0) {$page--}}
'UpArrow' {if ($page -gt 0) {$page--}}
'LeftArrow' {if ($page -gt 0) {$page--}}
'Backspace' {if ($page -gt 0) {$page--}}
'L' {$page = [int][math]::Floor(($total - 1) / $pagesize)}
'End' {$page = [int][math]::Floor(($total - 1) / $pagesize)}
'T' {if ($sortField -eq "Title") {$descending = -not $descending} else {$sortField = "Title"; $descending = $false}
$page = 0}
'U' {if ($sortField -eq "Username") {$descending = -not $descending} else {$sortField = "Username"; $descending = $false}
$page = 0}
'W' {if ($sortField -eq "URL") {$descending = -not $descending} else {$sortField = "URL"; $descending = $false}
$page = 0}
'G' {if ($sortField -eq "Tags") {$descending = -not $descending} else {$sortField = "Tags"; $descending = $false}
$page = 0}
'Q' {nowarning; nomessage; rendermenu; return}
'Escape' {nowarning; nomessage; rendermenu; return}
'X' {if (-not $script:standarduser) {if ($validurls) {$outpath = Join-Path $script:databasedir 'validurls.txt'; $entries.data.URL | Sort-Object -Unique | Out-File $outpath -Encoding UTF8 -Force; Write-Host -f cyan "`n`nExported " -n; Write-Host -f white "$($entries.Count)" -n; Write-Host -f cyan " valid URLs to: " -n; Write-Host -f white "$outpath"; launchvalidator; rendermenu; return}
elseif (-not $validurls) {$outpath = Join-Path $script:databasedir 'searchresults.csv'; @($entries.data) | Select-Object Title, Username, URL, Tags, Created, Expires | ConvertTo-Csv -NoTypeInformation | Out-File $outpath -Encoding UTF8 -Force; Write-Host -f white "Exported $($entries.Count) entries to: $outpath"; Write-Host -f cyan "`n↩️[RETURN] " -n; Read-Host; rendermenu; return}}}
default {}}}}

function retrieveentry ($database = $script:jsondatabase, $keyfile = $script:keyfile, $searchterm, $noclip) {

# Validate minimum search length.
if (-not $searchterm -or $searchterm.Length -lt 3) {$script:warning = "Requested match is too small. Aborting search."; nomessage; return}

# Ensure key is loaded, but use the cached key if unlocked.
if ($script:unlocked -eq $true) {$key = $script:realKey}
else {$key = decryptkey $keyfile; nomessage; nowarning
if (-not $key) {$script:warning = "🔑 No key loaded. " + $script:warning; return}}

# Case-insensitive match on Title, URL, Tags, or Notes.
$entrymatches = @(); $script:warning = $null
foreach ($entry in $script:jsondatabase) {if ($entry.data.Title -match $searchterm -or $entry.data.Username -match $searchterm -or $entry.data.URL -match $searchterm -or $entry.data.Tags -match $searchterm -or $entry.data.Notes -match $searchterm) {if (-not (verifyentryhmac $entry)) {$script:warning += "Entry $($entry.data.title) has an invalid HMAC and will be ignored. "; continue}
$entrymatches += $entry}}
$total = $entrymatches.Count

# Handle no matches or too many matches.
if ($total -eq 0) {$script:warning = "🔐 No entry found matching '$searchterm'"; nomessage; return}
elseif ($total -gt 15) {$script:warning = "Too many matches ($total). Please enter a more specific search."; nomessage; return}

# If exactly one match, select it directly.
if ($total -eq 1) {$selected = $entrymatches[0]}

# Between 2 and 15 matches, display menu for user selection.
else {$invalidentry = "`n"
do {cls; Write-Host -f yellow "`nMultiple matches found:`n"
for ($i = 0; $i -lt $total; $i++) {$m = $entrymatches[$i]
$notesAbbrev = if ($m.data.Notes.Length -gt 40) {$m.data.Notes.Substring(0, 37) + "..."} else {$m.data.Notes}
$notesAbbrev = $notesAbbrev -replace "\r?\n", ""
$urlAbbrev = if ($m.data.URL.Length -gt 45) {$m.data.URL.Substring(0, 42) + "..."} else {$m.data.URL}
$tagsAbbrev = if ($m.data.Tags.Length -gt 42) {$m.data.Tags.Substring(0, 39) + "..."} else {$m.data.Tags}
Write-Host -f Cyan ("{0}. " -f ($i + 1)).PadRight(4) -n; Write-Host -f Yellow "📜 Title: " -n; Write-Host -f White ($m.data.Title).PadRight(38) -n; Write-Host -f Yellow " 🆔 User: " -n; Write-Host -f White ($m.data.Username).PadRight(30) -n; Write-Host -f Yellow " 🔗 URL: " -n; Write-Host -f White $urlAbbrev.PadRight(46) -n; Write-Host -f Yellow "🏷️ Tags:  " -n; Write-Host -f White $tagsAbbrev.PadRight(42) -n; Write-Host -f Yellow " 📝 Notes: " -n; Write-Host -f White $notesAbbrev; Write-Host -f Gray ("-" * 100)}; Write-Host -f Red $invalidentry; Write-Host -f Yellow "🔍 Select an entry to view or Enter to cancel: " -n; $choice = Read-Host
if ($choice -eq "") {$script:warning = "Password retrieval cancelled by user."; nomessage; return}

$parsedChoice = 0; $refParsedChoice = [ref]$parsedChoice
if ([int]::TryParse($choice, $refParsedChoice) -and $refParsedChoice.Value -ge 1 -and $refParsedChoice.Value -le $total) {$selected = $entrymatches[$refParsedChoice.Value - 1]; break}
else {$invalidentry = "`nInvalid entry. Try again."}}
while ($true)}

# Decrypt password field safely.
$passwordplain = "🚫 <no password saved> 🚫"
if ($selected.data.Password -and $selected.data.Password -ne "") {try {$passwordplain = decryptpassword $selected.data.Password}
catch {$passwordplain = "⚠️ <unable to decrypt password> ⚠️"}}

# Copy to clipboard unless -noclip switch is set.
if (-not $noclip.IsPresent) {try {$passwordplain | Set-Clipboard; clearclipboard} 
catch {}}

# Compose formatted output message.
$script:message = "`n🗓️ Created:  $($selected.data.Created)`n⌛ Expires:  $($selected.data.Expires)`n📜 Title:    $($selected.data.Title)`n🆔 UserName: $($selected.data.Username)`n🔐 Password: $passwordplain`n🔗 URL:      $($selected.data.URL)`n🏷️ Tags:     $($selected.data.Tags)`n------------------------------------`n📝 Notes:`n`n$($selected.data.Notes)"; nowarning; rendermenu}

function export ($path, $fields) {# Export current in-memory database content to CSV
if (-not $script:jsondatabase) {$script:warning = "No database content is currently loaded."; nomessage; rendermenu; return}

$validfields = 'Title','Username','Password','URL','Tags','Notes','Created','Expires'
$fieldList = $fields -split ',' | ForEach-Object {$_.Trim()}
$invalidfields = $fieldList | Where-Object {$_ -notin $validfields}
if ($invalidfields) {$script:warning = "Invalid field(s): $($invalidfields -join ', ')"; $script:message = "Allowed fields: $($validfields -join ', ')"; rendermenu; return}

# $script:jsondatabase is assumed to be an array of objects (already parsed JSON)
$script:warning = $null; $filtered = $script:jsondatabase | ForEach-Object {if (-not (verifyentryhmac $_)) {$script:warning += "Entry $($_.Title) has an invalid HMAC and will be ignored. "; return}
$obj = [ordered]@{}
foreach ($field in $fieldList) {$value = $_.$field
switch -Regex ($field) {'^Title$' {$obj['Title'] = $value; continue}
'^Username$' {$obj['Username'] = $value; continue}
'^Password$' {$obj['Password (AES-256-CBC)'] = $value; continue}
'^URL$' {$obj['URL'] = $value; continue}
'^Tags$' {$obj['Tags'] = $value; continue}
'^Notes$' {$obj['Notes'] = $value; continue}
'^Created$' {$obj['Created'] = $value; continue}
'^Expires$' {$obj['Expires'] = $value; continue}
default {$obj[$field] = $value}}}
[pscustomobject]$obj}

if (-not $filtered) {$script:warning += "No valid entries found in the in-memory database."; nomessage; return}

$filtered | Export-Csv -Path $path -NoTypeInformation -Force
if ($path -match '(?i)((\\[^\\]+){2}\\\w+\.csv)') {$shortname = $matches[1]} else {$shortname = $path}
$script:message = "Exported JSON database to: $shortname"; rendermenu}

function newentry ($database = $script:database, $keyfile = $script:keyfile) {# Create a new entry.
$answer = $null; $confirmDup = $null

# Prompt for fields.
Write-Host -f yellow "`n📜 Enter Title: " -n; $title = Read-Host
if (-not $title) {$script:warning = "Every entry must have a Title, as well as a Username and URL. Aborted."; nomessage; rendermenu; return}
Write-Host -f yellow "🆔 Username: " -n; $username = Read-Host
if (-not $username) {$script:warning = "Every entry must have a Username, as well as a Title and URL. Aborted."; nomessage; rendermenu; return}

# Paschword generator.
Write-Host -f yellow "`nDo you want to use the Paschword generator? (Y/N) " -n; $generator = Read-Host
if ($generator -match '^[Yy]') {$password = paschwordgenerator; Write-Host -f yellow "Accept password? (Y/N) " -n; $accept = Read-Host
if ($accept -match '^[Nn]') {do {$password = paschwordgenerator -regenerate; Write-Host -f yellow "Accept password? (Y/N) " -n; $accept = Read-Host} while ($accept -match '^[Nn]')}; ""}
else {Write-Host -f yellow "🔐 Password: " -n; $password = Read-Host -AsSecureString; ""}

Write-Host -f yellow "🔗 URL: " -n; $url = Read-Host
if (-not $url) {$script:warning = "Every entry must have a URL, as well as a Title and Username. Aborted."; nomessage; rendermenu; return}
Write-Host -f yellow "⏳ How many days before this password should expire? (Default = 365): " -n; $expireInput = Read-Host; $expireDays = 365
if ([int]::TryParse($expireInput, [ref]$null)) {$expireDays = [int]$expireInput
if ($expireDays -gt 365) {$expireDays = 365}
if ($expireDays -lt -365) {$expireDays = -365}}
$expires = (Get-Date).AddDays($expireDays).ToString("yyyy-MM-dd")
Write-Host -f yellow "🏷️ Tags: " -n; $tags = Read-Host; $tags = ($tags -split ',') | ForEach-Object {$_.Trim()} | Where-Object {$_} | Join-String -Separator ', '
Write-Host -f yellow "📝 Notes (Enter, then CTRL-Z + Enter to end): " -n; $notes = [Console]::In.ReadToEnd()

# Decrypt key if needed
if ($script:unlocked -eq $false) {decryptkey $script:keyfile}

# Convert SecureString to plain and then encrypt
if ($password -is [SecureString]) {try {$passwordPlain = [System.Net.NetworkCredential]::new("", $password).Password} catch {$passwordPlain = ""}}
else {$passwordPlain = $password; write-host $passwordplain}
if ([string]::IsNullOrWhiteSpace($passwordPlain)) {$passwordPlain = ""}; $secure = encryptpassword $passwordPlain

# Initialize or load in-memory database object.
if (-not $script:jsondatabase) {$script:jsondatabase = @()}

# Check for existing entry by Username and URL.
$existing = $script:jsondatabase | Where-Object {$_.Username -eq $username -and $_.URL -eq $url}

if ($existing) {Write-Host -f yellow "`n🔁 An entry already exists for '$username' at '$url'."; Write-Host -f yellow "`nDuplicate it? (Y/N) " -n; $answer = Read-Host

if ($answer -notmatch '^[Yy]') {Write-Host -f yellow "`nPlease update the entry:`n"; Write-Host -f yellow "📜 Enter Title ($($existing.Title)): " -n; $titleNew = Read-Host
if ([string]::IsNullOrEmpty($titleNew)) {$titleNew = $existing.Title} else {$title = $titleNew}
Write-Host -f yellow "🆔 Username ($($existing.Username)): " -n; $usernameNew = Read-Host
if ([string]::IsNullOrEmpty($usernameNew)) {$usernameNew = $existing.Username} else {$username = $usernameNew}
""; Write-Host -f yellow ("-" * 72)
indent "⚠️ WARNING! ⚠️" red 29
$nohistory = "By updating the entry this way, you will not be able to save a password history. If you wish to keep a history of old passwords, albeit in plaintext, abandon adding this as a new entry and choose the Update option, instead. Simply hit enter at the next prompt in order to abandon adding this entry.️"
$nohistory = wordwrap $nohistory
indent $nohistory white 2
Write-Host -f yellow ("-" * 72); ""
Write-Host -f green "🔐 Do you want to keep the original password or use the new one you just entered? (new/old) " -n; $keep = Read-Host
if ($keep -match "^(?i)old$") {$secure = $existing.Password}
elseif ($keep -match "^(?i)new$") {}
else {$script:warning = "Invalid choice. Aborting."; nomessage; rendermenu; return}
Write-Host -f yellow "🔗 URL ($($existing.URL)): " -n; $urlNew = Read-Host
if ([string]::IsNullOrEmpty($urlNew)) {$urlNew = $existing.URL} else {$url = $urlNew}
Write-Host -f yellow "🏷️ Tags ($($existing.tags)): " -n; $tagsNew = Read-Host
if ([string]::IsNullOrEmpty($tagsNew)) {$tagsNew = $existing.tags} else {$tags = $tagsNew}
Write-Host -f yellow "📝 Notes (CTRL-Z + Enter to end): " -n; $notesNew = [Console]::In.ReadToEnd()
if ([string]::IsNullOrEmpty($notesNew)) {$notesNew = $existing.notes} else {$notes = $notesNew}

# Check for no real changes except password.
if ($username -eq $existing.Username -and $url -eq $existing.URL -and $tags -eq $existing.tags -and $notes -eq $existing.notes) {Write-Host -f yellow "🤔 No changes detected. Overwrite entry? (Y/N) " -n; $confirmDup = Read-Host
if ($confirmDup -notmatch '^[Yy]') {$script:warning = "Entry not saved."; nomessage; $password = $null; $passwordplain = $null; return}}

# Remove old entry from in-memory
$script:jsondatabase = $script:jsondatabase | Where-Object {!($_.Username -eq $username -and $_.URL -eq $url)}}}

# Create the new entry object.
$data = [PSCustomObject]@{Title = $title
Username = $username
Password = $secure
URL = $url
Tags = $tags
Notes = $notes
Created = (Get-Date).ToString("yyyy-MM-dd")
Expires = $expires}
$hmac = createperentryhmac $data $script:key
$entry = [PSCustomObject]@{Data = $data; HMAC = $hmac}

if (-not $script:jsondatabase) {$script:jsondatabase = @()} 
elseif ($script:jsondatabase -isnot [System.Collections.IEnumerable] -or $script:jsondatabase -is [PSCustomObject]) {$script:jsondatabase = @($script:jsondatabase)}

# Add new entry to in-memory database and then to disk.
$script:jsondatabase += $entry; savetodisk}

function updateentry ($database = $script:jsondatabase, $keyfile = $script:keyfile, $searchterm) {# Find and update an existing entry.
$passwordplain = $null

# Validate search term.
if (-not $searchterm -or $searchterm.Length -lt 3) {$script:warning = "Search term too short. Use 3 or more characters."; nomessage; rendermenu; return}

# Load key if needed.
$key = if ($script:unlocked) {$script:realKey} else {decryptkey $keyfile; nowarning; nomessage}
if (-not $script:key) {$script:warning = "🔑 No key loaded."; rendermenu; return}

# Match entries by Title, Username, URL, Tags, Notes.
$searchterm = "(?i)$searchterm"; $searchterm = $searchterm -replace '\s*,\s*', '.+'
$entryMatches  = @(); foreach ($entry in $database) {$fullentry = "$($entry.data.Title) $($entry.data.Username) $($entry.data.URL) $($entry.data.Tags -join ' ') $($entry.data.Notes)"
if ($fullentry -match $searchterm) {$entryMatches += $entry}}

# Handle results.
if ($entryMatches.Count -eq 0) {$script:warning = "No entry found matching '$searchterm'."; nomessage; rendermenu; return}
elseif ($entryMatches.Count -gt 1) {$script:warning = "Multiple entries found ($($entryMatches.Count)). Please refine your search."; nomessage; rendermenu; return}

Write-Host -f cyan "`nUpdate Entry:"
Write-Host -f yellow ("-" * 36)

$entry = $entryMatches[0]
$passwordplain = decryptpassword $entry.data.Password

Write-Host -f white "🗓️ Created:  $($entry.data.Created)`n⌛ Expires:  $($entry.data.Expires)`n📜 Title:    $($entry.data.Title)`n🆔 UserName: $($entry.data.Username)`n🔐 Password: $passwordplain`n🔗 URL:      $($entry.data.URL)`n🏷️ Tags:     $($entry.data.Tags)`n------------------------------------`n📝 Notes:`n`n$($entry.data.Notes)"

# Prompt user for updated values.
Write-Host -f yellow "`n📝 Update entry fields. Leave blank to keep the current value.`n"
Write-Host -f white "📜 Title ($($entry.data.Title)): " -n; $title = Read-Host
Write-Host -f white "🆔 Username ($($entry.data.Username)): " -n; $username  = Read-Host

# Password choice.
Write-Host -f yellow "`n🔐 Do you want to update the password? (Y/N) " -n; $updatepass = Read-Host
if ($updatepass -match '^[Yy]') {Write-Host -f yellow "🔐 Do you want to want to keep a history of the old password in Notes? (Y/N) " -n; $passwordhistory = Read-Host
Write-Host -f yellow "Use Paschword generator? (Y/N) " -n; $gen = Read-Host
if ($gen -match '^[Yy]') {$passplain = paschwordgenerator; Write-Host -f yellow "Accept password? (Y/N) " -n; $accept = Read-Host
while ($accept -match '^[Nn]') {$passplain = paschwordgenerator -regenerate; Write-Host -f yellow "Accept password? (Y/N) " -n; $accept = Read-Host}}
else {Write-Host -f yellow "🔐 Password: " -n; $pass = Read-Host -AsSecureString
try {$passplain = [System.Net.NetworkCredential]::new("", $pass).Password} catch {$passplain = ""}}
try {$secure = encryptpassword $passplain $key} catch {$script:warning = "Password encryption failed."; nomessage; rendermenu; return}}
else {$secure = $entry.data.Password}

Write-Host -f white "`n🔗 URL ($($entry.data.URL)): " -n; $url = Read-Host 
Write-Host -f white  "⏳ Days before expiry (default: keep $($entry.data.Expires)) " -n; $expireIn = Read-Host
Write-Host -f white "🏷️ Tags ($($entry.data.Tags)): " -n; $tags = Read-Host
Write-Host -f white "📝 Notes (CTRL-Z, Enter to leave unchanged): " -n
$notesIn = [Console]::In.ReadToEnd()
Write-Host -f yellow  "`nAre you satisfied with everything? (Y/N) " -n; $abandon = Read-Host
if ($abandon -notmatch "^[Yy]") {$script:warning = "Abandoned updating entry."; nomessage; rendermenu; return}

# Expiration logic.
if ([int]::TryParse($expireIn, [ref]$null)) {$expireDays = [int]$expireIn
if ($expireDays -gt 365) {$expireDays = 365}
if ($expireDays -lt -365) {$expireDays = -365}
$expires = (Get-Date).AddDays($expireDays).ToString("yyyy-MM-dd")}
else {$expires = $entry.data.Expires}

# Validate HMAC.
if (-not (verifyentryhmac $entry)) {$script:warning = "❌ Entry '$($entry.data.Title)' failed HMAC validation. Tampering suspected. Aborted."; nomessage; rendermenu; return}

# Apply updated values.
$data = $entry.Data

$data.Title = if ($title) {$title} else {$data.Title}
$data.Username = if ($username) {$username} else {$data.Username}
$data.Password = $secure
$data.URL = if ($url) {$url} else {$data.URL}
$data.Tags = if ($tags) {($tags -split ',') | ForEach-Object {$_.Trim()} | Where-Object {$_} | Join-String -Separator ', '} else {$data.Tags}
$data.Notes = if ($notesIn) {$notesIn -replace '[^\u0009\u000A\u000D\u0020-\u007E]', ''} else {$data.Notes -replace '[^\u0009\u000A\u000D\u0020-\u007E]', ''}
$data.Expires = $expires

# Handle password history.
$updatedtoday = Get-Date -Format "yyyy-MM-dd"
if ($passwordhistory -match "[Yy]") {if (-not [string]::IsNullOrWhiteSpace($data.Notes)) {$data.Notes = $data.Notes.TrimEnd(); $data.Notes += "`n------------------------------------`n"}
$data.Notes += "[OLD PASSWORD] $passwordplain (valid from $($data.Created) to $updatedtoday)"}

$data.Created = $updatedtoday

# Recompute and update HMAC.
$entry.HMAC = createperentryhmac $data $script:key

# Save and confirm.
$script:jsondatabase = $database; $script:message = "`n✅ Entry successfully updated."; nowarning; savetodisk; rendermenu}

function removeentry ($searchterm) {# Remove an entry.

# Error-checking.
if (-not $script:jsondatabase) {$script:warning = "📑 No database loaded."; nomessage; return}
if ($searchterm.Length -lt 3) {$script:warning = "Search term too short. Aborting removal."; nomessage; return}

$matches = $script:jsondatabase | Where-Object {$_.Title -match $searchterm -or $_.data.Username -match $searchterm -or $_.data.URL -match $searchterm -or $_.data.Tags -match $searchterm -or $_.data.Notes -match $searchterm}
$count = $matches.Count
if ($count -eq 0) {$script:warning = "No entries found matching '$searchterm'."; nomessage; return}
elseif ($count -gt 15) {$script:warning = "Too many matches ($count). Please refine your search."; nomessage; return}

if ($count -eq 1) {$selected = $matches[0]}
else {$invalidentry = "`n"
do {cls; Write-Host -f yellow "`nMultiple matches found:`n"
for ($i = 0; $i -lt $count; $i++) {$m = $matches[$i]
$notesAbbrev = if ($m.Notes.Length -gt 40) {$m.Notes.Substring(0,37) + "..."} else {$m.Notes}
$urlAbbrev = if ($m.URL.Length -gt 45) {$m.URL.Substring(0,42) + "..."} else {$m.URL}
$tagsAbbrev = if ($m.Tags.Length -gt 42) {$m.Tags.Substring(0,39) + "..."} else {$m.Tags}
Write-Host -f Cyan "$($i + 1). ".PadRight(4) -n
Write-Host -f yellow "📜 Title: " -n; Write-Host -f white $($m.Title).PadRight(38) -n
Write-Host -f yellow " 🆔 User: " -n; Write-Host -f white $($m.Username).PadRight(30) -n
Write-Host -f yellow " 🔗 URL: " -n; Write-Host -f white $urlAbbrev.PadRight(46)
Write-Host -f yellow "🏷  Tags: " -n; Write-Host -f white $tagsAbbrev.PadRight(44) -n
Write-Host -f yellow "📝 Notes: " -n; Write-Host -f white $notesAbbrev
Write-Host -f gray ("-" * 100)}
Write-Host -f red $invalidentry
Write-Host -f yellow "❌ Select an entry to remove or Enter to cancel: " -n; $choice = Read-Host
if ($choice -eq "") {$script:warning = "Entry removal cancelled."; nomessage; return}
$parsedChoice = 0; $refParsedChoice = [ref]$parsedChoice
if ([int]::TryParse($choice, $refParsedChoice) -and $refParsedChoice.Value -ge 1 -and $refParsedChoice.Value -le $count) {$selected = $matches[$refParsedChoice.Value - 1]; break}
else {$invalidentry = "`nInvalid entry. Try again."}}
while ($true)}

# Notify about HMAC failure.
$hmacValid = verifyentryhmac $selected
if (-not $hmacValid) {Write-Host -f red "⚠️  Warning: This entry failed HMAC validation and may have been tampered with.`n"}

# Confirm deletion.
Write-Host -f red "🗓️ Created:   " -n; Write-Host -f white "$($selected.data.Created)"
Write-Host -f red "⌛ Expires:   " -n; Write-Host -f white "$($selected.data.Expires)"
Write-Host -f red "📜 Title:     " -n; Write-Host -f white "$($selected.data.Title)"
Write-Host -f red "🆔 UserName:  " -n; Write-Host -f white "$($selected.data.Username)"
Write-Host -f red "🔗 URL:       " -n; Write-Host -f white "$($selected.data.URL)"
Write-Host -f red "🏷  Tags:      " -n; Write-Host -f white "$($selected.data.Tags)"
Write-Host -f white "------------------------------------"
Write-Host -f red "📝 Notes:`n"; Write-Host -f white "$($selected.data.Notes)"
Write-Host -f cyan "`nType 'YES' to confirm removal: " -n; $confirm = Read-Host
if ($confirm -ne "YES") {$script:warning = "Removal aborted."; nomessage; return}

# Remove entry from in-memory database and save to disk.
$script:jsondatabase = @($script:jsondatabase | Where-Object {$_ -ne $selected}); savetodisk}

function newkey ($keyfile) {# Create an AES key, protected with a master password.
if (-not $keyfile) {$script:warning = "No key file identified."; nomessage}

# Generate random 32-byte AES key
$aesKey = New-Object byte[] 32; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($aesKey)

# Prepend magic marker "SCHV"
$marker = [System.Text.Encoding]::UTF8.GetBytes("SCHV"); $keyWithMarker = $marker + $aesKey; $keyfile = Join-Path $script:keydir $keyfile
if (Test-Path $keyfile) {$script:warning = "That key file already exists."; nomessage; rendermenu; return}

neuralizer; Write-Host -f yellow "🔐 Enter a master password to protect your key: " -n; $secureMaster = Read-Host -AsSecureString; $master = [System.Net.NetworkCredential]::new("", $secureMaster).Password
if ($master -notmatch '^(?=.*[a-z])(?=.*[A-Z])(?=.*\d)(?=.*[^a-zA-Z\d]).{8,}$') {$script:warning = "Password must be at least 8 characters long and include upper-case and lower-case letters, digits and symbols."; rendermenu; return}

# Generate random salt for PBKDF2
$salt = New-Object byte[] 16; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($salt); 

# Derive 64-byte key from master password + salt using your derivekeyfrompassword function
$protectKey = derivekeyfrompassword $master $salt

# Encrypt + authenticate the AES key + marker using your protectbytesaeshmac function
$encryptedKey = protectbytesaeshmac $keyWithMarker $protectKey

# Save salt + full encrypted blob (HMAC + IV + ciphertext)
$output = $salt + $encryptedKey; [IO.File]::WriteAllBytes($keyfile, $output); $script:message = "Encrypted AES key created."

# Optional: initialize privilege rotation support
Write-Host -f yellow "`nEnable master password rotation support? (Y/N): " -n; $choice = Read-Host
if ($choice -match '^[Yy]') {try {initializeprivilege -Key $aesKey -Master $master}
catch {$script:warning = "Key created, but failed to initialize rotation support: $_"; return}}
$script:keyfile = $keyfile; $script:keyexists = $true; $script:disablelogging = $false; nowarning}

function validatedatabase {# Validate a database and correct IV collisions.
Write-Host -f cyan "`n`n📄 Provide name of PWDB file to validate: " -n; $file = Read-Host
if ([string]::IsNullOrWhiteSpace($file)) {$script:warning = "Aborted."; nomessage; rendermenu; return}
if (-not [IO.Path]::HasExtension($file)) {$file += ".pwdb"}
if (-not [IO.Path]::IsPathRooted($file)) {$file = Join-Path $script:databasedir $file}
elseif (-not (Test-Path $file)) {$script:warning = "File not found: $file"; nomessage; rendermenu; return}

$script:database = $file; Write-Host -f cyan "`n🔑 Provide KEY file required to open the PWDB: " -n; $keypath = Read-Host
if ([string]::IsNullOrWhiteSpace($keypath)) {$script:warning = "Aborted."; nomessage; rendermenu; return}
if (-not [IO.Path]::HasExtension($keypath)) {$keypath += ".key"}
if (-not [IO.Path]::IsPathRooted($keypath)) {$keypath = Join-Path $script:keydir $keypath}
if (-not (Test-Path $keypath)) {$script:warning = "Key file not found: $keypath"; nomessage; rendermenu; return}

try {decryptkey $keypath
if (-not $script:key) {$script:warning = "Key decryption failed."; nomessage; rendermenu; return}

$script:keyfile = $keypath; $script:jsondatabase = $null; $script:jsondatabase = @(); loadjson
if (-not $script:jsondatabase) {$script:warning = "Decryption produced no data."; nomessage; rendermenu; return}
elseif (-not ($script:jsondatabase -is [System.Collections.IEnumerable])) {$script:warning = "Decrypted data is not an array."; nomessage; rendermenu; return}

$badEntries = @(); $i = 0; $script:warning = $null
foreach ($entry in $script:jsondatabase) {$i++; $missingFields = @()
foreach ($field in 'Title','Password','URL') {if (-not ($entry.data.PSObject.Properties.Name -contains $field)) {$missingFields += $field}}
if ($missingFields.Count -gt 0) {$badEntries += [PSCustomObject]@{Index = $i; Content = $entry; Reason  = "Missing required field(s): $($missingFields -join ', ')"}
continue}
if (-not (verifyentryhmac $entry)) {$badEntries += [PSCustomObject]@{Index = $i; Content = $entry; Reason  = "Failed HMAC validation."}}}

if ($badEntries.Count -gt 0) {Write-Host -f red "`nSome entries are malformed or failed HMAC verification:`n"; $badEntries | Format-Table -AutoSize; Write-Host -f yellow "`n↩️ Return " -n; Read-Host; rendermenu}

# 🧪 Detect and resolve IV collisions (same IV in multiple entries)
$ivSeen = @{}; $collisions = 0
for ($i = 0; $i -lt $script:jsondatabase.Count; $i++) {$entry = $script:jsondatabase[$i]
try {if ([string]::IsNullOrWhiteSpace($entry.data.Password)) {Write-Host -f darkyellow "⚠️ Entry $i`: Empty password — skipping."; continue}
$cipherBytes = [Convert]::FromBase64String($entry.data.Password)
if ($cipherBytes.Length -lt 16) {Write-Host -f darkyellow "⚠️ Entry $i`: Cipher too short — skipping."; continue}
$iv = [BitConverter]::ToString($cipherBytes[0..15]) -replace '-', ''}
catch {Write-Host -f red "⚠️ Entry $i`: Invalid base64 — skipping."; continue}
if ($ivSeen.ContainsKey($iv)) {foreach ($ix in @($i, $ivSeen[$iv])) {$e = $script:jsondatabase[$ix]; $plain = decryptentry $e
if ($plain) {$data = [PSCustomObject]@{Title = $plain.Title
Username = $plain.Username
Password = if ([string]::IsNullOrWhiteSpace($e.data.Password)) {$plain.Password} else {encryptpassword $plain.Password $script:key}
URL = $plain.URL
Tags = $plain.Tags
Notes = $plain.Notes
Created = $plain.Created
Expires = $plain.Expires}
$script:jsondatabase[$ix] = [PSCustomObject]@{Data = $data; HMAC = createperentryhmac $data $script:key}}}
$collisions++}
else {$ivSeen[$iv] = $i}}}
catch {$script:warning = "❌ Verification failed:`n$($_.Exception.Message)"; nomesssage; rendermenu}

if ($collisions -gt 0) {savetodisk; $script:warning = "⚠️  Detected and re-encrypted $collisions IV collision(s) with no data changes."}
else {$script:message = "✅ All entries are valid and IVs are unique. 🛡️"}; rendermenu}

function importcsv ($csvpath) {# Import a CSV file into the database.

# Decrypt the key first.
$script:key = $null; decryptkey $script:keyfile
if (-not $script:key) {$script:warning = "Key decryption failed. Aborting import."; nomessage; return}

# Ensure the database is initialized. This is needed for new, empty databases.
if (-not $script:jsondatabase) {$script:jsondatabase = @()}

# Import CSV file.
$imported = Import-Csv $csvpath; $requiredFields = @('Title', 'Username', 'Password', 'URL'); $optionalFields = @('Tags','Notes','Created','Expires')

Write-Host -f yellow "`nAre the passwords being imported currently stored in plaintext format? (Y/N) " -n; $aretheyplain = Read-Host
if ($aretheyplain -match "[Nn]") {Write-Host -f yellow "Are the passwords for the entries that are being imported already encrypted with the currently loaded key? (Y/N) " -n; $alreadyencrypted = Read-Host
if ($alreadyencrypted -match "[Nn]") {Write-Host -f red "Imported passwords must either be plaintext or encrypted with the same key already loaded into memory." -n; Read-Host; $script:warning = "Aborted due to password incompatability."; nomessage; rendermenu; return}}

# Set expiry expectations.
Write-Host -f yellow "`n⏳ How many days before these entries should expire? (Default = 365): " -n; $expireInput = Read-Host; $expireDays = 365
if ([int]::TryParse($expireInput, [ref]$null)) {$expireDays = [int]$expireInput
if ($expireDays -gt 365) {$expireDays = 365}
if ($expireDays -lt -365) {$expireDays = -365}}
$expires = (Get-Date).AddDays($expireDays).ToString("yyyy-MM-dd")

# Detect extra fields not accounted for already.
$csvFields = $imported[0].PSObject.Properties.Name; $csvFields = $imported[0].PSObject.Properties.Name; $extraFields = $csvFields | Where-Object {($requiredFields -notcontains $_) -and ($optionalFields -notcontains $_)}; $fieldAppendNotes = @{}; $fieldTagMode = @{}
if ($extraFields.Count -gt 0) {foreach ($field in $extraFields) {Write-Host -f Green "`nExtra field detected: " -n; Write-Host -f White "$field"
Write-Host -f Yellow "Append '$field' to Notes? (Y/N) " -n; $appendNoteAns = Read-Host; $fieldAppendNotes[$field] = ($appendNoteAns.ToUpper() -eq 'Y')

Write-Host -f Cyan "Add '$field' as a tag? (Y/N) " -n; $addTagAns = Read-Host; if ($addTagAns.ToUpper() -eq 'Y') {Write-Host -f Cyan "Add tag to all or only populated entries? ([A]ll/[P]opulated) " -n; $mode = Read-Host; if ($mode -and ($mode.ToLower() -in @('a','p'))) {$fieldTagMode[$field] = $mode.ToLower()}
else {Write-Host -f Red "Invalid option. Skipping tag for '$field'."; $fieldTagMode[$field] = 'none'}}}}

$tagAddCounts = @{}
foreach ($field in $extraFields) {$tagAddCounts[$field] = 0}
$added = 0; $skipped = 0; $overwritten = 0; $duplicates = 0
foreach ($entry in $imported) {$title = $null; $username = $null; $plainpassword = $null; $url = $null; $notes = $null; $tags = $null
if (-not $entry.PSObject.Properties.Name -contains 'Title') {$entry | Add-Member -MemberType NoteProperty -Name Title -Value ""}
if (-not $entry.PSObject.Properties.Name -contains 'Username') {Write-Host -f Red "Skipping entry: Missing Username"; $skipped++; continue}
if (-not $entry.PSObject.Properties.Name -contains 'Password') {$entry | Add-Member -MemberType NoteProperty -Name Password -Value ""}
if (-not $entry.PSObject.Properties.Name -contains 'URL') {Write-Host -f Red "Skipping entry: Missing URL"; $skipped++; continue}
if (-not $entry.PSObject.Properties.Name -contains 'Notes') {$entry | Add-Member -MemberType NoteProperty -Name Notes -Value ""}
if (-not $entry.PSObject.Properties.Name -contains 'Tags') {$entry | Add-Member -MemberType NoteProperty -Name Tags -Value ""}

$title = if ($entry.Title -is [string] -and $entry.Title.Trim()) {$entry.Title.Trim()} else {""}
$username = if ($entry.Username -is [string] -and $entry.Username.Trim()) {$entry.Username.Trim()} else {""}
$plainpassword = $entry.Password
$url = if ($entry.URL -is [string] -and $entry.URL.Trim()) {$entry.URL.Trim()} else {""}
$notes = if ($entry.Notes) {$entry.Notes.Trim()} else {""}
$tags = if ($entry.Tags) {$entry.Tags.Trim()} else {""}

# Validate non-empty Username and URL.
if ([string]::IsNullOrWhiteSpace($username)) {Write-Host -f Cyan "`nUsername is empty for an entry (Title: '$title', URL: '$url'). Enter a Username or press Enter to skip: " -n; $username = Read-Host
if ([string]::IsNullOrWhiteSpace($username)) {Write-Host -f Yellow "Skipping entry due to empty Username."; $skipped++; continue}}

if ([string]::IsNullOrWhiteSpace($url)) {Write-Host -f Cyan "`nURL is empty for an entry (Title: '$title', Username: '$username'). Enter a URL or press Enter to skip: " -n; $url = Read-Host
if ([string]::IsNullOrWhiteSpace($url)) {Write-Host -f Yellow "Skipping entry due to empty URL."; $skipped++; continue}}

# Auto-fill Title from domain if empty.
if ([string]::IsNullOrWhiteSpace($title)) {$domain = if ($url -match '(?i)^(https?:\/\/)?(www\.)?(([a-z\d-]+\.)*[a-z\d-]+\.[a-z]{2,10})(\W|$)') {$matches[3].ToLower()} else {""}
if ([string]::IsNullOrWhiteSpace($domain)) {Write-Host -f Cyan "`nTitle is missing and could not auto-extract from URL: $url. Please enter a Title or press Enter to skip: " -n; $title = Read-Host
if ([string]::IsNullOrWhiteSpace($title)) {Write-Host -f Yellow "Skipping entry due to missing Title."; $skipped++; continue}}
else {$title = $domain; Write-Host -f Yellow "Title auto-set to domain: $title"}}

# Append extra fields to Notes if requested.
foreach ($field in $extraFields) {if ($entry.PSObject.Properties.Name -contains $field) {$val = $entry.$field
if (-not [string]::IsNullOrWhiteSpace($val) -and $fieldAppendNotes[$field]) {$notes += "`n$field`: $val"}}}

# Add tags for extra fields.
foreach ($field in $extraFields) {if ($fieldTagMode[$field] -ne 'none' -and $entry.PSObject.Properties.Name -contains $field) {$val = $entry.$field; $shouldAdd = $false
switch ($fieldTagMode[$field]) {'a' {$shouldAdd = $true}
'p' {$shouldAdd = -not [string]::IsNullOrWhiteSpace($val)}}
if ($shouldAdd) {$existingTags = $tags -split ',\s*' | Where-Object {$_ -ne ''}
if (-not ($existingTags -contains $field)) {$tags = if ([string]::IsNullOrWhiteSpace($tags)) {$field} else {"$tags,$field"}
$tagAddCounts[$field]++}}}}

# Check duplicates by Username and URL.
$matches = $script:jsondatabase | Where-Object {$_.Data.Username -eq $username -and $_.Data.URL -eq $url}

if ($matches.Count -gt 0) {$validMatches = $matches | Where-Object {verifyentryhmac $_}
$invalidMatches = $matches | Where-Object {-not (verifyentryhmac $_)}

if ($validMatches.Count -eq 0) {Write-Host -f Red "❌ All duplicate entries for 🆔 '$username' at 🔗 '$url' failed HMAC validation. Possible tampering suspected. Skipping duplicate handling."; continue}

# Proceed with first valid duplicate for the prompt
$match = $validMatches[0]; $duplicates++
Write-Host -f Yellow "`nDuplicate detected for 🆔 '$username' at 🔗 '$url'"
Write-Host -f Cyan "📜 Title: $($match.Data.Title) => $title"
Write-Host -f Cyan "🏷️  Tags: $($match.Data.Tags) => $tags"
Write-Host -f Cyan "📝 Notes: $($match.Data.Notes) => $notes"
Write-Host -f White "`nOptions: (S)kip / (O)verwrite / (K)eep both [default: Keep]: " -n; $choice = Read-Host
switch ($choice.ToUpper()) {"O" {$script:jsondatabase = $script:jsondatabase | Where-Object {$_ -ne $match}; Write-Host -f Red "`nOverwritten."; $overwritten++}
"S" {Write-Host -f Red "`nSkipping entry."; $skipped++; continue}
"K" {Write-Host -f Green "`nKeeping both."}
default {Write-Host -f Green "`nKeeping both."}}}

# Encrypt password using encryptpassword function; allow empty password.
if ($alreadyencrypted -match "[Yy]") {$encryptedPassword = $plainpassword}
else {if ([string]::IsNullOrWhiteSpace($plainpassword)) {Write-Host -f Yellow "`nEntry for 🆔 '$username' at 🔗 '$url' has no password. Adding with 🚫 empty password."; $plainpassword = ""}
$encryptedPassword = encryptpassword $plainpassword}

# Create new entry and add to in-memory database and then save to disk.
$data = [PSCustomObject]@{Title = $title
Username = $username
Password = $encryptedPassword
URL = $url
Tags = $tags
Notes = $notes
Created = (Get-Date).ToString("yyyy-MM-dd")
Expires = $expires}
$hmac = createperentryhmac $data $script:key
$newEntry = [PSCustomObject]@{Data = $data; HMAC = $hmac}

$script:jsondatabase += $newEntry; $added++}
savetodisk

# Summarize output.
Write-Host -f Green "`n✅ Import complete.`n"
Write-Host -f Yellow "New entries added:" -n; Write-Host -f White " $added"
Write-Host -f Gray "Duplicates skipped:" -n; Write-Host -f White " $skipped"
Write-Host -f Red "Overwritten entries:" -n; Write-Host -f White " $overwritten"
Write-Host -f Yellow "Total duplicates:" -n; Write-Host -f White " $duplicates"
$tagsAdded = ($tagAddCounts.GetEnumerator() | Where-Object {$_.Value -gt 0})
if ($tagsAdded.Count -gt 0) {Write-Host -f Yellow "Tag types added:" -n; Write-Host -f White " $($tagsAdded.Count)"
Write-Host -f Yellow "Tags added:" -n; Write-Host -f White " $($tagsAdded.Name -join ', ')"}

# Offer secure delete of CSV file after import.
Write-Host -f red "`n⚠️  Do you want to securely erase the imported CSV file from disk? (Y/N) " -n; $wipecsv = Read-Host
if ($wipecsv -match '^[Yy]') {try {$passes = Get-Random -Minimum 3 -Maximum 50; $length = (Get-Item $csvpath).Length
for ($i = 0; $i -lt $passes; $i++) {$junk = New-Object byte[] $length; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($junk); [System.IO.File]::WriteAllBytes($csvpath, $junk)}
Remove-Item $csvpath -Force
Write-Host -f white "`n🧨 CSV file wiped and deleted in $passes passes."}
catch {Write-Host -f Red "❌ Failed to securely wipe CSV file: $_"}}

Write-Host -f Cyan "`n↩️Return" -n; Read-Host}

function saveandsort {# Sort the database by tag, then by title.
$script:jsondatabase = $script:jsondatabase | Sort-Object {($_.data.Tags -join ' ').ToLower()}, {$_.data.Title.ToLower()}; savetodisk}

function sometestfunction {# Various testing functions via F10
# Note to self: the following keys are not yet mapped via the main menu: g j w y 4-9 0
}

#---------------------------------------------HOUSE CLEANING FUNCTIONS-----------------------------

function corruptdatabase {# JSON Database overwriting.
$databasepasscount = Get-Random -Minimum 3 -Maximum 10;
if (-not ($script:jsondatabase -and $script:jsondatabase.Count -gt 0)) {return}
for ($i = 0; $i -lt $databasepasscount; $i++) {foreach ($entry in $script:jsondatabase) {foreach ($property in $entry.PSObject.Properties) {$original = "$($property.Value)"
if ([string]::IsNullOrEmpty($original)) {continue}
$originalLength = $original.Length; $multiplier = Get-Random -Minimum 1.1 -Maximum 3.9; $roundingMethod = Get-Random -InputObject 'Floor','Ceiling','Round'; $targetLength = [Math]::$roundingMethod($originalLength * $multiplier); $junkBytes = New-Object byte[] $targetLength; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($junkBytes); $trimmed = $junkBytes[0..($originalLength - 1)]; $asciiJunk = ($trimmed | ForEach-Object {[char](($_ % 94) + 33)}) -join ''; $property.Value = $asciiJunk}}}; $script:jsondatabase = $null}

function wipe ([ref]$data) {# Byte variable overwriting and wiping.
if ($data.Value -is [byte[]] -and $data.Value.Length -gt 0) {$length = $data.Value.Length
for ($i = 0; $i -lt $script:keypasscount; $i++) {$multiplier = Get-Random -Minimum 1.1 -Maximum 3.9; $roundingMethod = Get-Random -InputObject 'Floor','Ceiling','Round'; $targetLength = [Math]::$roundingMethod($length * $multiplier); $junk = New-Object byte[] $targetLength; [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($junk); [Array]::Copy($junk, 0, $data.Value, 0, $length)}
$data.Value = $null}
elseif ($data.Value -is [SecureString]) {$bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($data.Value); [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr); $data.Value = $null}}

function scramble ([ref]$reference) {# String overwriting.
if ([string]::IsNullOrEmpty($reference.Value)) {return}
$length = $reference.Value.Length
for ($i = 0; $i -lt $script:keypasscount; $i++) {$multiplier = Get-Random -Minimum 1.1 -Maximum 3.9; $roundingMethod = Get-Random -InputObject 'Floor','Ceiling','Round'
$targetLength = [Math]::$roundingMethod($length * $multiplier); $junk = -join ((33..126) | Get-Random -Count $targetLength | ForEach-Object {[char]$_}); $reference.Value = $junk}
$reference.Value = $null; [GC]::Collect(); [GC]::WaitForPendingFinalizers()}

function neuralizer {# Wipe key and database from memory.
$script:unlocked = $false; $choice = $null; $script:timetoboot = Get-Date

if ($script:noclip -eq $false) {clearclipboard 0 64}

$stopwatch_corrupt = [System.Diagnostics.Stopwatch]::StartNew()
corruptdatabase
$stopwatch_corrupt.Stop()

$wipearray = @($aeskey, $bytes, $bytes1, $bytes2, $cipherbytes, $ciphertext, $compressedbytes, $decrypted, $decryptedbytes, $decryptedkey, $derivedkey, $enc, $enckey, $encryptedbytes, $encryptedkey, $entries, $entry, $entrymatches, $filtered, $finalbytes, $hash, $hmacbytes, $hmacdata, $hmackey, $imported, $iv, $jsonbytes, $key, $keywithmarker, $marker, $matches, $newentry, $newwrapkey, $newwrapsalt, $output, $pass, $password, $plain, $plainbytes, $plainpwd, $plaintext, $protectedbytes, $protectkey, $raw, $refparsedchoice, $rootkey, $salt, $script:key, $secure, $secure1, $secure2, $securemaster, $str1, $str2, $verifkey, $verifsalt, $wrapkey, $wrapsalt)
$stopwatch_wipe = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($item in $wipearray) {if ($item) {wipe ([ref]$item)}}
$stopwatch_wipe.Stop()

$scramblearray = @($chars, $computedhash, $coreparts, $encroot, $encryptedpassword, $existing, $expected, $gen, $getdatabase, $getkey, $input, $invalidentry, $joined, $json, $jsontext, $keep, $key, $master, $newpwd, $newpwd2, $oldpwd, $passplain, $passwordhistory, $passwordplain, $plainpassword, $plaintext, $pwchars, $result, $selected.password, $selected.username, $storedhash, $updatepass, $username, $value, $wipecsv)
$stopwatch_scramble = [System.Diagnostics.Stopwatch]::StartNew()
foreach ($item in $scramblearray) {if ($item) {scramble ([ref]$item)}}
$stopwatch_scramble.Stop()

if ($script:quit) {scramble ([ref]$script:message); scramble ([ref]$script:warning); $securymemorytime = ([math]::Round($stopwatch_wipe.Elapsed.TotalSeconds, 2)) + ([math]::Round($stopwatch_scramble.Elapsed.TotalSeconds, 2)) + ([math]::Round($stopwatch_corrupt.Elapsed.TotalSeconds, 2)); $script:message += "Clearing the database and memory artifacts took $securymemorytime seconds."}}

#---------------------------------------------END HOUSE CLEANING------------------------------------

function backup {# Backup currently loaded key and database pair to the database directory.
$script:message = $null; $script:warning = $null; $baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:database); $timestamp = Get-Date -Format "MM-dd-yyyy @ HH_mm_ss"; $zipName = "$baseName ($timestamp).zip"; $zipPath = Join-Path $script:databasedir $zipName

try {$tempDir = Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString()); New-Item -ItemType Directory -Path $tempDir | Out-Null
Copy-Item $script:database -Destination $tempDir; Copy-Item $script:keyfile -Destination $tempDir; Compress-Archive -Path (Join-Path $tempDir '*') -DestinationPath $zipPath -Force; Remove-Item $tempDir -Recurse -Force; $script:message = $script:message + "`nBackup created: $zipName"; nowarning} catch {$script:warning = "Backup failed: $_"; nomessage}; return}

function scheduledbackup {# Run backup according to PSD1 settings.
$baseName = [System.IO.Path]::GetFileNameWithoutExtension($script:database)
$backups = Get-ChildItem -Path $script:databasedir -File "*.zip" -ea SilentlyContinue | Where-Object {$_.Name -like "$baseName*(*@*).zip"}
$needBackup = $true
$newest = $backups | Sort-Object LastWriteTime -Descending | Select-Object -First 1

if ($newest) {$age = (Get-Date) - $newest.LastWriteTime
if ($age.TotalDays -lt $script:backupfrequency) {$needBackup = $false}}

if ($needBackup) {Write-Host -f darkgray "💾 Creating new backup..."; backup}
else {$script:message = $script:message + "`n🕒 No scheduled backup is currently required."; nowarning; rendermenu}

# Enforce archive limit
$backups = Get-ChildItem -Path $script:databasedir -File "$baseName*(*.zip)" -ea SilentlyContinue

$sortedBackups = $backups | Sort-Object LastWriteTime -Descending
if ($sortedBackups.Count -gt $script:archiveslimit) {$toDelete = $sortedBackups | Select-Object -Skip $script:archiveslimit
foreach ($file in $toDelete) {try {Remove-Item -LiteralPath $file.FullName -Force -ea Stop; $script:message = $script:message + "`n🗑️ Deleted old backup: $($file.Name)"; nowarning}
catch {$script:warning = "⚠️ Failed to delete: $($file.FullName) - $_"}}}; rendermenu; return}

function restore {# Restore a backup.
$script:message = $null; $script:warning = $null
$pattern = '^[A-Za-z0-9_]+ \(\d{2}-\d{2}-\d{4} @ \d{2}_\d{2}_\d{2}\)\.zip$'; 

$backups = Get-ChildItem -Path $script:databasedir -Filter '*.zip' | Where-Object {$_.Name -match $pattern} | Sort-Object Name
if (-not $backups) {$script:warning = "No backup files found in: $script:databasedir"; nomessage; return}
Write-Host -f yellow "`nAvailable backups:`n"
for ($i = 0; $i -lt $backups.Count; $i++) {Write-Host -f cyan ("{0}. " -f ($i + 1)) -n; Write-Host -f white $backups[$i].Name}
Write-Host -f yellow "`nSelect a backup to restore (1-$($backups.Count)) " -n; $selection = Read-Host
if (-not [int]::TryParse($selection, [ref]$null) -or $selection -lt 1 -or $selection -gt $backups.Count) {$script:warning = "Invalid selection. Restore aborted."; nomessage; return}

$chosenFile = $backups[$selection - 1].FullName; $tempDir = Join-Path $env:TEMP ([Guid]::NewGuid().ToString())
try {New-Item -ItemType Directory -Path $tempDir | Out-Null; Expand-Archive -Path $chosenFile -DestinationPath $tempDir -Force; $dbFile  = Get-ChildItem -Path $tempDir -Filter '*.pwdb' | Select-Object -First 1; $keyFile = Get-ChildItem -Path $tempDir -Filter '*.key'  | Select-Object -First 1
if (-not $dbFile -or -not $keyFile) {$script:warning = "Backup is missing required files:`n" + (if (-not $dbFile) {"- Database (.pwdb)`n"} else {""}) + (if (-not $keyFile) {"- Key file (.key)`n"} else {""})
Remove-Item $tempDir -Recurse -Force; return}

$destDb  = Join-Path $script:databasedir $dbFile.Name; $destKey = Join-Path $script:keydir     $keyFile.Name
if (Test-Path $destDb) {Write-Host -f red "`nOverwrite existing database '$($dbFile.Name)'? (Y/N) " -n
if ((Read-Host) -notmatch '[Yy]$') {$script:warning = "Database overwrite declined. Restore aborted."; Remove-Item $tempDir -Recurse -Force; return}}

if (Test-Path $destKey) {Write-Host -f red "Overwrite existing key file '$($keyFile.Name)'? (Y/N) " -n
if ((Read-Host) -notmatch '[Yy]$') {$script:warning = "Key overwrite declined. Restore aborted."; Remove-Item $tempDir -Recurse -Force; return}}

Copy-Item -Path $dbFile.FullName  -Destination $destDb -Force; Copy-Item -Path $keyFile.FullName -Destination $destKey -Force

if ($chosenFile -match '(?i)((\\[^\\]+){2}\\[^\\]+\.ZIP)') {$shortfile = $matches[1]} else {$shortfile = $chosenFile}
$script:message = "Restored '$($dbFile.Name)' and '$($keyFile.Name)' from backup: $shortfile"; nowarning}
catch {$script:warning = "Restore failed:`n$_"; nomessage}
finally {if (Test-Path $tempDir) {Remove-Item $tempDir -Recurse -Force}}}

function launchvalidator {# Launch the validator in a separate window.
$validator = Join-Path $PSScriptRoot "ValidateURLs.ps1"; $file = Join-Path $script:databasedir "validurls.txt"
Write-Host -f cyan "Do you want to launch " -n; Write-Host -f white "ValidateURLs.ps1" -n; Write-Host -f cyan " in a separate window, to test that each of the URLs listed in " -n; Write-Host -f white "validurls.txt" -n; Write-Host -f cyan " are still active? (Y/N) " -n; $proceed = Read-Host
if ($proceed -match "^[Yy]") {if (-not (Test-Path $validator)) {$script:warning = "ValidateURLs.ps1 not found at the expected path:`n$PSScriptRoot"; nomessage; rendermenu; return}
Start-Process -FilePath "powershell.exe" -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File $validator $file -safe `"$script:useragent`"" -WindowStyle Normal; $script:message = "ValidateURLs.ps1 is running in a separate window. Remember to check on it's progress."; nowarning}
else {$script:warning = "Aborted external URL validation script."}
rendermenu; return}

function paschwordgenerator ($design, [switch]$regenerate) {# Create an intuitive password
$specialChars = '~!@#$%^&*_+=.,;:-'.ToCharArray(); $superSpecialChars = '(){}[]'.ToCharArray(); $leetMap = @{'a' = @('@','4'); 'e' = @('3'); 'h' = @('#'); 'l' = @('1','7','!'); 'o' = @('0'); 's' = @('5','$')}

# Load dictionary.
if (-not $script:dictionaryWords) {if (-not (Test-Path $script:dictionaryfile)) {throw "Dictionary file not found: $script:dictionaryfile"}
$script:dictionaryWords = Get-Content -Path $script:dictionaryfile | Where-Object {$_.Trim().Length -gt 0}}

# Present user options.
if (-not $regenerate) {Write-Host ""
Write-Host -f yellow ("-" * 100)
Write-Host -f cyan "Schmart Password Generator:"
Write-Host -f yellow ("-" * 100)
Write-Host -f yellow "Modes, presented in hierarchal order:`n"
Write-Host -f white "[" -n; Write-Host -f cyan "P" -n; Write-Host -f white "]IN, 4-12 digits only, the default is 6."
Write-Host -f white "[" -n; Write-Host -f cyan "H" -n; Write-Host -f white "]uman readable 'leet' code, 12-32 characters."
Write-Host -f white "[" -n; Write-Host -f cyan "D" -n; Write-Host -f white "]ictionary words only, 12-32 characters."
Write-Host -f white "[" -n; Write-Host -f cyan "A" -n; Write-Host -f white "]lphanumeric characters, 4-32 characters."
Write-Host -f yellow ("-" * 100)
Write-Host -f yellow "Modifiers:`n"
Write-Host -f white "[" -n; Write-Host -f cyan "X" -n; Write-Host -f white "]paces may appear between words for [D]/[H], randomly in [A], never as the first or last character."
Write-Host -f white "[" -n; Write-Host -f cyan "S" -n; Write-Host -f white "]pecial characters include: " -n; Write-Host -f cyan "~!@#$%^&*_-+=.,;:" -n; Write-Host -f white "."
Write-Host -f white "[" -n; Write-Host -f cyan "Z" -n; Write-Host -f white "]uper special characters also includes brackets: " -n; Write-Host -f cyan "(){}[]" -n; Write-Host -f white "."
Write-Host -f yellow ("-" * 100)
Write-Host -f yellow "Length:`n"
Write-Host -f white "[" -n; Write-Host -f cyan "#" -n; Write-Host -f white "] 4-32 characters, within the restrictions stated above."
Write-Host -f yellow ("-" * 100)
Write-Host -f yellow "`nPlease choose a combination of the options above (Default = " -n; Write-Host -f cyan "DXS12" -n; Write-Host -f yellow "): " -n; $script:design = Read-Host

if ([string]::IsNullOrWhiteSpace($script:design)) {$script:design = 'DXS12'}

$start = "The password will be created as "
if ($script:design -match 'P') {$base = "a PIN"}
elseif ($script:design -match 'H') {$base = "Human-readable text"}
elseif ($script:design -match 'D') {$base = "Dictionary words"}
elseif ($script:design -match 'A') {$base = "Alphanumeric characters"}
if ($script:design -match 'X') {$spaces = ", allowing spaces"} else {$spaces = ""}
if ($script:design -match 'Z') {$specials = ", using special characters, as well as brackets"}
elseif ($script:design -match 'S') {$specials = ", using special characters"}
else {$specials = ""}
if ($script:design -match '(\d+)') {[int]$number = $matches[1]
if ($script:design -match 'P' -and $number -gt 16) {$number = 16}
elseif ($script:design -match 'D' -and $number -lt 12) {$number = 12}
$length = ", with a length of $number."} 
else {$length = "."}
if ($script:design -match 'P') {$builder = "$start$base$length"}
else {$builder = "$start$base$spaces$specials$length"}

Write-Host -f darkgray ("-" * 100)
Write-Host -f darkgray "$builder`n"; Write-Host -f yellow "Results:  " -n; Write-Host -f darkgray "N3w PaSsWoRd (" -n

$sample = "Co1our_By_Ch@ract3r_Type"
$sample.ToCharArray() | ForEach-Object {switch -regex ($_) {'(?-i)[A-Z]' {Write-Host -f gray $_ -n; continue}
'(?-i)[a-z]' {Write-Host -f darkgray $_ -n; continue}
'\d' {Write-Host -f cyan $_ -n; continue}
"[$($specialChars -join '')]" {Write-Host -f yellow $_ -n; continue}
"[$($superSpecialChars -join '')]" {Write-Host -f green $_ -n; continue}
' ' {Write-Host -b blue $_ -n; continue}
default {Write-Host -f magenta $_ -n}}}

Write-Host -f darkgray ")"; Write-Host -f darkgray ("-" * 100)}

# Parse input.
$null = $script:design
$flagsRaw = ($script:design -replace '\d','').ToCharArray(); $length = [int]($script:design -replace '\D','')
if (-not $length -and $script:design -match 'P') {$length = 4}
elseif (-not $length) {$length = 8}

# Clamp length with overrides
if ($script:design -match 'P') {$length = [Math]::Min([Math]::Max($length,4),12)}
elseif ($script:design -match 'D') {$length = [Math]::Max($length,12)}
else {$length = [Math]::Min([Math]::Max($length,4),32)}

# Special character flags (case-sensitive)
$useSpaces = $flagsRaw -contains 'X'; $useNormalSpecial = $flagsRaw -contains 'S'; $useSuperSpecial = $flagsRaw -contains 'Z'

# Determine effective mode (uppercase-insensitive)
$upperFlags = $flagsRaw | ForEach-Object {$_.ToString().ToUpperInvariant()}
if ($upperFlags -contains 'P') {$mode = 'P'}
elseif ($upperFlags -contains 'H') {$mode = 'H'}
elseif ($upperFlags -contains 'D') {$mode = 'D'}
else {$mode = 'A'}

#-------------------------PIN generator-------------------------

function generatepin($len) {$digits = 0..9; $pin = -join (1..$len | ForEach-Object {Get-Random -InputObject $digits})
return $pin}

#-------------------------Standard alphanumeric password generator-------------------------

function generatealphanumeric($len, $useSpaces, $useNormalSpecial, $useSuperSpecial) {$baseChars = @(); $specials = @()
$lower = [char[]]'abcdefghijklmnopqrstuvwxyz'
$upper = [char[]]'ABCDEFGHIJKLMNOPQRSTUVWXYZ'
$digit = [char[]]'0123456789'
if ($useNormalSpecial) {$specials += $specialChars}
if ($useSuperSpecial) {$specials += $superSpecialChars}
$baseChars += $lower + $upper + $digit + $specials

# Build initial password
$pwChars = 1..$len | ForEach-Object {Get-Random -InputObject $baseChars}

# Enforce at least one lowercase, uppercase, and digit
if (-not ($pwChars -join '' -cmatch '[a-z]')) {$pwChars[(Get-Random -Minimum 0 -Maximum $len)] = Get-Random -InputObject $lower}
if (-not ($pwChars -join '' -cmatch '[A-Z]')) {$pwChars[(Get-Random -Minimum 0 -Maximum $len)] = Get-Random -InputObject $upper}
if (-not ($pwChars -join '' -cmatch '\d')) {$pwChars[(Get-Random -Minimum 0 -Maximum $len)] = Get-Random -InputObject $digit}

# Enforce at least one special if requested
if ($specials.Count -gt 0 -and -not ($pwChars -join '' -cmatch '[\[\]{}()<>|\\\/?!@#\$%\^&\*\-_=\+\.,;:]')) {$pwChars[(Get-Random -Minimum 0 -Maximum $len)] = Get-Random -InputObject $specials}

# Insert spaces if requested, avoiding first character
if ($useSpaces) {$maxSpaces = [Math]::Floor($len / 4); $spaceCount = Get-Random -Minimum 1 -Maximum ([Math]::Max(2, $maxSpaces)); $positions = 1..($len - 1) | Get-Random -Count $spaceCount
foreach ($pos in $positions) {$pwChars[$pos] = ' '}}

return -join $pwChars}

#-------------------------Word helpers-------------------------

function addleet($password) {

function transformWord($word) {$chars = $word.ToCharArray()
for ($i = 0; $i -lt $chars.Length; $i++) {$c = $chars[$i].ToString().ToLower()
if ($leetMap.ContainsKey($c) -and (Get-Random -Minimum 0 -Maximum 4) -eq 3) {$subs = $leetMap[$c]; $chars[$i] = $subs | Get-Random}}
return -join $chars}

return [regex]::Replace($password, '[a-zA-Z]{4,}', {param($match) transformWord $match.Value})}

function randomizecase($word) {$chars = $word.ToCharArray(); $forceIndex = Get-Random -Minimum 0 -Maximum $chars.Length
for ($i = 0; $i -lt $chars.Length; $i++) {$chars[$i] = if ((Get-Random -Minimum 0 -Maximum 2) -eq 1) {[char]::ToUpper($chars[$i])}
else {[char]::ToLower($chars[$i])}}
$upperCount = ($chars | Where-Object {$_ -cmatch '[A-Z]'}).Count; $lowerCount = $chars.Length - $upperCount; $chars[$forceIndex] = if ($upperCount -gt $lowerCount) {[char]::ToLower($chars[$forceIndex])}
else {[char]::ToUpper($chars[$forceIndex])}
return -join $chars}

function addjoiners($words, $useSpaces, $useNormalSpecial, $useSuperSpecial) {
# Prepare special pool
$specialPool = @()
$numbers = @('0','1','2','3','4','5','6','7','8','9')
if ($useNormalSpecial) {$specialPool += $specialChars}
if ($useSuperSpecial) {$specialPool += $superSpecialChars}

# Prepare joiner pool for filler joiners (space, special, number)
$fillerJoiners = @()
if ($useSpaces) {$fillerJoiners += ' '}
if ($specialPool.Count) {$fillerJoiners += $specialPool}
if ($numbers.Count) {$fillerJoiners += $numbers}

# Select 1 number, 1 special, 1 word for the mandatory core part and shuffle
$mandatoryNumber = ($numbers | Get-Random); $mandatorySpecial = ($specialPool | Get-Random); $mandatoryWord = ($words | Get-Random)
$coreParts = @($mandatoryNumber, $mandatorySpecial, $mandatoryWord) | Sort-Object {Get-Random}

# Build password starting with core parts joined without spaces
$remainingWords = $words | Where-Object {$_ -ne $mandatoryWord}
$password = -join $coreParts
for ($i=0; $i -lt $remainingWords.Count; $i++) {$joiner = ''
if ($fillerJoiners.Count -gt 0) {$joiner = $fillerJoiners | Get-Random
if ((Get-Random -Minimum 1 -Maximum 4) -ne 1) {$joiner = ''}}
$password += $joiner + $remainingWords[$i]}

return $password}

#-------------------------Human readable password generator-------------------------

function generatehumanreadable($len, $useSpaces, $useNormalSpecial, $useSuperSpecial) {$words = @(); $totalLength = 0
while ($totalLength -lt $len) {$w = Get-Random -InputObject $script:dictionaryWords; $words += $w; $totalLength += $w.Length}

$words = $words | ForEach-Object {randomizecase $_} | ForEach-Object {addleet $_}
$password = addjoiners $words $useSpaces $useNormalSpecial $useSuperSpecial

if ($password.Length -gt $len) {$password = $password.Substring(0, $len)}
elseif ($password.Length -lt $len) {$password = $password.PadRight($len, (Get-Random -InputObject ([char[]]'abcdefghijklmnopqrstuvwxyz')))}
return $password}

#-------------------------Dictionary password generator-------------------------

function generatedictionary($len, $useSpaces, $useNormalSpecial, $useSuperSpecial) {$words = @(); $totalLength = 0

# Pick words until near or above length or max count reached
while ($totalLength -lt $len -and $words.Count -lt 10) {$w = Get-Random -InputObject $script:dictionaryWords; $words += $w; $totalLength += $w.Length}

# Randomize casing of each word and build with joiners
$words = $words | ForEach-Object {randomizecase $_}
$password = addjoiners $words $useSpaces $useNormalSpecial $useSuperSpecial

# Truncate if too long, pad if too short.
if ($password.Length -gt $len) {$password = $password.Substring(0, $len)}
while ($password.Length -lt $len) {$allowedChars = @('a'..'z') + ('A'..'Z') + ('0'..'9')
if ($useNormalSpecial) {$allowedChars += $specialChars}
if ($useSuperSpecial) {$allowedChars += $superSpecialChars}
$password += (Get-Random -InputObject $allowedChars)}

# No trailing spaces from joiners or padding
while ($password[-1] -eq ' ') {$password = $password.Substring(0, $password.Length - 1) + (Get-Random -InputObject ([char[]]'abcdefghijklmnopqrstuvwxyz'))}

return $password}

#-------------------------Main dispatch-------------------------

$password = switch ($mode) {'P' {generatepin -len $length}
'A' {generatealphanumeric -len $length -useSpaces $useSpaces -useNormalSpecial $useNormalSpecial -useSuperSpecial $useSuperSpecial}
'H' {generatehumanreadable -len $length -useSpaces $useSpaces -useNormalSpecial $useNormalSpecial -useSuperSpecial $useSuperSpecial}
'D' {generatedictionary -len $length -useSpaces $useSpaces -useNormalSpecial $useNormalSpecial -useSuperSpecial $useSuperSpecial}}

Write-Host -f yellow "Password: " -n; Write-Host -f darkgray "$password (" -n

$password.ToCharArray() | ForEach-Object {switch -regex ($_) {'(?-i)[A-Z]' {Write-Host -f gray $_ -n; continue}
'(?-i)[a-z]' {Write-Host -f darkgray $_ -n; continue}
'\d' {Write-Host -f cyan $_ -n; continue}
"[$($specialChars -join '')]" {Write-Host -f yellow $_ -n; continue}
"[$($superSpecialChars -join '')]" {Write-Host -f green $_ -n; continue}
' ' {Write-Host -b blue $_ -n; continue}
default {Write-Host -f magenta $_ -n}}}
Write-Host -f darkgray ") " -n;

return $password}

function emoji {# Display emoji in Choose an Action prompt when there are processing delays.
$script:emoji = $null
if ($choice -eq $null) {$script:emoji = ""}
elseif ($choice -eq 'X') {$script:emoji = "❌ Remove an entry"}
elseif ($choice -eq 'M') {$script:emoji = "🛠️ Management mode"}
elseif ($choice -eq 'K') {$script:emoji = "🗝  Select a key"}
elseif ($choice -eq 'C') {$script:emoji = "🔑 Create a key"}
elseif ($choice -eq 'D') {$script:emoji = "📑 Select a database"}
elseif ($choice -eq 'P') {$script:emoji = "📄 Create a database"}
elseif ($choice -eq 'N') {$script:emoji = "👑 New master password"}
elseif ($choice -eq 'F') {$script:emoji = "👑 Full DB export"}
elseif ($choice -eq 'V') {$script:emoji = "✅ Verify a database"}
elseif ($choice -eq 'I') {$script:emoji = "📥 Import from CSV"}
elseif ($choice -eq 'OEMMINUS') {$script:emoji = "📤 Export to CSV"}
elseif ($choice -eq 'SUBTRACT') {$script:emoji = "📤 Export to CSV"}
elseif ($choice -eq 'OEMCOMMA') {$script:emoji = "📦←︎ Backup"}
elseif ($choice -eq 'OEMPERIOD') {$script:emoji = "📦→︎ Restore"}
elseif ($choice -eq 'F4') {$script:emoji = "🔴 Disable logging"}
elseif ($choice -eq 'F10') {$script:emoji = "🛠️ Modify configuration"}
elseif ($choice -eq 'F12') {$script:emoji = "📄 Sort and save database"}
elseif ($choice -eq 'G') {$script:emoji = "🪪 Grant user privileges"}
elseif ($choice.length -gt 1) {$script:emoji = ""}
else {$script:emoji = $choice}
return $script:emoji}

function limiteduser {# Standard user limitations, regardless of management mode.
emoji; if ($script:standarduser) {$script:warning = "Access to '$script:emoji' is restricted."; nomessage}}

function managementisdisabled {# Restrict access to specific features.
emoji; if (-not $script:management) {$script:warning = "Access to '$script:emoji' is restricted."; nomessage}}

function modifyconfiguration {# Modify the PSD1 configuration.
# Load current settings
$manifest = Import-PowerShellDataFile -Path $configpath
$config = $manifest.PrivateData

# Define editable keys with constraints
$editable = @{defaultkey = @{desc='Key filename'; validate={param($v) $v -match '\S'}}
defaultdatabase = @{desc='Database filename'; validate={param($v) $v -match '\S'}}
keydir = @{desc='Key directory path'; validate={param($v) $v -match '\S'}}
databasedir = @{desc='Database directory path'; validate={param($v) $v -match '\S'}}
timeoutseconds = @{desc='Timeout (max 5940 seconds)'; validate={param($v) try {($v -as [int]) -in 1..5940} catch {$false}}}
timetobootlimit = @{desc='Boot time limit (max 120 minutes)'; validate={param($v) try {($v -as [int]) -in 1..120} catch {$false}}}
delayseconds = @{desc='Clipboard delay (in seconds)'; validate={param($v) try {[int]$v -ge 0} catch {$false}}}
expirywarning = @{desc='Password expiry (1–365 days)'; validate={param($v) try {($v -as [int]) -in 1..365} catch {$false}}}
logretention = @{desc='Log retention (min 30 days)'; validate={param($v) try {[int]$v -ge 30} catch {$false}}}
dictionaryfile = @{desc='Dictionary filename'; validate={param($v) $v -match '\S'}}
backupfrequency = @{desc='Backup frequency (in days)'; validate={param($v) try {[int]$v -ge 1} catch {$false}}}
archiveslimit = @{desc='Archives limit (files to retain)'; validate={param($v) try {[int]$v -ge 1} catch {$false}}}
useragent = @{desc='User-Agent'; validate={param($v) $v -match '\S'}}}

Write-Host -f yellow "`n`nCurrent Configuration:`n"; $i = 0
Write-Host -f cyan "There are currently $($editable.count) configurable items in v$script:version.`n"
foreach ($key in $editable.Keys) {$current = $config[$key]; $i++
Write-Host -f white "$i. $($editable[$key].desc) [$key = '$current']: " -n; $input = Read-Host
if ($input -ne '') {if (-not (& $editable[$key].validate $input)) {Write-Host -f red "Invalid value for $key. Keeping existing value."}
else {$config[$key] = "$input"; Write-Host -f green "$key updated to '$input'"}}}

# Rebuild psd1 content
# Save new file with predictable key order
$lines = @(); $lines += "# Core module details`n@{"

# Desired order for top-level keys
$topKeys = 'RootModule','ModuleVersion','GUID','Author','CompanyName','Copyright','Description'
foreach ($k in $topKeys) {if ($manifest.ContainsKey($k)) {$v = $manifest[$k]
if ($v -is [string]) {$lines += "$k = '$v'"}
elseif ($v -is [array]) {$lines += "$k = @('" + ($v -join "', '") + "')"}
else {$lines += "$k = $v"}}}

# Handle all remaining non-PrivateData keys not in topKeys
foreach ($k in $manifest.Keys | Where-Object {$_ -notin $topKeys -and $_ -ne 'PrivateData'}) {$v = $manifest[$k]
if ($v -is [string]) {$lines += "$k = '$v'"}
elseif ($v -is [array]) {$lines += "$k = @('" + ($v -join "', '") + "')"}
else {$lines += "$k = $v"}}

# Append PrivateData block
$lines += "`n# Configuration data"; $lines += "PrivateData = @{"
foreach ($sk in $config.Keys) {$sv = $config[$sk]; $lines += "$sk = '$sv'"}
$lines += "}}"

# Save new file
Set-Content -Path $configpath -Value $lines -Encoding UTF8; Write-Host -f green "`nConfiguration updated successfully."; initialize; return}

function rendermenu {# Title and countdown timer.
$toggle = if ($script:management) {"Hide"} else {"Show"}; $managementcolour = if ($script:management) {"darkgray"} else {"green"}

# Create border elements.
function endcap {Write-Host -f cyan "+" -n; Write-Host -f cyan ("-" * 70) -n; Write-Host -f cyan "+"}
function horizontal {Write-Host -f cyan "|" -n; Write-Host -f cyan ("-" * 70) -n; Write-Host -f cyan "|"}
function startline {Write-Host -f cyan "|" -n}
function linecap {Write-Host -f cyan "|"}

# Title and countdown timer.
cls; ""; endcap
startline; Write-Host -f white " 🔑 Secure Paschwords Manager v$script:version 🔒".padright(53) -n
if ($script:unlocked) {if ($countdown -ge 540) {Write-Host -f green "🔒 in $($script:minutes +1) minutes " -n}
elseif ($countdown -lt 540 -and $countdown -ge 60) {Write-Host -f green " 🔒 in $($script:minutes +1) minutes " -n}
elseif ($countdown -lt 60) {Write-Host -f red -n ("      🔒 in 0:{0:D2} " -f $script:seconds)}
else {Write-Host "`t`t    🔒 "-n}} 
else {Write-Host "`t`t    🔒 "-n}; linecap
horizontal

# Loaded resource display.
if ($script:database) {$displaydatabase = Split-Path -Leaf $script:database -ea SilentlyContinue} else {$displaydatabase = "none loaded"}
if ($script:keyfile) {$displaykey = Split-Path -Leaf $script:keyfile -ea SilentlyContinue} else {$displaykey = "none loaded"}
$databasestatus = if ($db -and $key -and $db -ne $key) {"🤔"} elseif ($displaykey -eq "none loaded" -or $displaydatabase -eq "none loaded" -or $script:unlocked -eq $false) {"🔒"} else {"🔓"}
$keystatus = if ($script:unlocked -eq $false -or $displaykey -eq "none loaded") {"🔒"} else {"🔓"}

startline; Write-Host -f white " Current database: " -n; Write-Host -f green "$displaydatabase $databasestatus".padright(33) -n
Write-Host -f yellow "⏱️ [T]imer reset. " -n; linecap
startline; Write-Host -f white " Current key: " -n; Write-Host -f green "$displaykey $keystatus".padright(35) -n
if ($displaydatabase -eq "none loaded" -or $displaykey -eq "none loaded") {Write-Host -f green "♻️ Rel[O]ad defaults." -n} else {Write-Host (" " * 21) -n};linecap

if ($displaydatabase -match '^(?i)(.+?)\.pwdb$') {$db = $matches[1]}
if ($displaykey -match '^(?i)(.+?)\.key$') {$key = $matches[1]}
if (($displaykey -eq "none loaded" -or $displaydatabase -eq "none loaded") -and ($script:database -or $script:keyfile)) {if ($script:warning -notmatch "Make sure") {if ($script:warning) {$script:warning += "`n"}; $script:warning += "Make sure to load both a database and a keyfile before continuing."}
if ($db -and $key -and $db -ne $key) {startline; Write-Host -f red " Warning: " -n; Write-Host -f yellow "The key and database filenames do not match.".padright(60) -n; linecap
if ($script:warning -notmatch "Continuing") {if ($script:warning) {$script:warning += "`n"}; $script:warning += "Continuing with an incorrect key and database pairing could lead to data corruption. Ensure you have the correct file combination before making any file changes."}}}

# Display menu options.
horizontal
startline; Write-Host -f cyan " A. " -n; Write-Host -f yellow "➕ [A]dd a new entry or update an existing one.".padright(65) -n; linecap
$clipboard = if ($script:noclip -eq $true) {"🚫"} else {"📋"}
startline; Write-Host -f cyan " R. " -n; Write-Host -f white "🔓 [R]etrieve an entry.".padright(50) -n; Write-Host -f cyan "Z. " -n; Write-Host -f white "Clipboard $clipboard " -n; linecap
startline; Write-Host -f cyan " X. " -n; Write-Host -f red "❌ Remove an entry.".padright(41) -n; if ($script:disablelogging) {Write-Host -f red "Logging is disabled. 🔴 " -n} else {Write-Host -f green "Logging is enabled.  🟢 " -n};linecap
horizontal
startline; Write-Host -f cyan " B. " -n; Write-Host -f white "🧐 [B]rowse all entries: " -n; Write-Host -f cyan "$(($script:jsondatabase).Count)".padright(41) -n; linecap
$today = Get-Date; $expiredcount = ($script:jsondatabase | Where-Object {$_.data.Expires -and ($_.data."Expires" -as [datetime]) -le $today}).Count
startline; Write-Host -f cyan " E. " -n; Write-Host -f white "⌛ [E]xpired entries view: " -n; if ($expiredcount -eq 0) {Write-Host -f green "0".padright(39) -n} else {Write-Host -f red "$expiredcount".padright(39) -n}; linecap
startline; Write-Host -f cyan " S. " -n; Write-Host -f white "🔍 [S]earch entries for specific keywords.".padright(66) -n; linecap
startline; Write-Host -f cyan "   1. " -n; Write-Host -f white "🖥  [1] Find IPs.".padright(65) -n; linecap
startline; Write-Host -f cyan "   2. " -n; Write-Host -f white "👎 [2] Find invalid URLs.".padright(64) -n; linecap
startline; Write-Host -f cyan "   3. " -n; Write-Host -f white "🌐 [3] Find valid URLs.".padright(64) -n; linecap

horizontal
startline; Write-Host -f cyan " M. " -n; Write-Host -f white "🛠️ [M]anagement controls: " -n; Write-Host -f $managementcolour $toggle.padright(40) -n; linecap
horizontal
if ($script:management) {startline; Write-Host -f cyan " K. " -n; Write-Host -f white "🗝️ Select a different password encryption [K]ey.".padright(67) -n; linecap
startline; Write-Host -f cyan " C. " -n; Write-Host -f yellow "🔑 [C]reate a new password encryption key.".padright(66) -n; linecap
horizontal
startline; Write-Host -f cyan " D. " -n; Write-Host -f white "📑 Select a different password [D]atabase.".padright(66) -n; linecap
startline; Write-Host -f cyan " P. " -n; Write-Host -f yellow "📄 Create a new [P]assword database.".padright(66) -n; linecap
horizontal
startline; Write-Host -f cyan " N. " -n; Write-Host -f white "👑 [N]ew master password.".padright(66) -n; linecap
horizontal
startline;  Write-Host -f cyan " V. " -n; Write-Host -f white "✅ [V]alidate a PWDB file and correct IV collisions.".padright(65) -n; linecap
horizontal
startline; Write-Host -f cyan " I. " -n; Write-Host -f yellow "📥 [I]mport a CSV plaintext password database.".padright(66) -n; linecap
startline; Write-Host -f cyan " -  " -n; Write-Host -f white "📤 Export the current database to CSV. " -n; Write-Host -f green "Encryption remains intact. " -n; linecap
startline; Write-Host -f cyan " F. " -n; Write-Host -f white "📂 [F]ull DB export with " -n; Write-Host -f red "unencrypted" -n; Write-Host -f white " passwords.".padright(30) -n; linecap

horizontal
startline; Write-Host -f cyan " <  " -n; Write-Host -f white "📦←︎ Backup currently loaded database and key.".padright(67) -n; linecap
startline; Write-Host -f cyan " >  " -n; Write-Host -f yellow "📦→︎ Restore a backup.".padright(67) -n; linecap
horizontal}

# Session options.
startline; if ($script:unlocked -eq $true) {Write-Host " 🔓 " -n} else {Write-Host " 🔒 " -n}
if ($script:unlocked -eq $true) {Write-Host -f red "[L]ock Session " -n} else {Write-Host -f darkgray "[L]ock Session " -n}
Write-Host -f white "/ " -n;
if ($script:unlocked -eq $true) {Write-Host -f darkgray "[U]nlock session".padright(22) -n} else {Write-Host -f green "[U]nlock session".padright(22) -n}
if (-not (Test-Path $script:keyfile -ea SilentlyContinue)) {Write-Host -f black -b yellow "❓ [H]elp <-- " -n; Write-Host "".padright(4) -n}
else {Write-Host -f yellow "❓ [H]elp".padright(17) -n}
Write-Host -f gray "⏏️ [ESC] " -n;; linecap 
endcap

# Message and warning center.
$script:message = wordwrap $script:message; $script:warning = wordwrap $script:warning
if ($script:message.length -ge 1) {Write-Host "  🗨️" -n; indent $script:message white 2}
if ($script:warning.length -ge 1) {Write-Host "  ⚠️" -n; indent $script:warning red 2}
if ($script:message.length -ge 1 -or $script:warning.length -ge 1 ) {Write-Host -f cyan ("-" * 72)}
$lastcommand = emoji; Write-Host -f white "⚡ Choose an action: " -n}

function logchoices ($choice, $message, $warning){# Log user actions.
# Do not log if the user has turned off logging.
if ($script:disablelogging) {return}

# Redact sensitive lines from message
if ($message) {$logmessage = ($message -replace '🔐 Password:.*', '🔐 Password: [REDACTED]' -replace '🔗 URL: .*', '🔗 URL:      [REDACTED]' -replace '🆔 UserName:.*', '🆔 UserName: [REDACTED]') -split '(?m)^[-]{10,}' | Select-Object -First 1}

# Map keys to descriptions.
$map = @{'A' = 'Add an entry'; 'B' = 'Browse entries'; 'C' = 'Create a key'; 'D' = 'Select a database'; 'D1' = 'Find IPs'; 'D2' = 'Find invalid URLs'; 'D3' = 'Find valid URLs'; 'E' = 'View expired entries'; 'G' = 'Grant user privileges'; '.A' = 'Add user';'.B' = 'Backup privilege settings'; '.R' = 'Remove user'; '.U' = 'Update user'; '.V' = 'View user registry';'.Q' = 'Quit Grant user privileges'; 'H' = 'Help'; 'I' = 'Import a CSV'; 'K' = 'Select a key'; 'L' = 'Lock'; 'M' = 'Toggle management view'; 'O' = 'Restore Default Key & Database'; 'P' = 'Create a database'; 'Q' = 'Quit'; 'R' = 'Retrieve an entry'; 'S' = 'Search entries'; 'T' = 'Reset timer'; 'U' = 'Unlock'; 'V' = 'Verify a PWDB'; 'X' = 'Remove an entry'; 'Z' = 'Toggle Clipboard'; 'F1' = 'Help'; 'F4' = 'Toggle logging'; 'F9' = 'Display configuration information'; 'F10' = 'Modify configuation'; 'F12' = 'Sort and save database'; 'OEMPERIOD' = 'Backup key and database'; 'OEMCOMMA' = 'Restore a key and database'; 'OEMMINUS' = 'Export to CSV'; 'SUBTRACT' = 'Export to CSV'; 'BACKSPACE' = 'Clear message center'}

# Create directory, if it doesn't exist.
if (-not (Test-Path $script:logdir)) {New-Item $script:logdir -ItemType Directory -Force | Out-Null}

# Cleanup old logs (older than the number of days set in logretention, with the minimum set to 30 days).
Get-ChildItem -Path $script:logdir -Filter 'log - *.log' | Where-Object {$_.LastWriteTime -lt (Get-Date).AddDays(-[int]$script:logretention)} | Remove-Item -Force

# Create base file each session.
if (-not $script:logfile) {$timestamp = (Get-Date).ToString('MM-dd-yy @ HH_mm_ss'); $script:logfile = Join-Path $script:logdir "log - $timestamp.log"}

# Map unknown keys.
if (-not $map.ContainsKey($choice)) {Add-Content -Path $script:logfile -Value "$(Get-Date -Format 'HH:mm:ss') - UNRECOGNIZED: $choice"; return}

# Compile entry information.
$timestamp = Get-Date -Format 'HH:mm:ss'; $info = "$(if ($message) {" - MESSAGE: $logmessage"})$(if ($warning) {" - WARNING: $warning"})"; $entry = "$timestamp - $script:loggedinuser - $($map[$choice])$info`n" + ("-" * 100)

# Ensure log gets written by retrying 5 times for every log, to avoid race conditions.
$retries = 5
for ($i = 0; $i -lt $retries; $i++) {try {$fs = [System.IO.File]::Open($script:logfile, 'Append', 'Write', 'ReadWrite'); $sw = New-Object System.IO.StreamWriter($fs)
$sw.WriteLine($entry); $sw.Close(); $fs.Close(); break}
catch {Start-Sleep -Milliseconds 100}}}

function logcleanup {# Compress log files.

function gziplog ($inputFile, $outputFile = "$inputFile.gz") {$inputStream = [System.IO.File]::OpenRead($inputFile); $outputStream = [System.IO.File]::Create($outputFile); $gzipStream = New-Object System.IO.Compression.GZipStream($outputStream, [System.IO.Compression.CompressionMode]::Compress); $inputStream.CopyTo($gzipStream); $gzipStream.Close(); $inputStream.Close(); $outputStream.Close()}

$today = (Get-Date).Date; Get-ChildItem -Path $script:logdir -Filter 'log - *.log' | Where-Object {$_.Name -match '^log - (\d{2})-(\d{2})-(\d{2}) @'} | Group-Object {if ($_.Name -match '^log - (\d{2})-(\d{2})-(\d{2})') {$mm = $matches[1]; $dd = $matches[2]; $yy = $matches[3]; $fileDate = Get-Date "$mm-$dd-20$yy"
if ($fileDate -lt $today) {"$mm-$dd-$yy"} else {$null}}} | Where-Object {$_.Name} | ForEach-Object {$date = $_.Name; $output = Join-Path $script:logdir "log - $date.log"; $_.Group | Sort-Object LastWriteTime | ForEach-Object {Get-Content $_.FullName | Add-Content -Path $output}
$_.Group | ForEach-Object {Remove-Item $_.FullName -Force}
gziplog $output; Remove-Item $output -Force}}

function login {# Display initial login screen.
initialize; setdefaults; logcleanup; resizewindow
if (-not (verify)) {return}

$script:sessionstart = Get-Date; $script:key = $null; Write-Host -f yellow "`n`t+-------------------------------------+`n`t|  🔑  Secure Paschwords Manager  🔒  |`n`t|-------------------------------------|" -n

# Unlock the database and authenticate the user in order to allow access, if the environment is already established.
if (-not $script:keyexists -and -not (Test-Path $script:registryFile -ea SilentlyContinue)) {loggedin}
elseif (-not $script:keyexists) {Write-Host -f white "`n`t`tNo database key present.`n`t"; loginfailed}
elseif ($script:keyexists) {decryptkey $script:keyfile
if ($script:key) {if (authenticateuser) {loggedin}}
else {loginfailed}}}

function loginfailed {# Login failed.
Write-Host -f yellow "`t|-------------------------------------|`n`t|" -n; Write-Host -f red "   😲  Access Denied! ABORTING! 🔒   " -n; Write-Host -f yellow "|`n`t+-------------------------------------+`n"; return}

function logoff {# Exit screen.
nowarning; nomessage; Write-Host -f red "Securing the environment..."; neuralizer; $choice=$null; rendermenu; Write-Host -f white "`n`t`t    ____________________`n`t`t   |  ________________  |`n`t`t   | |                | |`n`t`t   | |   🔒 "-n; Write-Host -f red "Locked." -n; Write-Host -f white "   | |`n`t`t   | |                | |`n`t`t   | |________________| |`n`t`t   |____________________|`n`t`t    _____|_________|_____`n`t`t   / * * * * * * * * * * \`n`t`t  / * * * * * * * * * * * \`n`t`t ‘-------------------------’`n"; return}

function loggedin {# Once key is unlocked, allow access to the dynamic menu.
$script:sessionstart = Get-Date; $choice = $null
loadjson
rendermenu
scheduledbackup

do {# Wait for a keypress, in order to refresh the screen.
while (-not [Console]::KeyAvailable -and -not $script:quit) {

# End function at user request.
if ($script:quit) {logoff; return}

# End script after a preset number of minutes of inactivity.
if ($script:timetoboot -ne $null) {$elapsed = (Get-Date) - $script:timetoboot
if ($elapsed.TotalMinutes -ge $script:timetobootlimit) {$script:quit = $true; logoff; return}}

# Set session timer variables.
$timeout = (Get-Date).AddSeconds(10); $countdown = [int]($script:timeoutseconds - ((Get-Date) - $script:sessionstart).TotalSeconds); if ($countdown -lt 0) {$countdown = 0}; $script:minutes = [int]([math]::Floor($countdown / 60)); $script:seconds = $countdown % 60

# Lock session when timer runs out and break from continual refreshes.
if ($script:unlocked -eq $true -and $countdown -le 0) {neuralizer; $script:message = "Session timed out. The key has been locked."; rendermenu}

# Refresh display if session is unlocked
if ($script:unlocked -and ($countdown -lt 60 -or $script:minutes -lt $script:lastrefresh)) {rendermenu; $script:lastrefresh = $script:minutes}

# Wait for next loop.
if ($countdown -gt 60) {Start-Sleep -Milliseconds 250}
else {Start-Sleep -Seconds 1}}

# Send key presses to the menu for processing.
if ([Console]::KeyAvailable -and -not $script:quit) {$key = [Console]::ReadKey($true); $choice = $key.Key.ToString().ToUpper()

logchoices $choice $script:message $script:warning
switch ($choice) {
'A' {# Add a new entry.
if ($script:database -and $script:keyfile -and $script:unlocked) {$addorupdate = $null; Write-Host -f yellow "`n`nAdd a new entry, or Update an existing one? (Add/Update) " -n; $addorupdate = Read-Host
if (-not $addorupdate) {$script:warning = "Aborted."; nomessage; rendermenu; break}
if ($addorupdate -match "(?i)^a(dd)?") {newentry $script:database $script:keyfile; rendermenu}
elseif ($addorupdate -match "(?i)^u(pdate)?") {Write-Host -f green "`n🔓 Enter Title, 🆔 Username, 🔗 URL, 🏷  Tag or 📝 Note to identify entry (comma separated): " -n; $searchterm = Read-Host
if ([string]::IsNullOrWhiteSpace($searchterm)) {$script:warning = "No search term provided."; nomessage; rendermenu; break}
elseif ($searchterm) {updateentry $script:jsondatabase $script:keyfile $searchterm}}}
else {$script:warning = "A database and key must be opened and unlocked to add an entry."; nomessage; rendermenu; break}}

'R' {# Retrieve an entry.
if (-not $script:keyfile) {$script:warning = "🔑 No key loaded."; nomessage}

if (-not $script:jsondatabase) {$script:warning = "📑 No database loaded. " + $script:warning; nomessage}

if ($script:keyfile -and $script:jsondatabase) {Write-Host -f green "`n`n🔓 Enter Title, 🆔 Username, 🔗 URL, 🏷  Tag or 📝 Note to identify entry: " -n; $searchterm = Read-Host}

if ([string]::IsNullOrWhiteSpace($searchterm)) {$script:warning = "No search term provided."; nomessage}

elseif ($searchterm) {retrieveentry $script:jsondatabase $script:keyfile $searchterm $noclip}
rendermenu}

'X' {# Remove an entry.
limiteduser; if ($script:standarduser) {rendermenu; break}
Write-Host -f red "`n`n❌ Enter Title, Username, URL, Tag or Note to identify entry: " -n; $searchterm = Read-Host; removeentry $searchterm; rendermenu}

'B' {# Browse all entries from memory.
if (-not $script:jsondatabase -or -not $script:jsondatabase.Count) {$script:warning = "No valid entries loaded in memory to display."; nomessage}
else {showentries $script:jsondatabase; nomessage; nowarning}}

'E' {# Retrieve expired entries.
if (-not $script:jsondatabase -or -not $script:jsondatabase.Count) {$script:warning = "📑 No database loaded."; nomessage; rendermenu}

$expiredEntries = $script:jsondatabase | Where-Object {try {[datetime]::Parse($_.data.expires) -le (Get-Date)}
catch {$false}}

if (-not $expiredEntries.Count) {$script:warning = "No expired entries found."}
else {showentries $expiredEntries -expired; nowarning}; nomessage; rendermenu}

'S' {# Search for keyword matches.
if (-not $script:jsondatabase -or $script:jsondatabase.Count -eq 0) {$script:warning = "📑 No database loaded."; nomessage; rendermenu; break}

Write-Host -f yellow "`n`nProvide a comma separated list of keywords to find: " -n; $keywords = Read-Host

if (-not $keywords -or $keywords.Trim().Length -eq 0) {$matchedEntries = $null; $script:warning = "No search terms provided."; nomessage; rendermenu}

# Split keywords, trim and to lowercase for case-insensitive matching
$pattern = "(?i)(" + ($keywords -replace "\s*,\s*", "|") + ")"; $matchcount = 0; $script:warning = $null
foreach ($entry in $script:jsondatabase) {if ($entry.data.Title -match $pattern -or $entry.data.Username -match $pattern -or $entry.data.URL -match $pattern -or $entry.data.Tags -match $pattern -or $entry.data.Notes -match $pattern) {if (-not (verifyentryhmac $entry)) {$script:warning += "Entry $($entry.data.title) has an invalid HMAC and will be ignored. "; continue}
$matchcount++; break}}

if ($matchcount -eq 0) {$script:warning = "No matches found for provided keywords."; nomessage; rendermenu}

else {showentries $script:jsondatabase -search -keywords "$pattern"; nomessage; nowarning}}

'D1' {# Search for IP matches.
if (-not $script:jsondatabase -or -not $script:jsondatabase.Count) {$script:warning = "📑 No database loaded."; nomessage; rendermenu}
else {showentries $script:jsondatabase -ips; nomessage; nowarning}}

'D2' {# Search for invalid URLs.
if (-not $script:jsondatabase -or -not $script:jsondatabase.Count) {$script:warning = "📑 No database loaded."; nomessage; rendermenu}
else {showentries $script:jsondatabase -invalidurls; nomessage; nowarning}}

'D3' {# Search for valid URLs.
if (-not $script:jsondatabase -or -not $script:jsondatabase.Count) {$script:warning = "📑 No database loaded."; nomessage; rendermenu}
else {showentries $script:jsondatabase -validurls; nomessage; nowarning}}

'M' {# Toggle Management mode.
if ($script:management -eq $true) {$script:management = $false; nowarning; nomessage; rendermenu; break}
if ($script:standarduser) {limiteduser; rendermenu; break}

else {nowarning; $script:management = $true}
nomessage; rendermenu}

'K' {# Select a different password encryption key.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
$script:keyfiles = Get-ChildItem -Path $script:keydir -Filter *.key
if (-not $script:keyfiles) {$script:warning = "No .key files found."; nomessage; rendermenu}
elseif ($script:keyfiles) {Write-Host -f white "`n`n🗝  Available AES Key Files:"; Write-Host -f yellow ("-" * 70)
for ($i = 0; $i -lt $script:keyfiles.Count; $i++) {Write-Host -f cyan "$($i+1). " -n; Write-Host -f white $script:keyfiles[$i].Name}
Write-Host -f green "`n🗝  Enter number of the key file to use: " -n; $sel = Read-Host
if ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le $script:keyfiles.Count) {$script:keyfile = $script:keyfiles[$sel - 1].FullName; $script:keyexists = $true; nowarning; neuralizer; decryptkey $script:keyfile
if ($script:unlocked) {if ($script:keyfile -match '(?i)((\\[^\\]+){2}\\\w+\.KEY)') {$shortkey = $matches[1]}
else {$shortkey = $script:keyfile}
$script:message = "$shortkey selected and made active."; nowarning; $script:disablelogging = $false}
if (-not $script:key) {$script:warning += " Key decryption failed. Aborting."; nomessage}}}; rendermenu}

'C' {# Create a new password encryption key.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
Write-Host -f green "`n`n🔑 Enter filename for new keyfile: " -n; $getkey = Read-Host
if ($getkey -lt 1) {$script:warning = "No filename entered."; nomessage; rendermenu}
else {if (-not $getkey.EndsWith(".key")) {$getkey += ".key"}
newkey $getkey; rendermenu}}

'D' {# Select a different database.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
$dbFiles = Get-ChildItem -Path $script:databasedir -Filter *.pwdb
if (-not $dbFiles) {$script:warning = "No .pwdb files found."; nomessage; rendermenu}
else {Write-Host -f white "`n`n📑 Available Password Databases:"; Write-Host -f yellow ("-" * 70)
for ($i = 0; $i -lt $dbFiles.Count; $i++) {Write-Host -f cyan "$($i+1). " -n; Write-Host -f white $dbFiles[$i].Name}
Write-Host -f green "`n📑 Enter number of the database file to use: " -n; $sel = Read-Host
if ($sel -match '^\d+$' -and $sel -ge 1 -and $sel -le $dbFiles.Count) {$script:jsondatabase = $null; $script:database = $dbFiles[$sel - 1].FullName; $dbloaded = $script:database -replace '.+\\Modules\\', ''; loadjson; $script:message = "$dbloaded selected and made active."
if ($script:jsondatabase.Count -eq 0) {$script:warning = "If changing database and key combinations, always load the key before the database."} else {nowarning}}
else {$script:warning = "Invalid selection."; nomessage}; rendermenu}}

'P' {# Create a new password database.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
Write-Host -f green "`n`n📄 Enter filename for new password database: " -n; $getdatabase = Read-Host
if ($getdatabase.length -lt 1) {$script:warning = "No filename entered."; nomessage; rendermenu}
else {if (-not $getdatabase.EndsWith(".pwdb")) {$getdatabase += ".pwdb"}
$path = Join-Path $script:databasedir $getdatabase
if (Test-Path $path) {$script:warning = "File already exists. Choose a different name."; nomessage}
else {$script:jsondatabase = $null; $script:jsondatabase = @(); decryptkey $script:keyfile; $script:database = $Path
savetodisk; $script:message = "📄 New database $getdatabase created."; nowarning}; rendermenu}}

'N' {# New master password.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
managementisdisabled
if ($script:key) {rotatemasterpassword; rendermenu}}

'F' {# Full db export.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
if ($script:key) {fulldbexport; rendermenu}}

'V' {# Verify a PWDB file.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
validatedatabase}

'I' {# Import a CSV password database.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
$script:message = "Imported files must contain the fields: Title, Username, Password and URL. Timestamp is ignored and Password can be empty, but must exist. All other fields can be added as notes and/or tags. Fields added to notes will only be added if they are populated. Fields added to tags can be added to all imported entries or only those that are populated."; nowarning
if (-not $script:database -and -not $script:keyfile) {$script:warning = "You must have a database and key file loaded in order to start an import."; nomessage; return}
Write-Host -f yellow "`n`n📥 Enter the full path to the CSV file: " -n; $csvpath = Read-Host
if ($csvpath.length -lt 1) {$script:warning = "Aborted."; nomessage; rendermenu}
elseif (Test-Path $csvpath -ea SilentlyContinue) {importcsv $csvpath}
else {$script:warning = "CSV not found."; nomessage}; rendermenu}

'OEMMINUS' {# Export all entries.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
nomessage; nowarning; rendermenu
Write-Host -f yellow "`n`nProvide an export path for the database.`nOtherwise the database directory will be used: " -n; $path = Read-Host
if ($path.length -lt 1) {$path = "$script:database"; $path = $path -replace '\.pwdb$', '.csv'}
Write-Host -f yellow "`nSpecify the fields and the order in which to includet them.`nThe default is (" -n; Write-Host -f white "Title, Username, URL" -n; Write-Host -f yellow "): " -n; $fields = Read-Host
if ($fields.length -lt 1) {$fields = "Title,Username,URL"}
$fields = $fields -replace "\s*,\s*", ","
Write-Host -f yellow "`nProceed? (Y/N) " -n; $confirmexport = Read-Host
if ($confirmexport -match "^[Yy]$") {export $path $fields} else {$script:warning = "Aborted."; nomessage; rendermenu}}

'SUBTRACT' {# Export all entries.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
nomessage; nowarning; rendermenu
Write-Host -f yellow "`n`nProvide an export path for the database.`nOtherwise the database directory will be used: " -n; $path = Read-Host
if ($path.length -lt 1) {$path = "$script:database"; $path = $path -replace '\.pwdb$', '.csv'}
Write-Host -f yellow "`nSpecify the fields and the order in which to includet them.`nThe default is (" -n; Write-Host -f white "Title, Username, URL" -n; Write-Host -f yellow "): " -n; $fields = Read-Host
if ($fields.length -lt 1) {$fields = "Title,Username,URL"}
$fields = $fields -replace "\s*,\s*", ","
Write-Host -f yellow "`nProceed? (Y/N) " -n; $confirmexport = Read-Host
if ($confirmexport -match "^[Yy]$") {export $path $fields; rendermenu} else {$script:warning = "Aborted."; nomessage; rendermenu}}

'OEMCOMMA' {# Backup current database and key.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
backup; rendermenu}

'OEMPERIOD' {# Retore a backup.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
restore; rendermenu}

'L' {# Lock session.
$script:message = "Session locked."; nowarning; neuralizer; rendermenu}

'U' {# Unlock session.
if ($script:keyfile) {""; decryptkey $script:keyfile}
else {$script:warning = "🔑 No key loaded."; nomessage}
if ($script:unlocked) {loadjson; $script:disablelogging = $false; $script:message += " Session unlocked."}; nowarning; rendermenu}

'Z' {# Toggle clipboard.
if ($script:noclip -eq $true) {$script:noclip = $false; $script:message = "Retrieved passwords will be copied to the clipboard for $script:delayseconds seconds."; nowarning; rendermenu}
elseif ($script:noclip -eq $false) {$script:noclip = $true; $script:message = "Retrieved passwords will not be copied to the clipboard."; nowarning; rendermenu}}

'Q' {# Quit. (Includes funky logic to capture keys after the user confirms.)
Write-Host -f green "`n`nAre you sure you want to quit? (Y/N) " -n; $confirmquit = Read-Host
if ($confirmquit -notmatch "^[Yy]$") {$script:warning = "Aborted."; nomessage; rendermenu}
else {$script:quit = $true; logoff; while ([Console]::KeyAvailable) {return}; return}}

'H' {# Help.
nowarning
if ($script:keyexists -eq $false) {$script:warning = "First time use: You will need to create key and database files with the menu options above. The defaults configured in the PSD1 file use the filename 'paschwords' for both."}
else {helptext}; rendermenu}

'F1' {# Help.
nowarning
if ($script:keyexists -eq $false) {$script:warning = "First time use: You will need to create key and database files with the menu options above. The defaults configured in the PSD1 file use the filename 'paschwords' for both."}
else {helptext}; rendermenu}

'ESCAPE' {# Quit. (Includes funky logic to capture keys after the user confirms.)
Write-Host -f green "`n`nAre you sure you want to quit? (Y/N) " -n; $confirmquit = Read-Host
if ($confirmquit -notmatch "^[Yy]$") {$script:warning = "Aborted."; nomessage; rendermenu}
else {; logoff; while ([Console]::KeyAvailable) {return}; return}}

'T' {# Set Timer.
if (-not $script:keyfile -or -not $script:unlocked) {$script:warning = "You must have a key loaded and unlocked to reset its timer."; nomessage; rendermenu}
else {""; decryptkey $script:keyfile
if (-not $script:unlocked) {neuralizer; rendermenu}
if ($script:unlocked) {loadjson; Write-Host -f yellow "`nHow many minutes should the session remain unlocked? (1-99) " -n; $usersetminutes = Read-Host; if ($usersetminutes -as [int] -and [int]$usersetminutes -ge 1 -and [int]$usersetminutes -le 99) {$script:timeoutseconds = [int]$usersetminutes * 60; $script:sessionstart = Get-Date; $script:lastrefresh = 99; rendermenu}
else {$script:warning = "Invalid timer value set."; nomessage; rendermenu}}}}

'O' {# Reload defaults.
if (-not $script:database -or -not $script:keyfile) {$script:unlocked = $false; $script:database = $script:defaultdatabase; $script:keyfile = $script:defaultkey; ""; decryptkey $script:keyfile
if ($script:unlocked) {loadjson; $script:message += " Defaults successfully loaded and made active."; nowarning; rendermenu}
else {$script:database = $null; $script:keyfile = $null; rendermenu}}}

'BACKSPACE' {# Clear messages.
nomessage; nowarning; rendermenu}

'ENTER' {# Clear messages.
nomessage; nowarning; rendermenu}

'F4' {# Turn off Logging.
if ($script:standarduser) {limiteduser; rendermenu; break}
if ($script:keyfile -match '\\([^\\]+)$') {$shortkey = $matches[1]}
if ($script:disablelogging -eq $true) {$script:warning = "Logging is already turned off for $shortkey."; nomessage; rendermenu; break}
elseif ($script:disablelogging -eq $false) {$script:disablelogging = $true; $script:warning = "Logging temporarily turned off for $shortkey @ $(Get-Date)"; nomessage; rendermenu}}

'F9' {# Configuration details.
$fixedkeydir = $keydir -replace '\\\\', '\' -replace '\\\w+\.\w+',''; $fixeddatabasedir = $databasedir -replace '\\\\', '\' -replace '\\\w+\.\w+',''; $configfileonly = $script:configpath -replace '.+\\', ''; $keyfileonly = $defaultkey -replace '.+\\', ''; $databasefileonly = $defaultdatabase -replace '.+\\', ''; $dictionaryfileonly = $dictionaryfile -replace '.+\\', ''; $timeoutminutes = [math]::Floor($timeoutseconds / 60); $privilege = if ($script:standarduser) {"Standard user"} else {"Privileged user"}
$script:message = "Configuration Details:`n`nCurrent User:`t`t   $script:loggedinuser`nAccess:`t`t   $privilege`n`nVersion:`t`t   $script:version`nConfiguration File Path: $configfileonly`nDefault Key:             $keyfileonly`nDefault Database:        $databasefileonly`nDictionary File:         $dictionaryfileonly`n`nSession Inactivity Timer: $timeoutseconds seconds / $timeoutminutes minutes`nScript Inactivity Timer:  $script:timetobootlimit minutes`nClipboard Timer:          $delayseconds seconds`nEntry Expiration Warning: $expirywarning days`nLog Retention:            $logretention days`nBackup Frequency:         $script:backupfrequency days`nArchives Limit:           $script:archiveslimit ZIP files`n`nDirectories:`n$fixedkeydir`n$fixeddatabasedir`n`nValidateURLs User-Agent:`n$script:useragent"; nowarning; rendermenu}

'F10' {# Modify PSD1 configuration.
managementisdisabled; if ($script:standarduser) {rendermenu; break}
modifyconfiguration; $script:database = $script:defaultdatabase; $script:keyfile = $script:defaultkey; Write-Host -f yellow "Reloading default key and database."; $script:key = decryptkey $script:keyfile
if ($script:unlocked) {$script:message = "New configuration active. Default key and database successfully loaded and made active."; nowarning}
rendermenu}

'F12' {# Sort and resave database.
managementisdisabled; if ($script:standarduser) {rendermenu; break} 

if (masterlockout) {rendermenu; break}

Write-Host -f green  "`n`n`t👑 Enter Master Password " -n; $master = Read-Host -AsSecureString
if (-not (verifymasterpassword $master)) {$script:failedmaster ++; $script:warning = "Wrong master password. $([math]::Max(0,4 - $script:failedmaster)) attempts remain before lockout."}

saveandsort; if ($script:message) {$script:message += "`nDatabase has been sorted by tag, then title."}; rendermenu}

'G' {# Grant user privileges.
managementisdisabled; if ($script:standarduser) {rendermenu; break}

if (masterlockout) {rendermenu; break}

Write-Host -f green  "`n`n`t👑 Enter Master Password " -n; $master = Read-Host -AsSecureString
if (-not (verifymasterpassword $master)) {$script:failedmaster ++; $script:warning = "Wrong master password. $([math]::Max(0,4 - $script:failedmaster)) attempts remain before lockout."}

usermanagement; rendermenu}

default {if ($choice.length -gt 0) {$script:warning = "'$choice' is an invalid choice."}}}

# Reset on key press.
$script:sessionstart = Get-Date
$choice = $null}} while (-not $script:quit)}

# Initialize and launch.
login}

Export-ModuleMember -Function paschwords

<#
## Overview

❓ Usage: pwmanage <database.pwdb> <keyfile.key> -noclip

Most features should be self-explanatory, but here are some useful pieces of information to know:

Standard users have permissions to view, search and retrieve entries, toggle clipboard, lock and unlock the session and reset the timer. All other features are only granted to privileged users. If a standard user wants to load a different database and key, they will need to do so by specifying it at the command line.

It is best practice to save key files somewhere distant from the databases. Saving them in different directories on the same hard drive does not count as proper security management, but if this is being used as a personal password manager, then it isn't typically an issue.

The import function is extremely powerful, accepting non-standard fields and importing them as tags, notes, or both. This should make it capable of importing password databases from a wide variety of other password managers, commercial and otherwise. Press 'I' in management mode for more details.

When the clipboard empties, it is first overwritten with junk, in order to reduce memory artefacts. Clipboard managers would make this pointless, but this method can still be effective in commercial environments, provided proper application hygeine is in place.

There are also some hidden keys within the main menu:

• Use 'G' to launch the User management menu.
• Use 'F4' to disable logging for the currently loaded key, until the key is locked or unloaded.
• Use 'F9' to see the current script configuration details and 'F10' to change them.
• Use 'F12' to sort the currently loaded database by tag, then title and save the changes to disk.

## PSD1 Configuration

You can view the current configuration with F9 and edit it with F10. The Privlege directory however, where the Master hash and key are kept are not accessible through the in module configuration, for safety reasons. All other settings are all loaded from the accomanying PSD1 file:

• The default database and key file names and their respective file paths make it easier to locate and switch databases, on the fly.

• If you use some path under DefaultPowerShellDirectory, this will be replaced in the script with the user's actual PowerShell directory.

• The standard inactivity timeout locks sessions after the specified number of seconds of inactivity.

• The standard time to boot takes over after the inactivity timer and exits the function altogether, after this second timer expires.

• The clipboard time out represents the number of seconds a retrieved password will remain in the clipboard memory before being overwritten with junk information and then cleared. Incidentally, the copy to clipboard feature can be disabled at launch by using the -noclip function, but can by also be toggled inside the function.

• The default expiration value represents the number of days after creation date that an entry will enter the reminder pool. This in no way modifies the entries. It just presents a recommended date for updating passwords. The default is set to the 365 days maximum that is allowed. Values less than this can of course be set. 60 days for example, is common in corporate environments.

• The Backup frequency sets the number of days between backups and the Archives limit sets the maximum number of backups to keep for each database and key combination.

• Log retention defaults to 30 days. This is also the minimum allowed, but there is no upper limit.

• The default Common.dictionary file used for the built-in Paschword Generator can be replaced with any plaintext word list.

• The useragent represents the value passed to the accompanying ValidateURLs.ps1, if utlized from within the valid URL export feature.
## Paschword Generator Modes
When a new entry is added to the database, the user is presented with an option to use the built-in paschword generator, providing users with the ability to create paschwords which meet all typical security requirements, but also features several intelligent mechanisms to build  more useful and memorable paschwords.

By typing a series of options at the design prompt, users can create paschword patterns that meet their preferences. Using a hierarchical model, these option are:

• [P]IN: This option supercedes all others and creates a purely numerical paschword, with a minimum character length of 4 and maximum of 16.

• [H]uman readable: This option uses a plaintext dictionary to extract two or more words at random, in order to generate a paschword. These are then run through an alphanumeric word derivation, commonly known as 'leet' code, wherein certain letters are replaced with similar looking numbers and symbols.

• [D]ictionary words only: While not typically as secure as human readable word derivations, this method is the same as the last, but skips the 'leet' code replacement.

• [A]lphanumeric: This is your most common paschword generator, starting with a base of letters and numbers to create a random string of characters.

## Paschword Word Derivations
A few notes about the word derivations:

• All of the options except for PIN will randomize the case of words, so that there should always be a strong mix of upper-case and lower-case letters.

• All 3 of these options will also include at least 1 number.

• The 2 options that use the dictionary have a minimum character length of 12, while the PIN and Alphanumeric options have a minimum character length of 4.

• The maximum character length of all paschwords is 32, except for PIN, which as previously mentioned is 16.

• The included dictionary used for Human readable and Dictionary paschwords contains 4720 common English words with a minimum length of 4 letters and a maximum of 10. This list was pulled from Google's most common words list and modified to remove suffixes and most proper nouns. So, you would find words like encrypt, but not encrypted or encrypts. This was done in order to make the word list as compact and diverse as possible.

• The included dictionary may be replaced with any plaintext dictionary, if so desired. It is after all, just a base for pseudo-random paschword generation, while attempting to make the words easier for humans to decipher and remember, because it's great if you have a paschword that is 32 characters long and contains nothing but random symbols, mixed-case letters and numbers, but if you can't remember it, then this can often work to your detriment.
## Paschword Generator Modifiers
Next up are the paschword derivations, of which there are 3:

• [X] Spaces may be included, but will never appear as the first or last letter of a paschword. In the Human readable and Dictionary options, the spaces, if they appear, will always be located between words, in order to make them more useful for generating those memorable paschwords.

• [S]pecial characters includes the following characters: ~!@#$%^&*_-+=.,;:.

• [Z]uper special characters will also includes brackets: (){}[].

If the Special or Zuper special character options are chosen, a minimum of 1 character is guaranteed to exist in the paschword. This does not mean that there will be 1 Special and 1 Zuper special character, just that there will be 1 that belongs to either of those two groups, if requested.
----------------------------------------------------------------------------------------------------
The final element determines the paschword length, with a previously stated minimum of 4 and maximum of 32, but 16 in the case of a PIN.

• [#]4-32 characters in length.
## Paschword Generator Examples
What does this look like in practice?

P12: Would generate a 12 character PIN.

AS32: This would generate an Alphanumeric paschword, with special characters and a length of 32 characters. This is complex and random, but not very memorable.

DXS12: This is the default paschword generation model, which will be used if no characters are typed at the design prompt. It will create a 12 character paschword based on Dictionary words, include standard Special characters and may contains Spaces. This makes for very memorable paschwords, but still random enough to make it difficult for standard decipering tools like brute force or rainbow tables from being able to decipher them.

Now, you have the tool at your disposal, you can use it to mix and match as you see fit. What do you need? DS12, HXS14 AS8? You decide. The paschword generator will create one for you based on the provided critera and ask you if you're satisfied with the result before accepting it. It's fast and easy.
## Technical Details

This module has been written to be as powerful and flexible as possible, while remaining open source.

• The Key files use AES-256-CBC encryption, with a PBKDF2-derived key from the master paschword. A random IV is generated for each key file and prepended to the encrypted content.

• The paschword entries are encrypted using AES-256-CBC with a random IV. The ciphertext is also Base64-encoded for storage.

• The database files are serialized to JSON, compressed with GZIP, then prepended with the AES IV, encrypted using AES-256-CBC, and finally Base64-encoded.

• When a session is locked, the database and key are not just cleared from memory. Both are overwritten several times with junk data much larger than the size of the original elements before being set to null, as are several of the internal, temporary variables, in order to maximize security and decrease the likelihood of successful artefact capture through the use of memory forensic tools. Is this overkill? Yes, probably, but it didn't take a lot of effort on my part to make it signficantly safer in this regard.

• The Paschword generator uses a dictionary containing 4720 of the most common English words between 4 and 10 characters in length, without suffixes, in order to make diversity broader and yet, easily recognizable. Standard randomizers also exist for paschwords without any discernible patterns.
## License

MIT License

Copyright (c) 2025 Schvenn

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
##>
