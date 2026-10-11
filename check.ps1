# laptop-genuineness: read-only health and genuineness check for any Windows 10/11 laptop.
#
# Run from an ADMIN PowerShell (Win + X -> Terminal (Admin)), either:
#   straight from GitHub:  irm https://raw.githubusercontent.com/Dev010904/laptop-genuineness/main/check.ps1 | iex
#   or from a USB stick:   powershell -ExecutionPolicy Bypass -File "E:\laptop-genuineness\check.ps1"
#
# It only READS information. Nothing on the laptop is changed.
# Output: detailed sections, then a SCORECARD with Result / Expected / Verdict for every check.
param([switch]$NoOpen)

$ErrorActionPreference = 'SilentlyContinue'
# When run from a URL there is no script folder, so save to the Desktop
$dir = if ($PSScriptRoot) { $PSScriptRoot } else { Join-Path ([Environment]::GetFolderPath('Desktop')) 'laptop-test-report' }
New-Item -ItemType Directory -Force $dir | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$report = Join-Path $dir "report-$stamp.txt"
$batteryHtml = Join-Path $dir "battery-$stamp.html"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Known models: when the laptop matches, results are compared against these exact specs.
# Add more entries to support more models.
$profiles = @(
    @{
        Name      = 'MSI Crosshair 16 HX AI (D2XWFKG-067IN)'
        Match     = 'Crosshair 16 HX'
        Cpu       = 'Ultra 9 275HX'; CpuText = 'Intel Core Ultra 9 275HX'; Threads = 24
        RamGB     = 16; RamModules = 2; RamSpeed = 5600
        Gpu       = 'RTX 5060'; GpuText = 'NVIDIA GeForce RTX 5060 Laptop GPU'; VramGB = 8
        Width     = 2560; Height = 1600; Hz = 240
        SsdMinGB  = 900; SsdMaxGB = 1000; SsdText = '1 TB (Windows shows ~931-954 GB)'
        BatteryWh = 90
    }
)

# Common blue-screen codes: meaning and how serious they are
$bugchecks = @{
    '0x0000009f' = @('DRIVER_POWER_STATE_FAILURE (driver failed on sleep/wake)', 'WARN')
    '0x00000133' = @('DPC_WATCHDOG_VIOLATION (driver/storage firmware hang)', 'WARN')
    '0x00000124' = @('WHEA_UNCORRECTABLE_ERROR (HARDWARE error: CPU/RAM/board)', 'FAIL')
    '0x0000007a' = @('KERNEL_DATA_INPAGE_ERROR (disk/SSD read failure)', 'FAIL')
    '0x0000007b' = @('INACCESSIBLE_BOOT_DEVICE (disk/storage driver)', 'WARN')
    '0x0000001a' = @('MEMORY_MANAGEMENT (possible faulty RAM)', 'FAIL')
    '0x00000050' = @('PAGE_FAULT_IN_NONPAGED_AREA (RAM or driver)', 'WARN')
    '0x000000d1' = @('DRIVER_IRQL_NOT_LESS_OR_EQUAL (driver)', 'WARN')
    '0x0000000a' = @('IRQL_NOT_LESS_OR_EQUAL (driver)', 'WARN')
    '0x0000003b' = @('SYSTEM_SERVICE_EXCEPTION (driver/software)', 'WARN')
    '0x0000007e' = @('SYSTEM_THREAD_EXCEPTION_NOT_HANDLED (driver)', 'WARN')
    '0x000000ef' = @('CRITICAL_PROCESS_DIED (software/disk)', 'WARN')
    '0x00000116' = @('VIDEO_TDR_FAILURE (graphics driver/GPU)', 'WARN')
    '0x00000117' = @('VIDEO_TDR_TIMEOUT_DETECTED (graphics driver/GPU)', 'WARN')
}

$rows = New-Object System.Collections.Generic.List[object]
function Row($verdict, $check, $result, $expected) {
    $rows.Add([pscustomobject]@{ Index = $rows.Count; Verdict = $verdict; Check = $check; Result = "$result"; Expected = "$expected" })
}
function Section($title) { "`n==================== $title ====================" }
function Chars($arr) { -join ($arr | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) }
function Show { $input | Out-String -Stream | Where-Object { $_.Trim() } }

# Native display modes (exact max refresh rate), via EnumDisplaySettings
if (-not ('LGDisplay' -as [type])) {
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class LGDisplay {
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Ansi)]
    public struct DEVMODE {
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmDeviceName;
        public short dmSpecVersion; public short dmDriverVersion; public short dmSize; public short dmDriverExtra;
        public int dmFields; public int dmPositionX; public int dmPositionY; public int dmDisplayOrientation; public int dmDisplayFixedOutput;
        public short dmColor; public short dmDuplex; public short dmYResolution; public short dmTTOption; public short dmCollate;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)] public string dmFormName;
        public short dmLogPixels; public int dmBitsPerPel; public int dmPelsWidth; public int dmPelsHeight;
        public int dmDisplayFlags; public int dmDisplayFrequency; public int dmICMMethod; public int dmICMIntent;
        public int dmMediaType; public int dmDitherType; public int dmReserved1; public int dmReserved2;
        public int dmPanningWidth; public int dmPanningHeight;
    }
    [DllImport("user32.dll", CharSet = CharSet.Ansi)]
    static extern bool EnumDisplaySettings(string device, int mode, ref DEVMODE dm);
    public static int[] Mode(int i) {
        DEVMODE dm = new DEVMODE(); dm.dmSize = (short)Marshal.SizeOf(typeof(DEVMODE));
        if (!EnumDisplaySettings(null, i, ref dm)) return null;
        return new int[] { dm.dmPelsWidth, dm.dmPelsHeight, dm.dmDisplayFrequency };
    }
}
'@ -ErrorAction SilentlyContinue
}

& {
    "Laptop inspection - $(Get-Date)"
    if ($isAdmin) { Row 'OK' 'Run as Administrator' 'Yes' 'Yes (needed for SSD wear/hours)' }
    else {
        "!! NOT running as Administrator - SSD wear/hours and some battery data will be missing !!"
        Row 'WARN' 'Run as Administrator' 'No' 'Yes - re-run from Terminal (Admin)'
    }

    # ---------------------------------------------------------------- model
    Section 'MODEL / SERIAL'
    $cs = Get-CimInstance Win32_ComputerSystem
    $bios = Get-CimInstance Win32_BIOS
    $board = Get-CimInstance Win32_BaseBoard
    $cs | Select-Object Manufacturer, Model, SystemSKUNumber | Format-List | Show
    $bios | Select-Object SerialNumber, SMBIOSBIOSVersion, ReleaseDate | Format-List | Show
    $board | Select-Object Product, SerialNumber | Format-List | Show

    $id = "$($cs.Manufacturer) $($cs.Model) $($cs.SystemSKUNumber) $($board.Product)"
    $p = $profiles | Where-Object { $id -match $_.Match } | Select-Object -First 1
    if ($p) { "Matched known model profile: $($p.Name) - results compared against its exact specs." }
    else { 'No built-in profile for this model - compare CHECK rows with the official spec sheet.' }

    Row $(if ($p) { 'OK' } else { 'CHECK' }) 'Model' "$($cs.Manufacturer) $($cs.Model)" $(if ($p) { "$($p.Name) - also match the code on box + bill" } else { 'Exact model code on the box and the bill' })
    if (-not $bios.SerialNumber -or $bios.SerialNumber -match 'To be filled|Default|^0+$|O\.E\.M|System Serial') {
        Row 'FAIL' 'Serial number' "'$($bios.SerialNumber)'" 'A real serial (generic/missing = board replaced)'
    } else {
        Row 'CHECK' 'Serial number' $bios.SerialNumber 'Same as sticker under laptop, box and bill'
    }

    # ---------------------------------------------------------------- cpu
    Section 'CPU'
    $cpu = Get-CimInstance Win32_Processor | Select-Object -First 1
    $cpu | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed | Format-List | Show
    $cpuRes = "$($cpu.Name.Trim()) ($($cpu.NumberOfCores) cores / $($cpu.NumberOfLogicalProcessors) threads)"
    if ($p) {
        $ok = ($cpu.Name -match [regex]::Escape($p.Cpu)) -and ($cpu.NumberOfLogicalProcessors -eq $p.Threads)
        Row $(if ($ok) { 'OK' } else { 'FAIL' }) 'CPU' $cpuRes "$($p.CpuText), $($p.Threads) threads"
    } else { Row 'CHECK' 'CPU' $cpuRes 'Processor on the spec sheet' }

    # ---------------------------------------------------------------- ram
    Section 'RAM'
    $ram = @(Get-CimInstance Win32_PhysicalMemory)
    $ram | Select-Object DeviceLocator, @{n='SizeGB';e={$_.Capacity/1GB}}, Speed, ConfiguredClockSpeed, Manufacturer, PartNumber |
        Format-Table -AutoSize | Show
    $totalGB = ($ram | Measure-Object Capacity -Sum).Sum / 1GB
    $rated = ($ram | Measure-Object Speed -Minimum).Minimum
    $running = ($ram | Measure-Object ConfiguredClockSpeed -Minimum).Minimum
    $layout = ($ram | ForEach-Object { "$($_.Capacity/1GB)" }) -join ' + '
    $ramRes = "$totalGB GB ($layout GB) @ $running MT/s"
    if ($p) {
        $ok = ($totalGB -eq $p.RamGB) -and ($ram.Count -eq $p.RamModules) -and ($running -ge $p.RamSpeed)
        Row $(if ($ok) { 'OK' } else { 'FAIL' }) 'RAM' $ramRes "$($p.RamGB) GB ($($p.RamModules) x $($p.RamGB / $p.RamModules) GB) @ $($p.RamSpeed) MT/s"
    } else { Row 'CHECK' 'RAM' $ramRes 'Size and speed on the spec sheet' }
    Row $(if ($ram.Count -ge 2) { 'OK' } else { 'WARN' }) 'RAM channels' $(if ($ram.Count -ge 2) { "Dual channel ($($ram.Count) modules)" } else { 'Single channel (1 module)' }) 'Dual channel (2 modules) for full speed'
    if ($running -and $rated -and $running -lt $rated) {
        Row 'WARN' 'RAM speed' "Running $running, rated $rated MT/s" 'Running speed = rated speed'
    }

    # ---------------------------------------------------------------- gpu
    Section 'GPU'
    $gpus = @(Get-CimInstance Win32_VideoController)
    # Win32_VideoController caps AdapterRAM at 4 GB, so read the real VRAM size from the driver's registry key
    $vram = @{}
    Get-ChildItem 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}' |
        ForEach-Object {
            $k = Get-ItemProperty $_.PSPath
            $size = $k.'HardwareInformation.qwMemorySize'
            if ($k.DriverDesc -and $size) { $vram[$k.DriverDesc] = [math]::Round([double]$size / 1GB, 1) }
        }
    $gpus | Select-Object Name, @{n='VRAM_GB';e={$vram[$_.Name]}}, DriverVersion, Status | Format-Table -AutoSize | Show
    $dedicated = @($gpus | Where-Object { $_.Name -match 'NVIDIA|Radeon RX|Radeon Pro|Arc A' })
    if ($p) {
        $g = $dedicated | Where-Object { $_.Name -match [regex]::Escape($p.Gpu) } | Select-Object -First 1
        $gRes = if ($dedicated) { ($dedicated | ForEach-Object { "$($_.Name) ($($vram[$_.Name]) GB)" }) -join ', ' } else { 'No dedicated GPU found' }
        $ok = $g -and (-not $vram[$g.Name] -or $vram[$g.Name] -ge $p.VramGB - 0.5)
        Row $(if ($ok) { 'OK' } else { 'FAIL' }) 'Dedicated GPU' $gRes "$($p.GpuText), $($p.VramGB) GB"
    } elseif ($dedicated) {
        Row 'CHECK' 'Dedicated GPU' (($dedicated | ForEach-Object { "$($_.Name) ($($vram[$_.Name]) GB)" }) -join ', ') 'GPU and VRAM on the spec sheet'
    } else {
        Row 'INFO' 'Dedicated GPU' 'None (integrated graphics only)' 'Matches spec sheet (fine if it has no dedicated GPU)'
    }
    $badGpu = @($gpus | Where-Object { $_.Status -ne 'OK' -or $_.Name -match 'Microsoft Basic Display' })
    Row $(if ($badGpu) { 'FAIL' } else { 'OK' }) 'Graphics drivers' $(if ($badGpu) { ($badGpu.Name -join ', ') + ' not working' } else { 'All GPUs status OK' }) 'All OK, no "Microsoft Basic Display"'
    if ($gpus.Name -match 'NVIDIA') {
        if (Get-Command nvidia-smi -ErrorAction SilentlyContinue) {
            'nvidia-smi:'
            nvidia-smi --query-gpu=name,vbios_version,driver_version,memory.total,temperature.gpu,power.draw,power.max_limit --format=csv | Show
            Row 'OK' 'NVIDIA driver' 'Installed (nvidia-smi works)' 'Installed'
        } else { Row 'WARN' 'NVIDIA driver' 'nvidia-smi missing' 'Installed' }
    }

    # ---------------------------------------------------------------- display
    Section 'DISPLAY'
    $modes = @()
    for ($i = 0; $i -lt 2000; $i++) { $m = [LGDisplay]::Mode($i); if (-not $m) { break }; $modes += ,$m }
    $cur = [LGDisplay]::Mode(-1)
    if ($modes.Count) {
        $native = $modes | Sort-Object { $_[0] * $_[1] } -Descending | Select-Object -First 1
        $maxHz = ($modes | Where-Object { $_[0] -eq $native[0] -and $_[1] -eq $native[1] } | ForEach-Object { $_[2] } | Measure-Object -Maximum).Maximum
        "Native resolution : $($native[0]) x $($native[1])"
        "Max refresh rate  : $maxHz Hz (at native resolution)"
        if ($cur) { "Current mode      : $($cur[0]) x $($cur[1]) @ $($cur[2]) Hz" }
        if ($p) {
            $ok = ($native[0] -eq $p.Width -and $native[1] -eq $p.Height)
            Row $(if ($ok) { 'OK' } else { 'FAIL' }) 'Screen resolution' "$($native[0]) x $($native[1])" "$($p.Width) x $($p.Height)"
            Row $(if ($maxHz -ge $p.Hz - 1) { 'OK' } else { 'FAIL' }) 'Max refresh rate' "$maxHz Hz" "$($p.Hz) Hz"
        } else {
            Row 'CHECK' 'Screen resolution' "$($native[0]) x $($native[1])" 'Resolution on the spec sheet'
            Row 'CHECK' 'Max refresh rate' "$maxHz Hz" 'Refresh rate on the spec sheet (60/120/144/165/240...)'
        }
        if ($cur -and $cur[2] -lt $maxHz - 1) {
            Row 'INFO' 'Current refresh rate' "$($cur[2]) Hz" "$maxHz Hz - set it in Settings > Display > Advanced display (or plug in charger)"
        }
    }
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object {
        [pscustomobject]@{
            PanelMaker  = Chars $_.ManufacturerName
            ProductCode = Chars $_.ProductCodeID
            MadeWeek    = $_.WeekOfManufacture
            MadeYear    = $_.YearOfManufacture
        }
    } | Format-Table -AutoSize | Show
    $panel = Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | Select-Object -First 1
    if ($panel) { Row 'INFO' 'Panel made' "Week $($panel.WeekOfManufacture) of $($panel.YearOfManufacture) ($(Chars $panel.ManufacturerName))" 'Tells you how old the stock is' }

    # ---------------------------------------------------------------- storage
    Section 'STORAGE'
    $internal = @(Get-PhysicalDisk | Where-Object { $_.BusType -notmatch 'USB|SD|MMC|File Backed' })
    Get-PhysicalDisk | Select-Object DeviceId, FriendlyName, BusType, MediaType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, HealthStatus |
        Format-Table -AutoSize | Show
    foreach ($d in $internal) {
        $gb = [math]::Round($d.Size / 1GB)
        $name = "Disk $($d.DeviceId) $($d.FriendlyName)"
        if ($p -and $internal.Count -eq 1) {
            $ok = $gb -ge $p.SsdMinGB -and $gb -le $p.SsdMaxGB
            Row $(if ($ok) { 'OK' } else { 'FAIL' }) 'SSD size' "$gb GB ($($d.FriendlyName))" $p.SsdText
        } else { Row 'CHECK' 'SSD size' "$gb GB ($($d.FriendlyName))" 'Storage on the spec sheet (1 TB shows ~931-954 GB)' }
        Row $(if ($d.HealthStatus -eq 'Healthy') { 'OK' } else { 'FAIL' }) 'SSD health' "$($d.HealthStatus) ($name)" 'Healthy'

        $r = $d | Get-StorageReliabilityCounter -ErrorAction SilentlyContinue
        $r | Select-Object @{n='Disk';e={$d.DeviceId}}, Wear, PowerOnHours, Temperature, ReadErrorsTotal, WriteErrorsTotal | Format-Table -AutoSize | Show
        $na = 'Not reported by this drive (use CrystalDiskInfo)'
        if ($null -ne $r.Wear) {
            Row $(if ($r.Wear -le 2) { 'OK' } elseif ($r.Wear -le 10) { 'WARN' } else { 'FAIL' }) 'SSD wear (life used)' "$($r.Wear) %" '0-2 % (new/demo). Over 10 % = heavily used'
        } else { Row 'INFO' 'SSD wear (life used)' $(if ($isAdmin) { $na } else { 'Needs Administrator' }) '0-2 %' }
        if ($null -ne $r.PowerOnHours) {
            Row 'INFO' 'SSD power-on hours' "$($r.PowerOnHours) h (~$([math]::Round($r.PowerOnHours / 24)) days)" 'New: under ~50 h. Demo unit: high is normal'
        } else { Row 'INFO' 'SSD power-on hours' $(if ($isAdmin) { $na } else { 'Needs Administrator' }) 'New: under ~50 h. Demo unit: high is normal' }
        if ($r.Temperature) {
            Row $(if ($r.Temperature -lt 70) { 'OK' } elseif ($r.Temperature -lt 80) { 'WARN' } else { 'FAIL' }) 'SSD temperature' "$($r.Temperature) C" 'Under 70 C at idle'
        }
        $errs = [int]$r.ReadErrorsTotal + [int]$r.WriteErrorsTotal
        if ($null -ne $r.ReadErrorsTotal -or $null -ne $r.WriteErrorsTotal) {
            Row $(if ($errs -eq 0) { 'OK' } else { 'FAIL' }) 'SSD read/write errors' $errs '0'
        }
    }

    # ---------------------------------------------------------------- battery
    Section 'BATTERY'
    if (-not (Get-CimInstance Win32_Battery)) {
        'No battery detected (desktop PC, or battery disconnected).'
        Row 'FAIL' 'Battery' 'Not detected' 'Battery present'
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
        $bat = Get-CimInstance Win32_Battery | Select-Object -First 1
        "Design capacity     : $design mWh"
        "Full charge capacity: $full mWh"
        "Cycle count         : $cycles"
        "Charge now          : $($bat.EstimatedChargeRemaining) %  (BatteryStatus 2 = on charger)"

        if ($design -and $full) {
            $health = [math]::Round(100 * $full / $design, 1)
            "BATTERY HEALTH      : $health %"
            Row $(if ($health -ge 90) { 'OK' } elseif ($health -ge 85) { 'WARN' } else { 'FAIL' }) 'Battery health' "$health % ($full of $design mWh)" '90 %+ OK | 85-90 % negotiate | under 85 % reject'
        } else { Row 'WARN' 'Battery health' 'Could not read' 'Open the battery report HTML' }
        if ($p -and $design) {
            $wh = [math]::Round($design / 1000, 1)
            $ok = [math]::Abs($wh - $p.BatteryWh) -le $p.BatteryWh * 0.05
            Row $(if ($ok) { 'OK' } else { 'WARN' }) 'Battery design capacity' "$wh Wh" "$($p.BatteryWh) Wh (different = non-original battery?)"
        }
        if ($cycles) {
            Row $(if ($cycles -le 50) { 'OK' } elseif ($cycles -le 300) { 'WARN' } else { 'FAIL' }) 'Battery cycles' $cycles 'New/demo: under 50 | 50-300 used | 300+ worn'
        } else { Row 'INFO' 'Battery cycles' 'Not reported' 'Check CYCLE COUNT in the battery report' }
        Row 'INFO' 'Charger connected' $(if ($bat.BatteryStatus -eq 2) { 'Yes' } else { 'No' }) 'Test charging with the included adapter'
        if (Test-Path $batteryHtml) { "Full battery report saved: $batteryHtml" }
    }

    # ---------------------------------------------------------------- windows
    Section 'WINDOWS'
    $os = Get-CimInstance Win32_OperatingSystem
    $os | Select-Object Caption, Version, InstallDate, LastBootUpTime | Format-List | Show
    $lic = Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'"
    $activated = [bool]($lic | Where-Object { $_.LicenseStatus -eq 1 })
    Row $(if ($activated) { 'OK' } else { 'WARN' }) 'Windows activated' $(if ($activated) { 'Yes' } else { 'No' }) 'Yes (genuine licence)'
    $age = [math]::Round(((Get-Date) - $os.InstallDate).TotalDays)
    Row 'INFO' 'Windows installed' "$($os.InstallDate.ToString('dd MMM yyyy')) ($age days ago)" 'Recent = fresh/reset. Very old = long time in use'
    $builtin = 'Administrator|Guest|DefaultAccount|WDAGUtilityAccount|defaultuser\d*'
    $users = @(Get-LocalUser | Where-Object { $_.Enabled -and $_.Name -notmatch "^($builtin)$" })
    'Enabled user accounts:'
    $users | Select-Object Name, LastLogon | Format-Table -AutoSize | Show
    Row $(if ($users.Count -le 1) { 'OK' } else { 'CHECK' }) 'User accounts' "$($users.Count): $($users.Name -join ', ')" '1 (store/demo account). More = someone used it'

    # ---------------------------------------------------------------- history
    Section 'HEALTH HISTORY'
    $whea = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -ErrorAction SilentlyContinue)
    "Hardware errors (WHEA): $($whea.Count)"
    $whea | Select-Object -First 5 TimeCreated, Id | Format-Table -AutoSize | Show
    Row $(if ($whea.Count -eq 0) { 'OK' } else { 'FAIL' }) 'Hardware errors (WHEA)' $whea.Count '0 (any = CPU/RAM/board problem)'

    $bsods = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001} -ErrorAction SilentlyContinue)
    "Blue screens: $($bsods.Count)"
    $worst = 'OK'; $codes = @()
    foreach ($e in $bsods) {
        $code = ([regex]::Match($e.Message, '0x[0-9a-fA-F]{8}')).Value.ToLower()
        $info = $bugchecks[$code]
        $desc = if ($info) { $info[0] } else { 'unknown code - search it online' }
        $lvl = if ($info) { $info[1] } else { 'WARN' }
        if ($lvl -eq 'FAIL') { $worst = 'FAIL' } elseif ($worst -ne 'FAIL') { $worst = 'WARN' }
        "  $($e.TimeCreated.ToString('dd MMM yyyy HH:mm'))  $code  $desc"
        $codes += "$code"
    }
    $bsodRes = if ($bsods.Count) { "$($bsods.Count): " + (($codes | Group-Object | ForEach-Object { "$($_.Name) x$($_.Count) $(@($bugchecks[$_.Name])[0])" }) -join '; ') } else { '0' }
    Row $worst 'Blue screens' $bsodRes '0. Driver codes = fixable; hardware codes = reject'

    $kp = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41} -ErrorAction SilentlyContinue).Count
    Row $(if ($kp -le 5) { 'OK' } else { 'WARN' }) 'Unexpected shutdowns' $kp '0-5 (store units get unplugged)'

    # Disk errors: separate the internal drive(s) from USB sticks / external drives
    $internalNums = @(Get-Disk | Where-Object { $_.BusType -notmatch 'USB|SD|MMC|File Backed' } | ForEach-Object { $_.Number })
    $derr = @(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='disk','stornvme'; Level=2} -ErrorAction SilentlyContinue)
    $intErr = 0; $extErr = 0
    foreach ($e in $derr) {
        $n = [regex]::Match($e.Message, 'Harddisk(\d+)')
        if ($n.Success -and ($internalNums -notcontains [int]$n.Groups[1].Value)) { $extErr++ } else { $intErr++ }
        "  $($e.TimeCreated.ToString('dd MMM yyyy HH:mm'))  $($e.ProviderName) $($e.Id)  $(($e.Message -split "`n")[0])"
    }
    Row $(if ($intErr -eq 0) { 'OK' } else { 'FAIL' }) 'Internal disk errors' $intErr '0'
    if ($extErr) { Row 'INFO' 'USB/external disk errors' $extErr 'Ignored - from USB drives, not the laptop SSD' }

    # ---------------------------------------------------------------- devices
    Section 'DEVICES'
    $bad = @(Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' })
    $bad | Select-Object Class, FriendlyName, Status | Format-Table -AutoSize | Show
    Row $(if ($bad.Count -eq 0) { 'OK' } else { 'WARN' }) 'Devices with problems' $(if ($bad.Count) { "$($bad.Count): " + ($bad.FriendlyName -join ', ') } else { 'None' }) 'None'

    $pnp = @(Get-PnpDevice -PresentOnly -Status OK)
    $wifi = $pnp | Where-Object { $_.Class -eq 'Net' -and $_.FriendlyName -match 'Wi-?Fi|Wireless|WLAN|802\.11' -and $_.FriendlyName -notmatch 'Virtual|Direct' } | Select-Object -First 1
    # The Bluetooth class also lists paired devices (earbuds, phones), so pick the adapter itself
    $bt   = $pnp | Where-Object { $_.Class -eq 'Bluetooth' -and $_.FriendlyName -match 'Bluetooth' -and $_.FriendlyName -notmatch 'Enumerator|Generic|RFCOMM|LE |Device \(' } | Select-Object -First 1
    $cam  = $pnp | Where-Object { $_.Class -in 'Camera','Image' } | Select-Object -First 1
    $spk  = $pnp | Where-Object { $_.Class -eq 'AudioEndpoint' -and $_.FriendlyName -match 'Speaker' -and $_.FriendlyName -notmatch 'Steam|Virtual' } | Select-Object -First 1
    $mic  = $pnp | Where-Object { $_.Class -eq 'AudioEndpoint' -and $_.FriendlyName -match 'Microphone' -and $_.FriendlyName -notmatch 'Steam|Virtual' } | Select-Object -First 1
    foreach ($dev in @(@('Wi-Fi', $wifi), @('Bluetooth', $bt), @('Webcam', $cam), @('Speakers', $spk), @('Microphone', $mic))) {
        Row $(if ($dev[1]) { 'OK' } else { 'FAIL' }) $dev[0] $(if ($dev[1]) { $dev[1].FriendlyName } else { 'Not found' }) 'Present and working'
    }
} | Tee-Object -Variable details

# ---------------------------------------------------------------- scorecard
$colors = @{ OK = 'Green'; WARN = 'Yellow'; FAIL = 'Red'; CHECK = 'Cyan'; INFO = 'Gray' }
$order = @{ FAIL = 0; WARN = 1; CHECK = 2; OK = 3; INFO = 4 }
$lines = New-Object System.Collections.Generic.List[string]
function Out-Line($text, $color) { Write-Host $text -ForegroundColor $color; $lines.Add($text) }

Out-Line '' 'White'
Out-Line ('=' * 78) 'White'
Out-Line ' SCORECARD   (Result vs Expected for every check)' 'White'
Out-Line '   OK = matches   WARN = negotiate/check   FAIL = reject   CHECK = compare yourself' 'White'
Out-Line ('=' * 78) 'White'
foreach ($r in ($rows | Sort-Object { $order[$_.Verdict] }, Index)) {
    Out-Line ('[{0,-5}] {1}' -f $r.Verdict, $r.Check) $colors[$r.Verdict]
    Out-Line ('         Result  : {0}' -f $r.Result) 'White'
    Out-Line ('         Expected: {0}' -f $r.Expected) 'DarkGray'
}
$n = @{}; foreach ($v in 'OK','WARN','FAIL','CHECK','INFO') { $n[$v] = @($rows | Where-Object { $_.Verdict -eq $v }).Count }
Out-Line ('-' * 78) 'White'
Out-Line ("TOTAL:  {0} OK   {1} WARN   {2} FAIL   {3} CHECK   {4} INFO" -f $n.OK, $n.WARN, $n.FAIL, $n.CHECK, $n.INFO) 'White'
if ($n.FAIL) { Out-Line 'VERDICT: DO NOT BUY until every FAIL is explained or fixed.' 'Red' }
elseif ($n.WARN) { Out-Line 'VERDICT: Acceptable after checking the WARN items - use them to negotiate the price.' 'Yellow' }
else { Out-Line 'VERDICT: All software checks passed.' 'Green' }
if ($n.CHECK) { Out-Line 'Compare every CHECK row with the box, the bill and the official spec sheet.' 'Cyan' }
Out-Line 'Still do by hand: battery swelling, screen test, keyboard, ports, hinge, scratches, fans, warranty on your phone.' 'White'

$all = @($details | ForEach-Object { "$_" }) + $lines
[IO.File]::WriteAllLines($report, [string[]]$all, (New-Object Text.UTF8Encoding $true))
Write-Host "`nReport saved: $report"
if (-not $NoOpen -and (Test-Path $batteryHtml)) { Start-Process $batteryHtml }
