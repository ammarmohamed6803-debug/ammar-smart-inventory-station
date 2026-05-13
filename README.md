📦 Handmade Heroes Inventory Station

A standalone IoT warehouse terminal built on ESP32 — scan, log, and sync inventory in real time without a computer.
<img width="1512" height="808" alt="image" src="https://github.com/user-attachments/assets/1d1edde3-8031-4a0a-829c-09b0744a5b7c" />
<img width="1512" height="808" alt="image" src="https://github.com/user-attachments/assets/0379b872-d9bb-4332-8688-ba31d714ab36" />
<img width="1197" height="658" alt="image" src="https://github.com/user-attachments/assets/bcd14fb0-8b5c-4a6d-ba99-b196aad0fc60" />



🧾 Overview
The Handmade Heroes Inventory Station is a physical inventory management terminal designed for a small cosmetics warehouse. Workers tap their RFID cards, type a product code on a keypad, and log stock movements — all tracked per batch and synced live to Google Sheets.
Built entirely on an ESP32 DevKit V1, with no PC required on the warehouse floor.

✨ Features

🔖 RFID worker authentication — each worker taps their card to start a session
📦 Per-batch inventory tracking — store, ship, or add leftovers per batch number
🔁 Offline queue — transactions saved to flash if WiFi is down, auto-synced on reconnect
📊 Google Sheets integration — every transaction logs to a live spreadsheet via Apps Script
🌐 Web admin panel — edit the product list from any browser on the same network, no reflashing needed
🔒 Supervisor mode — Ammar, Aqilah, and Adi have elevated access to view stock and sync queue
↩️ Undo — reverse the last transaction (reflected on both device and sheet)
🛡️ Stock protection — can't delete a product that still has stock via the web admin
💾 Persistent storage — inventory state survives power cuts (LittleFS binary file)
⏱️ Auto session timeout — 30-minute idle timeout for security


🛠️ Hardware
ComponentDetailsMicrocontrollerESP32 DevKit V1 (30-pin)RFID ReaderRC522 (SPI)Display20×4 I2C LCD (address 0x27)Keypad4×4 matrix keypadLEDsGreen (GPIO 2), Red (GPIO 16)I2C ExpanderPCF8574 (for LCD backpack)
Pin Mapping
RC522 (SPI)
RC522ESP32SSGPIO 5RSTGPIO 4MOSIGPIO 23MISOGPIO 19SCKGPIO 18
LCD I2C
SignalESP32SDAGPIO 21SCLGPIO 22
Keypad Rows/Cols
PinsRows13, 14, 27, 26Cols25, 33, 32, 15

🗂️ Project Structure
/
├── inventory_station_v5.ino   # Main firmware (latest)
├── inventory_station_v4.ino   # Previous version (no web admin)
├── README.md
├── circuit.png                # Proteus schematic
├── sheets.png                 # Google Sheets screenshot
└── enclosure.png              # 3D enclosure CAD render

🚀 Getting Started
1. Prerequisites
Install these libraries in Arduino IDE:

MFRC522
LiquidCrystal_I2C
Keypad
WiFiClientSecure
LittleFS (ESP32 built-in)
Preferences (ESP32 built-in)
WebServer (ESP32 built-in)

Board: ESP32 Dev Module via Arduino ESP32 board package
2. Configuration
Edit these lines at the top of the .ino before flashing:
cppconst char* WIFI_SSID     = "YourNetworkName";
const char* WIFI_PASSWORD = "YourPassword";
const char* SHEET_URL     = "https://script.google.com/macros/s/YOUR_SCRIPT_ID/exec";
3. Google Apps Script Setup

Open Google Sheets → create a new spreadsheet
Go to Extensions → Apps Script
Paste your Code.gs and deploy as a Web App

Execute as: Me
Access: Anyone


Copy the deployment URL into SHEET_URL

4. First Boot
On first boot the device will:

Write the default product list to /products.csv on LittleFS
Connect to WiFi and show the IP address on the LCD
Auto-flush any queued offline transactions
Show Station Ready

5. Web Admin — Adding / Editing Products

Note the IP shown on the LCD at boot (e.g. 192.168.1.45)
Open http://192.168.1.45 in any browser on the same network
Edit products in code|name|sku format, one per line
Hit Save & Reload


⚠️ You cannot remove a product that still has stock. Ship it out first.


👷 Worker Roles
NameRoleAmmarSupervisorAqilahSupervisorAdiSupervisorYettiWorkerStevenWorkerStaffWorker
Supervisors get an Admin Panel on login with options to view stock, sync the offline queue, and switch to work mode.

📋 Transaction Types
ActionDescriptionStorageNew stock arriving — enter batch, box color, box qty, piecesShippingStock going out — pick batch, enter pieces to deductAdd LeftoverAdd loose pieces to an existing batch

🔄 Offline Mode
If WiFi is down, transactions are saved to /queue.txt on LittleFS. They auto-flush to Google Sheets on next boot, or manually via the supervisor's Sync Queue option.

🔧 Factory Reset
To wipe all stored data, uncomment this in setup():
cppfactoryReset();
Flash once, then comment it out and reflash. The LCD will instruct you.

📊 Google Sheets Columns
ColumnFieldADate & TimeBProduct ID (SKU)CProduct NameDConditionEBox TypeFNo. of BoxesGNo. of PiecesHTotal QtyIPatch No. (Batch)JWorker Name

📝 Version History
VersionChangesv5Web admin panel, LittleFS batch persistence, undo syncs to Sheets, factory reset, stock protectionv4Per-batch tracking, offline queue, supervisor mode, NVS persistence

📄 License
MIT — free to use and modify. Credit appreciated.

🙏 Acknowledgements

That's the full thing. Just copy it into a file called README.md in your GitHub repo root, upload your 3 images named circuit.png, sheets.png, and enclosure.png, and it'll render perfectly on the repo homepage.
Built for Handmade Heroes — a Malaysian handmade cosmetics brand. Designed to replace manual stock counting with a fast, reliable, offline-capable hardware terminal.

That's the full thing. Just copy it into a file called README.md in your GitHub repo root, upload your 3 images named circuit.png, sheets.png, and enclosure.png, and it'll render perfectly on the repo homepage.Sonnet 4.6Adaptive
