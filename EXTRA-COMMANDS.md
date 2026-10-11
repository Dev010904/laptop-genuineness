# Extra Commands: manual checks, stress test, GPU monitor (laptop-genuineness)

Use these if:
- you can't run `check.ps1` (no internet, no USB allowed), so you type commands yourself, or
- you want to re-check one thing on its own, or
- you want to run the stress test.

Run everything in **PowerShell as Administrator** (Win + X → **Terminal (Admin)**).
Every command here only reads information, except the stress test, which just loads the CPU for 5 minutes and then stops.

> Tip: in PowerShell, **right-click pastes**. Press **Ctrl + C** to stop any running command.

---

## 1. Stress test (fans, stability, temperatures)

Run this in **two** PowerShell windows at the same time.

### Window 1: load every CPU thread for 5 minutes

```powershell
$j = 1..$env:NUMBER_OF_PROCESSORS | % { Start-Job { while ($true) {} } }; Start-Sleep 300; $j | Stop-Job; $j | Remove-Job
```

| Part | Meaning |
|---|---|
| `1..$env:NUMBER_OF_PROCESSORS \| % { Start-Job {...} }` | Starts one background job per CPU thread (this laptop's real thread count) |
| `while ($true) {}` | An endless empty loop that keeps that core at 100 % |
| `Start-Sleep 300` | Waits 300 seconds (5 minutes). Change it to `600` for 10 minutes |
| `$j \| Stop-Job; $j \| Remove-Job` | Stops and cleans up all the jobs, so the CPU goes back to normal |

**If you need to stop early:** press **Ctrl + C**, then run:

```powershell
Get-Job | Stop-Job; Get-Job | Remove-Job
```

Open **Task Manager → Performance → CPU** while it runs. Usage should show close to **100 %**.

### Window 2: watch the GPU live (NVIDIA laptops only)

```powershell
nvidia-smi -l 2
```

- Refreshes every **2 seconds**. Press **Ctrl + C** to stop.
- Check that the GPU name matches the spec sheet, then watch the temperature and power numbers.
- On AMD or Intel-only laptops, use **Task Manager → Performance → GPU** instead.

For a short one-line view instead:

```powershell
nvidia-smi --query-gpu=name,temperature.gpu,power.draw,utilization.gpu,clocks.gr --format=csv -l 2
```

To load the GPU too, play a game or a 3D demo the store has installed, or open a WebGL demo in the browser while the CPU test runs.

### What to look and listen for

| Pass | Fail |
|---|---|
| Fans spin up loud but smooth | Rattling, clicking, grinding or whining fans |
| No freeze, crash or shutdown | Freezes, blue screen, or sudden power-off |
| Keyboard deck gets warm, but you can still touch it | Bottom gets too hot to touch within a minute or two |
| GPU temperature settles (often 70–85 °C under gaming load) | GPU reaches about 90 °C+ quickly and keeps climbing |

Tip: switch the brand's control app to its highest performance mode first (MSI Center, Armoury Crate, Lenovo Vantage, OMEN Gaming Hub…), so you hear the fans at their worst.

---

## 2. Battery

### Full battery report (HTML)

```powershell
powercfg /batteryreport /output "$env:USERPROFILE\Desktop\battery-report.html"; Start-Process "$env:USERPROFILE\Desktop\battery-report.html"
```

Saves the report to the Desktop and opens it. Compare **DESIGN CAPACITY** with **FULL CHARGE CAPACITY**, and note the **CYCLE COUNT**. Delete the file when you're done.

### Quick health % in the terminal

```powershell
$d = (Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData).DesignedCapacity; $f = (Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity).FullChargedCapacity; "Design $d  Full $f  Health {0:N1} %" -f (100*$f/$d)
```

Needs **Admin**. Look for **90 % or more**.

### Unplugged drain check

Unplug the charger and run this. It shows the charge level every 10 seconds, and Ctrl + C stops it:

```powershell
while ($true) { (Get-CimInstance Win32_Battery).EstimatedChargeRemaining; Start-Sleep 10 }
```

The number should drop slowly. A big sudden drop, or a shutdown, means a bad battery.

---

## 3. SSD

```powershell
Get-PhysicalDisk | Select FriendlyName, BusType, MediaType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, HealthStatus
```

Shows the drive name, type and size (about 954 GB is normal for "1 TB"), and **HealthStatus** should say `Healthy`.

```powershell
Get-PhysicalDisk | Get-StorageReliabilityCounter | Select Wear, PowerOnHours, Temperature, ReadErrorsTotal, WriteErrorsTotal
```

Needs **Admin**.

- **Wear** = % of the SSD's life already used. Want **0–2**.
- **PowerOnHours** will be high on a display unit. That's normal.
- **Errors** should be **0**.

For "total host writes" and the PCIe link speed, or if these come back blank, use **CrystalDiskInfo** (portable version, from the official site) on your USB.

---

## 4. Model, serial, specs

```powershell
Get-CimInstance Win32_ComputerSystem | Select Manufacturer, Model
```
Model should match the exact model code you're paying for (e.g. **Crosshair 16 HX AI D2XWFKG…**).

```powershell
Get-CimInstance Win32_BIOS | Select SerialNumber, SMBIOSBIOSVersion
```
The **SerialNumber** must match the sticker under the laptop, the box and the bill.

```powershell
Get-CimInstance Win32_Processor | Select Name, NumberOfCores, NumberOfLogicalProcessors
```
Should match the advertised processor and core count (e.g. Intel Core Ultra 9 275HX, 24 cores).

```powershell
Get-CimInstance Win32_PhysicalMemory | Select DeviceLocator, @{n='GB';e={$_.Capacity/1GB}}, Speed, Manufacturer, PartNumber
```
Total size and speed should match the spec sheet. Two rows = dual channel.

```powershell
Get-CimInstance Win32_VideoController | Select Name, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate
```
Should list the advertised dedicated GPU (if any) plus integrated graphics. Resolution and refresh rate should match the advertised display.

```powershell
nvidia-smi
```
NVIDIA laptops only. Shows the GPU name, driver version and VRAM (e.g. an 8 GB card shows about 8151 MiB).

---

## 5. Display panel info

```powershell
Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | % { [pscustomobject]@{ Maker = -join ($_.ManufacturerName | ? {$_} | % {[char]$_}); Code = -join ($_.ProductCodeID | ? {$_} | % {[char]$_}); Week = $_.WeekOfManufacture; Year = $_.YearOfManufacture } }
```

- **Maker** is a 3-letter code for the panel manufacturer (for example BOE, AUO, CMN, SDC).
- **Week / Year** is when the panel was made. That tells you how old the stock is.

---

## 6. Windows: install date, accounts, activation

```powershell
Get-CimInstance Win32_OperatingSystem | Select InstallDate, LastBootUpTime
```
**InstallDate** is when Windows was set up on this machine.

```powershell
Get-LocalUser | Select Name, Enabled, LastLogon
```
Lists the user accounts. Extra personal accounts mean someone has been using it.

```powershell
Get-CimInstance SoftwareLicensingProduct -Filter "PartialProductKey IS NOT NULL AND Name LIKE 'Windows%'" | Select Name, LicenseStatus
```
**LicenseStatus 1** = activated.

---

## 7. Crash and hardware-error history

```powershell
(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} -ErrorAction SilentlyContinue).Count
```
**WHEA hardware errors** (CPU, RAM, PCIe). Should be **0**. Anything above 0 is a red flag.

```powershell
(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41} -ErrorAction SilentlyContinue).Count
```
**Unexpected shutdowns** (power cuts, crashes, hard resets). A few is okay on a store unit; many is not.

```powershell
(Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; Id=1001} -ErrorAction SilentlyContinue).Count
```
**Blue screens.** Should be 0.

To see the actual WHEA errors (date and message), if the count is above 0:

```powershell
Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WHEA-Logger'} | Select TimeCreated, Message -First 10 | Format-List
```

---

## 8. Faulty or missing devices

```powershell
Get-PnpDevice -PresentOnly | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' } | Select Class, FriendlyName, Status
```
Should print **nothing**. Anything listed is a device with a driver or hardware problem.

```powershell
Get-PnpDevice -PresentOnly -Class Net, Bluetooth, Camera | Select Class, FriendlyName, Status
```
Wi-Fi, Bluetooth and the camera should all show **OK**.

---

## 9. Find your USB drive letter

```powershell
Get-Volume | Where-Object DriveType -eq Removable
```

---

## 10. Built-in Windows tools (no commands)

| Tool | How to open | What to check |
|---|---|---|
| Task Manager | Ctrl + Shift + Esc → Performance | CPU, RAM (size, speed, slots used), GPU, disk |
| Display settings | Settings → System → Display → Advanced display | Advertised resolution and refresh rate available |
| Device Manager | Win + X → Device Manager | No yellow warning icons |
| Reliability Monitor | Start → type **reliability** | A crash/error timeline. Lots of red X's is a bad sign |
| Activation | Settings → System → Activation | "Windows is activated" |
| Camera | Start → Camera | Webcam works |
| Sound Recorder | Start → Sound Recorder | Mic works |

