# laptop-genuineness: read-only health and genuineness check for any Windows 10/11 laptop.
#
# Run from an ADMIN PowerShell (Win + X -> Terminal (Admin)), either:
#   straight from GitHub:  irm https://raw.githubusercontent.com/Dev010904/laptop-genuineness/main/check.ps1 | iex
#   or from a USB stick:   powershell -ExecutionPolicy Bypass -File "E:\laptop-genuineness\check.ps1"
#
# It only READS information. Nothing on the laptop is changed.
param([switch]$NoOpen)

$ErrorActionPreference = 'SilentlyContinue'
# When run from a URL there is no script folder, so save to the Desktop
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'laptop-test-report' }
New-Item -ItemType Directory -Force $dir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$report = Join-Path $dir "report-$stamp.txt"
$batteryHtml = Join-Path $dir "battery-$stamp.html"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

$flags = New-Object System.Collections.Generic.List[object]
function Flag($level, $text) { $flags.Add([pscustomobject]@{ Level = $level; Check = $text }) }
function Section($title) { "`n==================== $title ====================" }
function Chars($arr) { -join ($arr | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) }
function Show { $input | Out-String -Stream | Where-Object { $_.Trim() } }

& {
    "Laptop inspection - $(Get-Date)"
    if (-not $isAdmin) {
        "!! NOT running as Administrator - SSD wear/hours and some battery data will be missing !!"
        Flag 'WARN' 'Not run as Administrator - re-run from Terminal (Admin) for full results'
    }

    Section 'MODEL / SERIAL  (compare with the box, the sticker under the laptop and the bill)'
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $cs | Select-Object Manufacturer, Model, SystemSKUNumber | Format-List | Show
    $bios | Select-Object SerialNumber, SMBIOSBIOSVersion, ReleaseDate | Format-List | Show
    Get-CimInstance Win32_BaseBoard | Select-Object Product, SerialNumber | Format-List | Show
    if (-not $bios.SerialNumber -or $bios.SerialNumber -match 'To be filled|Default|^0+$|O\.E\.M') {
        Flag 'FAIL' "BIOS serial number is missing or generic ('$($bios.SerialNumber)') - motherboard may be replaced"
    }

    Section 'CPU  (compare with the advertised processor)'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpu | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Format-List | Show

    Section 'RAM  (two sticks = dual channel; compare size and speed with the spec sheet)'
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $ram | Select-Object DeviceLocator, @{n='SizeGB';e={$_.Capacity/1GB}}, Speed, ConfiguredClockSpeed, Manufacturer, PartNumber |
        Format-Table -AutoSize | Show
    $totalGB = ($ram | Measure-Object Capacity -Sum).Sum / 1GB
    "Total installed: $totalGB GB in $($ram.Count) module(s)"
    if ($ram.Count -eq 1) { Flag 'INFO' "Only one RAM module ($totalGB GB) - single channel unless it is soldered + one stick" }

    Section 'GPU  (integrated + dedicated graphics, with real VRAM size)'
    $gpus = @(Get-CimInstance Win32_VideoController)
    # Win32_VideoController caps AdapterRAM at 4 GB, so read the real VRAM size from the driver's registry key
    $vram = @{}
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' |
        ForEach-Object {
            $p = Get-ItemProperty $_.PSPath
            $size = $p.'HardwareInformation.qwMemorySize'
            if ($p.DriverDesc -and $size) { $vram[$p.DriverDesc] = [math]::Round([double]$size / 1GB, 1) }
        }
    $gpus | ForEach-Object {
        $vendor = switch -Regex ($_.Name) { 'NVIDIA' { 'NVIDIA' } 'AMD|Radeon' { 'AMD' } 'Intel' { 'Intel' } default { 'Other' } }
        [pscustomobject]@{
            Name       = $_.Name
            Vendor     = $vendor
            VRAM_GB    = $vram[$_.Name]
            Driver     = $_.DriverVersion
            Status     = $_.Status
        }
    } | Format-Table -AutoSize | Show
    $gpus | Where-Object { $_.Status -ne 'OK' } | ForEach-Object { Flag 'FAIL' "GPU '$($_.Name)' status is $($_.Status)" }
    if ($gpus.Name -match 'Microsoft Basic Display') { Flag 'WARN' 'A GPU is using the Microsoft Basic Display driver - graphics driver missing' }
    if ($gpus.Name -match 'NVIDIA') {
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            'nvidia-smi:'
            nvidia-smi --query-gpu=name,vbios_version,memory.total,temperature.gpu,power.draw,power.max_limit --format=csv | Show
        } else { Flag 'WARN' 'NVIDIA GPU present but nvidia-smi not found - NVIDIA driver not fully installed' }
    }

    Section 'DISPLAY  (current mode, max refresh rate and panel manufacture date)'
    $gpus | Where-Object { $_.CurrentHorizontalResolution } |
        Select-Object Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate, MaxRefreshRate |
        Format-List | Show
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object {
        [pscustomobject]@{
            PanelMaker  = Chars $_.ManufacturerName
            PanelModel  = Chars $_.UserFriendlyName
            ProductCode = Chars $_.ProductCodeID
            PanelSerial = Chars $_.SerialNumberID
            MadeWeek    = $_.WeekOfManufacture
            MadeYear    = $_.YearOfManufacture
        }
    } | Format-List | Show
    'Tip: if the refresh rate is lower than advertised, check Settings > System > Display > Advanced display.'

    Section 'STORAGE  (HealthStatus Healthy, wear 0-2 %, errors 0)'
    $disks = @(Get-PhysicalDisk)
    $disks | Select-Object FriendlyName, BusType, MediaType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, HealthStatus, OperationalStatus |
        Format-Table -AutoSize | Show
    $disks | Where-Object { $_.HealthStatus -ne 'Healthy' } | ForEach-Object { Flag 'FAIL' "Disk '$($_.FriendlyName)' health is $($_.HealthStatus)" }
    $rel = @($disks | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue)
    if ($rel.Count -and ($rel | Where-Object { $null -ne $_.Wear -or $null -ne $_.PowerOnHours })) {
        $rel | Select-Object DeviceId, @{n='WearPercentUsed';e={$_.Wear}}, PowerOnHours, Temperature, ReadErrorsTotal, WriteErrorsTotal |
            Format-Table -AutoSize | Show
        foreach ($r in $rel) {
            if ($r.Wear -gt 5) { Flag 'WARN' "SSD wear is $($r.Wear) % (new is 0-2 %)" }
            if ($r.ReadErrorsTotal -gt 0 -or $r.WriteErrorsTotal -gt 0) { Flag 'FAIL' "SSD has read/write errors ($($r.ReadErrorsTotal)/$($r.WriteErrorsTotal))" }
        }
        'PowerOnHours is naturally high on a store demo unit - wear % and errors matter more.'
    } else {
        'SSD wear / power-on hours not exposed to Windows here (normal with Intel RST/VMD or without Admin).'
        'Use CrystalDiskInfo (portable) to read them.'
    }

    Section 'BATTERY  (health = full / design capacity; also check physically for swelling)'
    if (-not (Get-CimInstance Win32_Battery)) {
        'No battery detected (desktop PC, or battery disconnected).'
        Flag 'WARN' 'No battery detected'
    } else {
        # powercfg can fail writing straight to USB drives, so write to TEMP and copy over
        $tmpHtml = Join-Path $env:TEMP "battery-$stamp.html"
        powercfg /batteryreport /output "$tmpHtml" | Out-Null
        if (Test-Path $tmpHtml) { Copy-Item $tmpHtml $batteryHtml -Force }
        if (-not (Test-Path $batteryHtml)) { $batteryHtml = $tmpHtml }
        $html = if (Test-Path $batteryHtml) { Get-Content $batteryHtml -Raw } else { '' }
        function FromReport($label) {
            $m = [regex]::Match($html, "$label</span></td><td>([\d,\.]+)")
            if ($m.Success) { [int]($m.Groups[1].Value -replace '[,\.]', '') }
        }
        $design = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData | Select-Object -First 1).DesignedCapacity
        if (-not $design) { $design = FromReport 'DESIGN CAPACITY' }
        $full = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity | Select-Object -First 1).FullChargedCapacity
        if (-not $full) { $full = FromReport 'FULL CHARGE CAPACITY' }
        $cycles = (Get-CimInstance -Namespace root\wmi -ClassName BatteryCycleCount | Select-Object -First 1).CycleCount
        if (-not $cycles) { $cycles = FromReport 'CYCLE COUNT' }
        "Design capacity     : $design mWh"
        "Full charge capacity: $full mWh"
        "Cycle count         : $cycles   (blank/0 can mean 'not reported' by this brand)"
        if ($design -and $full) {
            $health = [math]::Round(100 * $full / $design, 1)
            "BATTERY HEALTH      : $health %"
            if ($health -lt 85) { Flag 'FAIL' "Battery health $health % (below 85 %)" }
            elseif ($health -lt 90) { Flag 'WARN' "Battery health $health % (85-90 %) - negotiate" }
        } else { Flag 'WARN' 'Could not read battery capacity - open the battery report' }
        Get-CimInstance Win32_Battery | Select-Object EstimatedChargeRemaining, BatteryStatus | Format-List | Show
        if (Test-Path $batteryHtml) { "Full battery report saved: $batteryHtml" }
        else { "Battery report not created - run 'powercfg /batteryreport' yourself and open battery-report.html" }
    }

    Section 'WINDOWS  (install date, user accounts, activation)'
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, InstallDate, LastBootUpTime | Format-List | Show
    'Local user accounts (extra personal accounts = someone has been using it):'
    Get-LocalUser | Select-Object Name, Enabled, LastLogon | Format-Table -AutoSize | Show
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"
    $lic | Select-Object Name, @{n='Activated';e={$_.LicenseStatus -eq 1}} | Format-List | Show
    if (-not ($lic | Where-Object { $_.LicenseStatus -eq 1 })) { Flag 'WARN' 'Windows is not activated' }

    Section 'HEALTH HISTORY  (should all be 0 or very low)'
    $count = { param($h) @(Get-WinEvent -FilterHashtable $h -ErrorAction SilentlyContinue).Count }
    $kp   = & $count @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41}
    $bsod = & $count @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001}
    $whea = & $count @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'}
    $derr = (& $count @{LogName='System'; ProviderName='disk'; Level=2}) + (& $count @{LogName='System'; ProviderName='stornvme'; Level=2})
    "Unexpected shutdowns (Kernel-Power 41): $kp"
    "Blue screens (BugCheck 1001)          : $bsod"
    "Hardware errors (WHEA-Logger)          : $whea"
    "Disk errors (disk / stornvme)          : $derr"
    if ($whea -gt 0) { Flag 'FAIL' "$whea WHEA hardware error(s) logged (CPU/RAM/PCIe)" }
    if ($bsod -gt 0) { Flag 'WARN' "$bsod blue screen(s) logged" }
    if ($derr -gt 0) { Flag 'WARN' "$derr disk error(s) logged" }
    if ($kp -gt 5)   { Flag 'WARN' "$kp unexpected shutdowns logged" }

    Section 'DEVICES WITH PROBLEMS  (should be empty)'
    $bad = @(Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
    $bad | Select-Object Class, FriendlyName, Status | Format-Table -AutoSize | Show
    if ($bad.Count) { Flag 'WARN' "$($bad.Count) device(s) with driver/hardware problems (see list)" }

    Section 'WIRELESS / CAMERA / AUDIO present'
    Get-PnpDevice -PresentOnly -Class Net, Bluetooth, Camera, Image, AudioEndpoint |
        Where-Object { $_.FriendlyName -match 'Wi-Fi|Wireless|WLAN|AX\d|Bluetooth|Camera|Webcam|Speaker|Microphone|Ethernet|Realtek|Killer' } |
        Select-Object Class, FriendlyName, Status | Format-Table -AutoSize | Show

    Section 'SUMMARY'
    if ($flags.Count -eq 0) { 'PASS - no problems detected by software. Now do the physical checks (swelling, screen, ports, keyboard).' }
    else { $flags | Sort-Object { @{FAIL=0; WARN=1; INFO=2}[$_.Level] } | Format-Table -AutoSize | Show }
    'Software cannot see: battery swelling, scratches, hinge, ports, speakers, fan noise, warranty date.'
} | Tee-Object -FilePath $report

"`nReport saved: $report"
if (-not $NoOpen -and (Test-Path $batteryHtml)) { Start-Process $batteryHtml }
