# laptop-genuineness

Check whether a Windows laptop is genuine and healthy **before you buy it**. It works for new laptops, store demo/display units, and second-hand laptops.

Everything runs on the laptop itself, so you see the results with your own eyes instead of trusting the seller.
The scripts only **read** information. Nothing on the laptop is changed.

| File | What it does |
|---|---|
| [`check.ps1`](check.ps1) | One script that checks model and serial, CPU, RAM, GPU (with real VRAM), display, SSD health, battery health, Windows activation, crash/hardware-error history and faulty devices. It ends with an automatic **PASS / WARN / FAIL summary** and saves a report. |
| [`screen-keyboard-test.html`](screen-keyboard-test.html) | Full-screen colour test (dead pixels, backlight bleed, image retention), key-by-key keyboard test, and a refresh-rate check. |
| [`EXTRA-COMMANDS.md`](EXTRA-COMMANDS.md) | Individual commands to run by hand, plus the CPU stress test and live GPU monitor, each explained. |

Works on **Windows 10 and 11** (any brand: Asus, MSI, Lenovo, HP, Dell, Acer…). It does not work on Windows 7/8 or Windows in **S mode**, which blocks PowerShell scripts.

---

## Quick start (no USB needed)

The laptop only needs internet. Connect it to the store Wi-Fi or your phone's hotspot.

### 1. Open PowerShell as Administrator

Press **Win + X**, click **Terminal (Admin)** (on older Windows: **Windows PowerShell (Admin)**), then click **Yes**.

Without Admin the script still runs, but SSD wear/hours and some battery data will be missing.

### 2. Run the check

```powershell
irm https://raw.githubusercontent.com/Dev010904/laptop-genuineness/main/check.ps1 | iex
```

- `irm` (Invoke-RestMethod) downloads the script text from GitHub.
- `iex` (Invoke-Expression) runs it in memory. Nothing is installed.
- The report is saved to **Desktop\laptop-test-report\\**, and the battery report opens in the browser.

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

Start with the **SUMMARY** at the bottom of the output:

- **FAIL**: serious problem. Don't buy, or only buy after it's fixed.
- **WARN**: check it, and use it to negotiate the price.
- **INFO**: worth knowing, not a fault.
- **PASS**: nothing wrong was found by software. Now do the physical checks.

Then compare each section with the laptop's **official spec sheet** (manufacturer website) and the **box / bill**:

| Section | What to check |
|---|---|
| **Model / Serial** | Model matches the exact model code you're paying for. **Serial** matches the sticker under the laptop, the box and the bill. A missing or generic serial ("To be filled by O.E.M.") is a FAIL: the motherboard may have been replaced. |
| **CPU** | Exact processor name and core/thread count match the spec sheet. |
| **RAM** | Total size and speed match. Two modules = dual channel. One module = single channel (slower graphics). |
| **GPU** | Dedicated GPU name and **VRAM_GB** match (e.g. RTX 4060 = 8 GB). Integrated GPUs show blank VRAM because they share system RAM. |
| **Display** | Resolution matches. **MaxRefreshRate** should match the advertised Hz. The panel's manufacture week/year tells you how old the stock is. |
| **Storage** | `Healthy`. Wear 0–2 % on a new or demo laptop. Read/write errors 0. Size about 93 % of the advertised number (1 TB shows as about 954 GB, which is normal). |
| **Battery** | Health 90 %+ is good. 85–90 % is WARN (negotiate). Below 85 % is FAIL. Also check the cycle count in the battery report. |
| **Windows** | Activated = True. Extra personal user accounts mean someone has been using it. |
| **Health history** | **WHEA hardware errors must be 0.** A few unexpected shutdowns are normal on a store unit. Blue screens and disk errors should be 0. |
| **Devices with problems** | Should be empty. |

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
| Storage | 1 TB NVMe (about 954 GB shown) |
| Battery | About 90,000 mWh design capacity |

---

Read-only checks. Use at your own risk. Always confirm the warranty directly with the manufacturer.
