# laptop-genuineness

Check whether a Windows laptop is genuine and healthy **before you buy it**. It works for new laptops, store demo/display units, and second-hand laptops.

Everything runs on the laptop itself, so you see the results with your own eyes instead of trusting the seller.
The scripts only **read** information. Nothing on the laptop is changed.

| File | What it does |
|---|---|
| [`check.ps1`](check.ps1) | One script that checks model and serial, CPU, RAM, GPU (with real VRAM), display (exact max refresh rate), SSD health, battery health, Windows activation, crash/hardware-error history and faulty devices. It ends with a colour-coded **SCORECARD** showing every **Result next to its Expected value** with a verdict, and saves a report. |
| [`screen-keyboard-test.html`](screen-keyboard-test.html) | Full-screen colour test (dead pixels, backlight bleed, image retention), key-by-key keyboard test, and a refresh-rate check. |
| [`EXTRA-COMMANDS.md`](EXTRA-COMMANDS.md) | Individual commands to run by hand, plus the CPU stress test and live GPU monitor, each explained. |

Works on **Windows 10 and 11** (any brand: Asus, MSI, Lenovo, HP, Dell, Acer…). It does not work on Windows 7/8 or Windows in **S mode**, which blocks PowerShell scripts.

---

## Quick start (no USB needed)

The laptop only needs internet. Connect it to the store Wi-Fi or your phone's hotspot.

Run it **as Administrator**. Without Admin the script still runs, but SSD wear/hours and some battery data will be missing.

### Option A: one command from any PowerShell (easiest)

Open any PowerShell window (Start → type `powershell` → Enter), paste this, then click **Yes** on the Windows popup:

```powershell
Start-Process powershell -Verb RunAs -ArgumentList '-NoExit','-ExecutionPolicy','Bypass','-Command','irm https://raw.githubusercontent.com/Dev010904/laptop-genuineness/main/check.ps1 | iex'
```

A new **Administrator** window opens, runs the full check, and stays open so you can read the scorecard.

### Option B: open an Admin terminal yourself

1. Press **Win + X**, click **Terminal (Admin)** (on older Windows: **Windows PowerShell (Admin)**), then click **Yes**. The window title must say **Administrator**.
2. Paste and press Enter:

```powershell
irm https://raw.githubusercontent.com/Dev010904/laptop-genuineness/main/check.ps1 | iex
```

- `irm` (Invoke-RestMethod) downloads the script text from GitHub.
- `iex` (Invoke-Expression) runs it in memory. Nothing is installed.
- The report is saved to **Desktop\laptop-test-report\\**, and the battery report opens in the browser.

Other ways to get an Admin PowerShell: Start → type `powershell` → right-click → **Run as administrator**, or **Win + R** → type `powershell` → **Ctrl + Shift + Enter**.

### 3. Open the screen and keyboard test

Open this link in the laptop's browser:

**https://dev010904.github.io/laptop-genuineness/screen-keyboard-test.html**

### 4. Clean up when you're done

Delete the **laptop-test-report** folder from the Desktop. Take a photo of the summary first, or copy the folder to your phone or USB.

---

## Offline option (USB stick)

1. Download this repo: **Code → Download ZIP**. Extract it to a USB stick.
2. In an Admin PowerShell, run the command below, replacing `E:` with your USB letter:

   ```powershell
   powershell -ExecutionPolicy Bypass -File "E:\laptop-genuineness\check.ps1"
   ```

   The report is saved next to the script, on the USB.

3. If Windows says the script is blocked (downloaded files get marked), run this once, then try again:

   ```powershell
   Unblock-File "E:\laptop-genuineness\check.ps1"
   ```

4. Double-click `screen-keyboard-test.html` to open it in the browser.

To find your USB drive letter:

```powershell
Get-Volume | Where-Object DriveType -eq Removable
```

---

## Reading the results

Scroll to the **SCORECARD** at the bottom. Every check is shown like this:

```
[FAIL ] Max refresh rate
         Result  : 144 Hz
         Expected: 240 Hz
```

Rows are sorted worst first:

| Verdict | Colour | Meaning |
|---|---|---|
| **FAIL** | Red | Serious problem or doesn't match the spec. Don't buy until it's explained or fixed. |
| **WARN** | Yellow | Check it, and use it to negotiate the price. |
| **CHECK** | Cyan | The script can't know the right answer. Compare it with the box, the bill and the spec sheet. |
| **OK** | Green | Matches what's expected. |
| **INFO** | Grey | Worth knowing, not a fault. |

The last lines give **TOTAL** counts and an overall **VERDICT**.

### Known models are compared automatically

If the laptop matches a built-in **model profile**, the script compares CPU, RAM, GPU + VRAM, resolution, refresh rate, SSD size and battery capacity against that model's **exact specs**, and marks each row OK or FAIL.

Currently included:
- **MSI Crosshair 16 HX AI (D2XWFKG-067IN)**

Other models get **CHECK** rows for those items, so you compare them with the spec sheet yourself. To add a model, copy the entry in `$profiles` at the top of `check.ps1`.

### Expected values for every check

| Check | Expected | Verdict rules |
|---|---|---|
| Run as Administrator | Yes | No = WARN (SSD data missing) |
| Model | Exact model code on box + bill | CHECK (OK when a profile matches) |
| Serial number | Same as sticker, box, bill | Missing/generic ("To be filled by O.E.M.") = **FAIL**, board replaced |
| CPU | Spec sheet processor + thread count | Profile mismatch = FAIL |
| RAM | Spec sheet size + speed | Profile mismatch = FAIL. Running below rated speed = WARN |
| RAM channels | 2 modules (dual channel) | 1 module = WARN |
| Dedicated GPU | Spec sheet GPU + VRAM (e.g. RTX 5060 = 8 GB) | Profile mismatch = FAIL |
| Graphics drivers | All OK | "Microsoft Basic Display" or error = FAIL |
| NVIDIA driver | nvidia-smi works | Missing = WARN |
| Screen resolution | Spec sheet (e.g. 2560 x 1600) | Profile mismatch = FAIL |
| Max refresh rate | Spec sheet (e.g. 240 Hz) | Profile mismatch = FAIL |
| Current refresh rate | Same as max | Lower = INFO (change it in Settings, or plug in charger) |
| SSD size | Spec sheet (1 TB shows ~931–954 GB) | Profile mismatch = FAIL |
| SSD health | Healthy | Anything else = FAIL |
| SSD wear | 0–2 % | 3–10 % = WARN, over 10 % = FAIL |
| SSD power-on hours | New: under ~50 h | INFO (high is normal on a demo unit) |
| SSD temperature | Under 70 °C idle | 70–80 = WARN, 80+ = FAIL |
| SSD read/write errors | 0 | Any = FAIL |
| Battery health | 90 %+ | 85–90 % = WARN (negotiate), under 85 % = FAIL |
| Battery design capacity | Profile value (e.g. 90 Wh) | Off by more than 5 % = WARN (non-original battery?) |
| Battery cycles | Under 50 for new/demo | 50–300 = WARN, 300+ = FAIL |
| Windows activated | Yes | No = WARN |
| User accounts | 1 | More = CHECK (someone used it) |
| Hardware errors (WHEA) | 0 | Any = **FAIL** |
| Blue screens | 0 | Driver codes (e.g. 0x9F) = WARN. Hardware codes (0x124, 0x7A, 0x1A) = **FAIL**. The code and its meaning are shown |
| Unexpected shutdowns | 0–5 | More = WARN |
| Internal disk errors | 0 | Any = FAIL. Errors from USB drives are listed separately and ignored |
| Devices with problems | None | Any = WARN |
| Wi-Fi, Bluetooth, webcam, speakers, mic | Present | Missing = FAIL |

### Things that can show blank (not a fault)

- **SSD wear / power-on hours:** some laptops hide these (Intel RST/VMD mode, some SSD brands). Use **CrystalDiskInfo** portable from its official site instead.
- **Battery cycle count:** some brands don't report it to Windows. Check the battery report HTML.
- **nvidia-smi:** only exists on laptops with an NVIDIA GPU.

### Reading the battery report (the HTML that opens)

- **Installed batteries:** compare `DESIGN CAPACITY` with `FULL CHARGE CAPACITY`, and check the `CYCLE COUNT`.
- **Battery capacity history:** how fast capacity has been dropping.
- **Usage history:** how much it has been used. A store display unit is plugged in almost all the time.

---

## Screen and keyboard test

### Screen test
1. Click **Start screen test**. The page goes full screen.
2. **Click**, or press **Space / arrow keys**, to change colour. Press **Esc** to exit.
3. What to look for on each colour:
   - **White, red, green, blue:** black dots (dead pixels) or always-coloured dots (stuck pixels). Scan slowly, section by section.
   - **Black:** set brightness to 100%, and stand somewhere dim if you can. Look for light glowing from the edges (backlight bleed). A little is normal on IPS; big bright patches are not.
   - **Grey 50%:** faint ghost shapes of a store demo loop (image retention), or blotchy areas.
   - **Dark grey:** cloudy or uneven patches.
   - **Gradient:** should be smooth, with no stripes.
4. Shine your **phone flashlight at an angle** on the screen to find scratches.

### Keyboard test
Click **Start keyboard test** and press **every key**. Each one turns green when it registers.

Keys like **Fn**, the **Copilot key** and some media keys can't be seen by a browser. Test those by using them, for example brightness and volume.

### Refresh rate
The menu shows **Browser refresh rate ≈ … Hz**. Plugged in, it should match the advertised refresh rate (for example 144, 165 or 240).

If it shows 60, check **Settings → System → Display → Advanced display → Choose a refresh rate**.

---

## Stress test (fans and stability)

See [`EXTRA-COMMANDS.md`](EXTRA-COMMANDS.md#1-stress-test-fans-stability-temperatures). It runs every CPU thread at 100 % for 5 minutes while you watch the temperatures and listen to the fans.

---

## Physical checks (no software can do these)

- **Battery swelling:** this is the most important physical check on demo or used laptops.
  - Put the laptop on a flat surface and press each corner. It should not rock.
  - The touchpad should not be raised.
  - The bottom panel should not bulge.
  - There should be no gap between the keyboard deck and the body.
- **Body:**
  - Look for scratches and dents.
  - Look for shiny keycaps (W, A, S, D, Space).
  - The hinge should be firm with no wobble.
  - Look for glue or holes from anti-theft tags.
- **Screws:** scratched screw heads mean it has been opened.
- **Vents:** shine your flashlight in. There should be no heavy dust.
- **Ports:**
  - Test every USB port.
  - Test HDMI on a monitor.
  - Test USB-C / Thunderbolt.
  - Test LAN.
  - Test the 3.5 mm audio jack.
- **Camera / mic / speakers:**
  - Open the Camera app.
  - Use Sound Recorder to test the mic.
  - Play a video to test the speakers.
- **Charger:** should be the original adapter, with the correct wattage on its label.
- **Warranty:** type the serial number into the **manufacturer's warranty check page on your own phone**. If it's a demo unit, ask for the warranty to start from your invoice date, written on the bill.

## Walk away if

- The battery is swollen, or its health is below 85 %
- There are dead pixels or clear image retention
- Model, CPU, RAM, GPU or serial don't match what you're paying for
- There are WHEA hardware errors, or many crashes
- The seller **won't let you run these checks**

---

## Example: MSI Crosshair 16 HX AI (D2XWFKG-067IN)

What a correct result looks like for this model:

| Check | Expected |
|---|---|
| Model | `Crosshair 16 HX AI D2XWFKG…` |
| CPU | Intel Core Ultra 9 275HX, 24 cores / 24 threads |
| RAM | 2 × 8 GB DDR5, 5600 |
| GPU | NVIDIA GeForce RTX 5060 Laptop GPU, 8 GB + Intel graphics |
| Display | 2560 × 1600, 240 Hz |
| Storage | 1 TB NVMe (about 931–954 GB shown) |
| Battery | About 90,000 mWh design capacity |

---

Read-only checks. Use at your own risk. Always confirm the warranty directly with the manufacturer.
