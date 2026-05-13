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
#include <SPI.h>
#include <MFRC522.h>
#include <Wire.h>
#include <LiquidCrystal_I2C.h>
#include <Keypad.h>
#include <WiFi.h>
#include <HTTPClient.h>
#include <WiFiClientSecure.h>
#include <LittleFS.h>
#include <Preferences.h>
#include <WebServer.h>

// ============================================================
//  Handmade Heroes Inventory Station — v5
//  Board: ESP32 DevKit V1 (30-pin)
//  Features:
//   - Per-batch inventory tracking (Storage / Ship / Add Leftover)
//   - Inventory + batches persist across reboot (Preferences/NVS)
//   - Offline queue on LittleFS, auto-flush on boot
//   - Supervisor mode (Aqilah, Adi) with admin panel
//   - Products loaded from /products.csv on LittleFS
//   - Web admin (browser) for editing products without reflashing
//   - Stock-protection: can't remove product that still has stock
// ============================================================

// --- WiFi ---
const char* WIFI_SSID     = "SparkeLabs_2.4GHz";
const char* WIFI_PASSWORD = "12345678";

// --- Google Apps Script URL ---
const char* SHEET_URL = "https://script.google.com/macros/s/AKfycbym5JZwn9BIzqOETfA4Sa0kmPfgXFmbDQrbwtvMrDbQJu0BIF-1C5gdSOyR9KzuFthaTQ/exec";

// --- RC522 RFID (SPI) ---
#define RC522_SS   5
#define RC522_RST  4
MFRC522 rfid(RC522_SS, RC522_RST);

// --- LCD 20x4 (I2C @ 0x27) ---
LiquidCrystal_I2C lcd(0x27, 20, 4);

// --- LEDs ---
const int GREEN_LED_PIN = 2;
const int RED_LED_PIN   = 16;

// --- 4x4 Keypad ---
const byte ROWS = 4, COLS = 4;
char keys[ROWS][COLS] = {
  {'1','2','3','A'},
  {'4','5','6','B'},
  {'7','8','9','C'},
  {'*','0','#','D'}
};
byte rowPins[ROWS] = {13, 14, 27, 26};
byte colPins[COLS] = {25, 33, 32, 15};
Keypad keypad = Keypad(makeKeymap(keys), rowPins, colPins, ROWS, COLS);

// --- Preferences (NVS) ---
Preferences prefs;

// --- Web admin server ---
WebServer adminServer(80);

// ============================================================
//  WORKER DATABASE — Ammar ,Aqilah and Adi  are SUPERVISORS
// ============================================================
const int NUM_WORKERS = 6;
byte workerUIDs[NUM_WORKERS][7] = {
  {0x19, 0x82, 0xBA, 0x11, 0x00, 0x00, 0x00}, // Ammar
  {0x04, 0xC1, 0x6A, 0x2E, 0x32, 0x02, 0x89}, // Aqilah
  {0x04, 0x91, 0x2D, 0x3D, 0x32, 0x02, 0x89}, // Yetti
  {0x04, 0x31, 0x58, 0xBB, 0x31, 0x02, 0x89}, // Steven
  {0x04, 0xC1, 0x03, 0xF8, 0x31, 0x02, 0x89}, // staff
  {0x04, 0xB1, 0xF5, 0xAA, 0x31, 0x02, 0x89}  // Adi
};
byte   workerUIDSizes[NUM_WORKERS] = {4, 7, 7, 7, 7, 7};
String workerNames[NUM_WORKERS]    = {"Ammar","Aqilah","Yetti","Steven","Staff","Adi"};
bool   isSupervisor[NUM_WORKERS]   = {true, true, false, false, false, true};
int currentWorker = -1;

// ============================================================
//  PRODUCT DATABASE
// ============================================================
const int MAX_PRODUCTS = 90;
int NUM_PRODUCTS = 86;

String productCodes[MAX_PRODUCTS];
String productNames[MAX_PRODUCTS];
String productSKUs[MAX_PRODUCTS];

const char* defaultProducts[] = {
  "001A|Lip Scrub Coconut|FG-HMHLS-001",
  "002A|Lip Scrub Matcha|FG-HMHLS-002",
  "004A|Lip Scrub Bakuchiol|FG-HMHLS-004",
  "006A|Lip Scrub Turmeric|FG-HMHLS-006",
  "007A|Lip Scrub Peppermint|FG-HMHLS-007",
  "001B|Coffee Scrub Orange|FG-HMHBS-001B",
  "02AB|Body Scrub Rose|FG-HMHBS-002A",
  "04DC|Clay Mask GreenTea|FG-HMHFM-004",
  "02AC|Gel Mask Jasmine|FG-HMHGM-002",
  "01DA|DryShampoo Med-Dark|FG-HMHDS-001",
  "02DA|DryShampoo Lt-Med|FG-HMHDS-002",
  "03DA|DryShampoo Rosemary Dark|FG-HMHDS-003",
  "04DA|DryShampoo Rosemary Lt|FG-HMHDS-004",
  "02BB|Nipple Balm|FG-HMHNB-002",
  "01DB|Diaper Balm|FG-HMHDB-001",
  "01AA|Lip Mask AllNighter|FG-HMHLM-001",
  "02AA|Lip Mask Bakuchiol|FG-HMHLM-002",
  "05AA|Lip Butter SoftPink|FG-HMHLM-005",
  "03BA|Lip Dew Mood|FG-HMHLT-003A",
  "06BA|Lip Dew Classic|FG-HMHLT-006A",
  "07BA|Lip Dew CottageCore 1.3g|FG-HMHLT-007",
  "7BAA|Lip Dew CottageCore 10ml|FG-HMHLT-007A",
  "02BA|Lip Dew Spirited|FG-HMHLB-002A",
  "001C|SnowShroom HA Serum|FG-HMHFS-001",
  "003C|Bakuchiol Oil 22ml|FG-HMHFS-003",
  "03CB|Bakuchiol Oil 10ml|FG-HMHFS-003B",
  "004C|Bakuchiol FirmSerum|FG-HMHFS-004",
  "005C|Squalane Face Oil|FG-HMHFS-005",
  "006C|SuperGlow VitC Oil|FG-HMHFS-006",
  "01CC|Oat Cuticle Oil|FG-HMHCO-001",
  "01CA|Eyelash Serum|FG-HMHES-001",
  "02CA|Eyebrow Serum|FG-HMHES-002",
  "03CA|UnderEye Espresso|FG-HMHES-003",
  "1AA0|LipOil SuperGlaze 5ml|FG-HMHLO-001",
  "1AAA|LipOil SuperGlaze 1ml|FG-HMHLO-001A",
  "2AA0|LipOil SugarPeach 5ml|FG-HMHLO-002",
  "2AAA|LipOil SugarPeach 1ml|FG-HMHLO-002A",
  "3AA0|LipOil Caramel 5ml|FG-HMHLO-003",
  "3AAA|LipOil Caramel 1ml|FG-HMHLO-003A",
  "4AA0|LipOil SweetBeet 5ml|FG-HMHLO-004",
  "4AAA|LipOil SweetBeet 1ml|FG-HMHLO-004A",
  "5AA0|LipOil VitC Turmeric|FG-HMHLO-005",
  "6AA0|LipOil Moonshine 5ml|FG-HMHLO-006",
  "6AAA|LipOil Moonshine 1ml|FG-HMHLO-006A",
  "7AA0|LipOil Ripe Cherry|FG-HMHLO-007",
  "1AB0|Face Mist Jasmine 66ml|FG-HMHMF-001",
  "1ABA|Face Mist Jasmine|FG-HMHMF-001A",
  "1CA0|Peppermint FootCream|FG-HMHFC-001",
  "2CA0|TeaTree FootCream|FG-HMHFC-002",
  "CC01|Natural Deo Unscent|FG-HMHSD-001",
  "AC01|Hair Tonic Thrive|FG-HMHHT-001",
  "5BB0|HBS Hyaluronic Acid|FG-HBS-005",
  "6BB0|HBS Niacinamide 12%|FG-HBS-006",
  "7BB0|HBS Niacinamide 20%|FG-HBS-007",
  "8BB0|HBS Vitamin C|FG-HBS-008",
  "9BB0|HBS Salicylic Acid|FG-HBS-009",
  "10BB|HBS Caffeine Eye|FG-HBS-010",
  "C010|Oat Cleansing Oil|FG-MOC-001",
  "B010|Micellar Water|FG-MMW-001",
  "CB01|VitF Cleansing Balm|FG-MCB-001",
  "AB01|AB Niacinamide 12%|FG-ABS-001",
  "AB02|AB Squalane|FG-ABS-002",
  "AB03|AB Vitamin C Serum|FG-ABS-003",
  "AB04|AB Hyaluronic Acid|FG-ABS-004",
  "AB06|AB Niacinamide 20%|FG-ABS-006",
  "AB07|AB Salicylic Acid|FG-ABS-007",
  "BB01|JP Deo FragranceFree|FG-JPSD-001",
  "BB02|JP Deo Zen AF|FG-JPSD-002",
  "BB03|JP Deo Coconut Van|FG-JPSD-003",
  "AA01|GiftBox LipCare|FG-HMHGB-001",
  "AA02|GiftBox LipBrighten|FG-HMHGB-002",
  "AA03|GiftBox LipPerfect|FG-HMHGB-003",
  "AA04|GiftBox DewySkin Kit|FG-HMHGB-004",
  "AA05|GiftBox LipOil Set|FG-HMHGB-005",
  "AA06|GiftBox MiniLipOil|FG-HMHGB-006",
  "AA07|Lip Exfoliate Brush|FG-HMHGB-007",
  "AA08|GiftBox Lash&Brow|FG-HMHGB-008",
  "AA12|Pumice Foot File|FG-HMHGB-012",
  "AA13|MicroGlass FootFile|FG-HMHGB-013",
  "AA14|Exfoliating Gloves|FG-HMHGB-014",
  "AA15|Cozy Socks Green|FG-HMHGB-015",
  "AA16|Cozy Gloves Green|FG-HMHGB-016",
  "AA17|Lip Brush Yellow|FG-HMHGB-017",
  "CA01|FaceLift Belt Blue|FG-HBGB-001",
  "CA02|FaceLift Belt Beige|FG-HBGB-002",
  "CA03|FaceLift Belt Pink|FG-HBGB-003"
};
const int DEFAULT_PRODUCT_COUNT = 86;

// ============================================================
//  BATCH DATA MODEL
// ============================================================
const int MAX_BATCHES = 15;
const int BATCH_NO_LEN = 13;

struct BatchInfo {
  char batchNo[BATCH_NO_LEN];
  int  boxes[5];
  int  pieces;
};

BatchInfo batches[MAX_PRODUCTS][MAX_BATCHES];

int queueCount = 0;

// ============================================================
//  STATE MACHINE
// ============================================================
enum State {
  STATE_IDLE,
  STATE_SUPERVISOR_MENU,
  STATE_ENTER_ID,
  STATE_CONFIRM_PRODUCT,
  STATE_SELECT_ACTION,
  STATE_ENTER_BATCH,
  STATE_SELECT_BATCH,
  STATE_SHOW_BATCH_DETAIL,
  STATE_SELECT_BOX,
  STATE_ENTER_BOX_QTY,
  STATE_ENTER_PIECES,
  STATE_CONFIRM,
  STATE_INVENTORY_SUMMARY
};
State currentState = STATE_IDLE;

String inputBuffer        = "";
String currentProductCode = "";
int    currentProductIdx  = -1;
int    currentAction      = 0;
int    currentBoxColor    = 0;
int    boxQty  = 0;
int    pieceQty = 0;
String batchNo  = "";
int    selectedBatchIdx = -1;
int    batchPage = 0;

String lastTransaction = "None";
int    lastPIdx        = -1;
int    lastAction      = 0;
int    lastBoxColor    = 0;
int    lastBoxQty      = 0;
int    lastPieceQty    = 0;
int    lastBatchIdx    = -1;
bool   lastBatchWasNew = false;
String lastWorkerName  = "";
String lastBatch       = "";

unsigned long lastActivityMs = 0;
const unsigned long IDLE_TIMEOUT_MS = 30UL * 60UL * 1000UL;

// --- Prototypes ---
void showIdleScreen();
void promptProductID();
void showProductConfirm();
void promptAction();
void promptBatch();
void showBatchSelector();
void showBatchDetail();
void promptBoxColor();
void promptBoxQty();
void promptPieces();
void showConfirmation();
void saveTransaction();
void showInventorySummary(int);
void errorFlash(String);
void resetSession();
void handleUndo();
void showSupervisorMenu();
void adminViewStock();
void adminFlushQueue();
void adminViewQueue();
void saveBatchState();
void loadBatchState();
void saveProductsToFile();
void loadProductsFromFile();
void loadDefaultProducts();
void queueTransaction(String payload);
void flushQueue();
int  countQueuedItems();
int  findProductIndex(String code);
int  findWorkerIndex(byte* uid, byte size);
int  findBatchIndex(int p, String bn);
int  findFreeBatchSlot(int p);
int  countActiveBatches(int p);
int  nthActiveBatch(int p, int n);
int  totalProductPieces(int p);
int  totalProductBoxes(int p, int color);
void cleanupEmptyBatches(int p);
bool sendToSheet(String payload);
String boxColorName(int c);
String actionName(int a);
void handleAdminRoot();
void handleAdminSave();

// ============================================================
//  HTTP
// ============================================================
bool sendToSheet(String payload) {
  WiFiClientSecure client;
  client.setInsecure();
  HTTPClient https;
  https.setTimeout(10000);
  https.setFollowRedirects(HTTPC_DISABLE_FOLLOW_REDIRECTS);
  if (!https.begin(client, SHEET_URL)) return false;
  https.addHeader("Content-Type", "application/json");
  int code = https.POST(payload);
  https.end();
  Serial.print("HTTP: "); Serial.println(code);
  return (code == 200 || code == 302);
}

// ============================================================
//  OFFLINE QUEUE (LittleFS)
// ============================================================
void queueTransaction(String payload) {
  File f = LittleFS.open("/queue.txt", FILE_APPEND);
  if (f) {
    f.println(payload);
    f.close();
    queueCount++;
    Serial.println("Queued offline (Q:" + String(queueCount) + ")");
  }
}

int countQueuedItems() {
  File f = LittleFS.open("/queue.txt", FILE_READ);
  if (!f) return 0;
  int count = 0;
  while (f.available()) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 2) count++;
  }
  f.close();
  return count;
}

void flushQueue() {
  if (WiFi.status() != WL_CONNECTED) return;
  File f = LittleFS.open("/queue.txt", FILE_READ);
  if (!f) return;

  String lines[50];
  int total = 0;
  while (f.available() && total < 50) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() > 2) lines[total++] = line;
  }
  f.close();

  if (total == 0) return;

  String failedLines[50];
  int failed = 0;

  for (int i = 0; i < total; i++) {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("Syncing " + String(i+1) + "/" + String(total));
    if (!sendToSheet(lines[i])) {
      failedLines[failed++] = lines[i];
    }
    lcd.init(); lcd.backlight();
  }

  LittleFS.remove("/queue.txt");
  if (failed > 0) {
    File fw = LittleFS.open("/queue.txt", FILE_WRITE);
    for (int i = 0; i < failed; i++) fw.println(failedLines[i]);
    fw.close();
  }
  queueCount = failed;
}
// ============================================================
//  FACTORY RESET — TEMPORARY, COMMENT OUT AFTER USE
// ============================================================
void factoryReset() {
  Serial.println("=== FACTORY RESET STARTING ===");

  // Wipe NVS (Preferences) — old batch data from earlier versions
  prefs.begin("inv", false);
  prefs.clear();
  prefs.end();
  Serial.println("NVS cleared");

  // Wipe LittleFS — current batches.bin, queue.txt, products.csv
  LittleFS.format();
  Serial.println("LittleFS formatted");

  Serial.println("=== FACTORY RESET DONE ===");
  Serial.println("Now COMMENT OUT the factoryReset() call and re-upload!");

  // Show on LCD too
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("FACTORY RESET DONE");
  lcd.setCursor(0,1); lcd.print("Now reupload code");
  lcd.setCursor(0,2); lcd.print("with reset line");
  lcd.setCursor(0,3); lcd.print("commented out!");

  // Halt forever — don't continue with normal boot
  while (true) delay(1000);
}
// ============================================================
//  BATCH STATE PERSISTENCE
// ============================================================
// ============================================================
//  BATCH STATE PERSISTENCE — LittleFS version (power-loss safe)
// ============================================================
void saveBatchState() {
  // Write to a temp file first, then rename — atomic on LittleFS
  File f = LittleFS.open("/batches.bin.tmp", FILE_WRITE);
  if (!f) {
    Serial.println("ERROR: failed to open batches.bin.tmp");
    return;
  }
  size_t written = f.write((uint8_t*)batches, sizeof(batches));
  f.close();
  if (written != sizeof(batches)) {
    Serial.println("ERROR: short write to batches.bin.tmp");
    LittleFS.remove("/batches.bin.tmp");
    return;
  }
  // Atomic-ish swap: remove old, rename new
  LittleFS.remove("/batches.bin");
  LittleFS.rename("/batches.bin.tmp", "/batches.bin");
  Serial.println("Batch state saved (" + String(written) + " bytes)");
}

void loadBatchState() {
  File f = LittleFS.open("/batches.bin", FILE_READ);
  if (!f) {
    Serial.println("No saved batch state — starting fresh");
    memset(batches, 0, sizeof(batches));
    return;
  }
  size_t expected = sizeof(batches);
  size_t got = f.read((uint8_t*)batches, expected);
  f.close();
  if (got != expected) {
    Serial.println("WARNING: batch file size mismatch (" + String(got) +
                   "/" + String(expected) + ") — starting fresh");
    memset(batches, 0, sizeof(batches));
    return;
  }
  Serial.println("Batch state loaded (" + String(got) + " bytes)");
}
// ============================================================
//  PRODUCT LIST PERSISTENCE
// ============================================================
void loadDefaultProducts() {
  NUM_PRODUCTS = DEFAULT_PRODUCT_COUNT;
  for (int i = 0; i < DEFAULT_PRODUCT_COUNT; i++) {
    String line = String(defaultProducts[i]);
    int p1 = line.indexOf('|');
    int p2 = line.indexOf('|', p1 + 1);
    productCodes[i] = line.substring(0, p1);
    productNames[i] = line.substring(p1 + 1, p2);
    productSKUs[i]  = line.substring(p2 + 1);
  }
}

void saveProductsToFile() {
  File f = LittleFS.open("/products.csv", FILE_WRITE);
  if (!f) return;
  for (int i = 0; i < NUM_PRODUCTS; i++) {
    f.println(productCodes[i] + "|" + productNames[i] + "|" + productSKUs[i]);
  }
  f.close();
  Serial.println("Products saved to LittleFS (" + String(NUM_PRODUCTS) + ")");
}

void loadProductsFromFile() {
  File f = LittleFS.open("/products.csv", FILE_READ);
  if (!f) {
    Serial.println("No products.csv — using defaults");
    loadDefaultProducts();
    saveProductsToFile();
    return;
  }
  int count = 0;
  while (f.available() && count < MAX_PRODUCTS) {
    String line = f.readStringUntil('\n');
    line.trim();
    if (line.length() < 5) continue;
    int p1 = line.indexOf('|');
    int p2 = line.indexOf('|', p1 + 1);
    if (p1 < 0 || p2 < 0) continue;
    productCodes[count] = line.substring(0, p1);
    productNames[count] = line.substring(p1 + 1, p2);
    productSKUs[count]  = line.substring(p2 + 1);
    count++;
  }
  f.close();
  NUM_PRODUCTS = count;
  Serial.println("Loaded " + String(NUM_PRODUCTS) + " products from LittleFS");
}

// ============================================================
//  WEB ADMIN — edit /products.csv from a browser
// ============================================================
void handleAdminRoot() {
  String html = "<!DOCTYPE html><html><head><title>HMH Inventory Admin</title>";
  html += "<meta name='viewport' content='width=device-width,initial-scale=1'>";
  html += "<style>body{font-family:sans-serif;max-width:700px;margin:20px auto;padding:0 10px}";
  html += "textarea{width:100%;height:60vh;font-family:monospace;font-size:14px;box-sizing:border-box}";
  html += "button{padding:10px 20px;font-size:16px;margin-top:10px;cursor:pointer}";
  html += "h2{color:#333}.hint{color:#666;font-size:13px}";
  html += ".warn{background:#fff3cd;border:1px solid #ffc107;padding:8px;border-radius:4px;font-size:13px}";
  html += "</style></head><body>";
  html += "<h2>HMH Product List</h2>";
  html += "<p class='hint'>Format: <b>code|name|sku</b> — one per line.<br>";
  html += "code = up to 6 chars (what worker types). name = up to 20 chars. sku = full SKU code.</p>";
  html += "<div class='warn'><b>Rules:</b><br>";
  html += "&bull; Add new lines at the bottom — don't reorder existing lines<br>";
  html += "&bull; You cannot remove a product that still has stock — ship it out first<br>";
  html += "&bull; Editing names/SKUs is always safe; changing keypad codes orphans batches</div>";
  html += "<form method='POST' action='/save'>";
  html += "<textarea name='csv'>";

  File f = LittleFS.open("/products.csv", FILE_READ);
  if (f) {
    while (f.available()) {
      char c = f.read();
      if (c == '<') html += "&lt;";
      else if (c == '>') html += "&gt;";
      else if (c == '&') html += "&amp;";
      else html += c;
    }
    f.close();
  }
  html += "</textarea><br>";
  html += "<button type='submit'>Save &amp; Reload</button>";
  html += "</form>";
  html += "<p class='hint'>Current product count: " + String(NUM_PRODUCTS) + "</p>";
  html += "</body></html>";
  adminServer.send(200, "text/html", html);
}

void handleAdminSave() {
  if (!adminServer.hasArg("csv")) {
    adminServer.send(400, "text/plain", "Missing csv");
    return;
  }
  String csv = adminServer.arg("csv");

  // --- Stock-protection check ---
  // Build a list of product codes that currently have active batches,
  // then scan the new CSV to make sure none of them are missing.
  String missing = "";
  for (int i = 0; i < NUM_PRODUCTS; i++) {
    if (countActiveBatches(i) > 0) {
      String code = productCodes[i];
      // Look for "code|" anywhere in the CSV to confirm the product still exists
      bool found = false;
      int searchStart = 0;
      while (searchStart < (int)csv.length()) {
        int idx = csv.indexOf(code + "|", searchStart);
        if (idx < 0) break;
        // Make sure this is at a line start (either start of file or after newline)
        if (idx == 0 || csv.charAt(idx - 1) == '\n' || csv.charAt(idx - 1) == '\r') {
          found = true;
          break;
        }
        searchStart = idx + 1;
      }
      if (!found) {
        missing += code + " (" + productNames[i] + ", " +
                   String(totalProductPieces(i)) + " pcs); ";
      }
    }
  }

  if (missing.length() > 0) {
    String resp = "<!DOCTYPE html><html><body style='font-family:sans-serif;max-width:600px;margin:30px auto'>";
    resp += "<h2 style='color:#c00'>Cannot save</h2>";
    resp += "<p>The following products still have stock and cannot be removed:</p>";
    resp += "<p style='background:#fee;padding:10px;border-left:4px solid #c00'><b>" + missing + "</b></p>";
    resp += "<p>Ship them out completely first, then try again.</p>";
    resp += "<a href='/'>&larr; Back</a></body></html>";
    adminServer.send(400, "text/html", resp);
    return;
  }

  // --- Cardinality check ---
  // Count lines to make sure we don't exceed MAX_PRODUCTS
  int lineCount = 0;
  int idx = 0;
  while (idx < (int)csv.length()) {
    int nl = csv.indexOf('\n', idx);
    if (nl < 0) {
      String tail = csv.substring(idx);
      tail.trim();
      if (tail.length() >= 5 && tail.indexOf('|') > 0) lineCount++;
      break;
    }
    String line = csv.substring(idx, nl);
    line.trim();
    if (line.length() >= 5 && line.indexOf('|') > 0) lineCount++;
    idx = nl + 1;
  }
  if (lineCount > MAX_PRODUCTS) {
    String resp = "<html><body><h2>Too many products</h2>";
    resp += "<p>Limit is " + String(MAX_PRODUCTS) + ", you have " + String(lineCount) + ".</p>";
    resp += "<a href='/'>Back</a></body></html>";
    adminServer.send(400, "text/html", resp);
    return;
  }

  // --- Write file ---
  File f = LittleFS.open("/products.csv", FILE_WRITE);
  if (!f) {
    adminServer.send(500, "text/plain", "Failed to open file");
    return;
  }
  f.print(csv);
  f.close();
  loadProductsFromFile();

  String resp = "<!DOCTYPE html><html><body style='font-family:sans-serif;max-width:600px;margin:30px auto'>";
  resp += "<h2 style='color:#080'>Saved.</h2>";
  resp += "<p>Loaded " + String(NUM_PRODUCTS) + " products.</p>";
  resp += "<a href='/'>&larr; Back</a></body></html>";
  adminServer.send(200, "text/html", resp);
}

// ============================================================
//  SETUP
// ============================================================
void setup() {
  Serial.begin(115200);
  pinMode(GREEN_LED_PIN, OUTPUT);
  pinMode(RED_LED_PIN, OUTPUT);

  if (!LittleFS.begin(true)) {
    Serial.println("LittleFS failed!");
  }
 // factoryReset();
  memset(batches, 0, sizeof(batches));

  loadProductsFromFile();
  loadBatchState();
  queueCount = countQueuedItems();

  Wire.begin(21, 22);
  lcd.init();
  lcd.backlight();

  SPI.begin();
  rfid.PCD_Init();
  delay(50);

  lcd.clear();
  byte v = rfid.PCD_ReadRegister(rfid.VersionReg);
  if (v == 0x00 || v == 0xFF) {
    lcd.print("RC522 ERROR!");
    lcd.setCursor(0,1); lcd.print("Check SPI wiring");
    while (true) delay(1000);
  }
  lcd.print("RC522 OK | Prod:");
  lcd.print(NUM_PRODUCTS);
  delay(800);

  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Connecting WiFi...");
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
  unsigned long wifiStart = millis();
  while (WiFi.status() != WL_CONNECTED && millis() - wifiStart < 15000) {
    delay(300);
  }
  lcd.clear();
  if (WiFi.status() == WL_CONNECTED) {
    lcd.print("WiFi Connected!");
    lcd.setCursor(0,1); lcd.print(WiFi.localIP());
    Serial.println("Web admin: http://" + WiFi.localIP().toString());

    // Start web admin server
    adminServer.on("/", handleAdminRoot);
    adminServer.on("/save", HTTP_POST, handleAdminSave);
    adminServer.begin();

    if (queueCount > 0) {
      lcd.setCursor(0,2); lcd.print("Flushing Q:" + String(queueCount));
      delay(500);
      flushQueue();
    }
  } else {
    lcd.print("WiFi Failed!");
    lcd.setCursor(0,1); lcd.print("Offline mode");
  }
  delay(1200);

  lastActivityMs = millis();
  showIdleScreen();
}

// ============================================================
//  MAIN LOOP
// ============================================================
void loop() {
  adminServer.handleClient();

  char key = keypad.getKey();
  if (key) lastActivityMs = millis();

  if (currentState != STATE_IDLE && (millis() - lastActivityMs > IDLE_TIMEOUT_MS)) {
    currentWorker = -1;
    lcd.clear(); lcd.print("Session timeout");
    delay(1500);
    resetSession();
    return;
  }

  if (key == '*' && currentState != STATE_IDLE && currentState != STATE_SUPERVISOR_MENU) {
    digitalWrite(GREEN_LED_PIN, LOW);
    currentWorker = -1;
    resetSession();
    return;
  }

  if (rfid.PICC_IsNewCardPresent() && rfid.PICC_ReadCardSerial()) {
    lastActivityMs = millis();
    int w = findWorkerIndex(rfid.uid.uidByte, rfid.uid.size);
    rfid.PICC_HaltA();
    rfid.PCD_StopCrypto1();

    if (w == -1) {
      errorFlash("Unknown card!");
      if (currentState == STATE_IDLE) showIdleScreen();
      return;
    }
    if (w == currentWorker && currentState != STATE_IDLE) return;

    currentWorker = w;
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("Hello " + workerNames[w] + "!");
    if (isSupervisor[w]) {
      lcd.setCursor(0,1); lcd.print("[SUPERVISOR]");
    }
    lcd.setCursor(0,2); lcd.print("Session started");
    digitalWrite(GREEN_LED_PIN, HIGH);
    delay(1200);
    digitalWrite(GREEN_LED_PIN, LOW);

    inputBuffer = ""; currentProductCode = ""; currentProductIdx = -1;
    currentAction = 0; currentBoxColor = 0;
    boxQty = 0; pieceQty = 0; batchNo = "";
    selectedBatchIdx = -1; batchPage = 0;

    if (isSupervisor[w]) {
      currentState = STATE_SUPERVISOR_MENU;
      showSupervisorMenu();
    } else {
      currentState = STATE_ENTER_ID;
      promptProductID();
    }
    return;
  }

  switch (currentState) {

    case STATE_IDLE:
      if (key == 'D') handleUndo();
      break;

    case STATE_SUPERVISOR_MENU:
      if (key == '1') {
        currentState = STATE_ENTER_ID;
        promptProductID();
      } else if (key == '2') {
        adminViewStock();
      } else if (key == '3') {
        adminFlushQueue();
        showSupervisorMenu();
      } else if (key == '4') {
        adminViewQueue();
        showSupervisorMenu();
      } else if (key == '*') {
        currentWorker = -1;
        resetSession();
      }
      break;

    case STATE_ENTER_ID:
      if (key) {
        if (key == '#') {
          int idx = findProductIndex(inputBuffer);
          if (idx != -1) {
            currentProductCode = inputBuffer;
            currentProductIdx  = idx;
            currentState = STATE_CONFIRM_PRODUCT;
            showProductConfirm();
          } else {
            errorFlash("Invalid code!");
            inputBuffer = "";
            promptProductID();
          }
        } else if ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'D')) {
          if (inputBuffer.length() < 6) {
            inputBuffer += key;
            lcd.setCursor(0,1); lcd.print("                    ");
            lcd.setCursor(0,1); lcd.print(inputBuffer);
          }
        }
      }
      break;

    case STATE_CONFIRM_PRODUCT:
      if (key == '1') {
        currentState = STATE_SELECT_ACTION;
        promptAction();
      } else if (key == '2') {
        currentProductCode = "";
        currentProductIdx  = -1;
        inputBuffer = "";
        currentState = STATE_ENTER_ID;
        promptProductID();
      }
      break;

    case STATE_SELECT_ACTION:
      if (key >= '1' && key <= '3') {
        currentAction = key - '0';
        if (currentAction == 1) {
          currentState = STATE_ENTER_BATCH;
          inputBuffer = "";
          promptBatch();
        } else {
          if (countActiveBatches(currentProductIdx) == 0) {
            errorFlash("No batches in stock");
            currentState = STATE_SELECT_ACTION;
            promptAction();
          } else {
            batchPage = 0;
            currentState = STATE_SELECT_BATCH;
            showBatchSelector();
          }
        }
      }
      break;

    case STATE_ENTER_BATCH:
      if (key) {
        if (key == '#') {
          if (inputBuffer.length() == 0) {
            errorFlash("Batch required");
            inputBuffer = "";
            promptBatch();
          } else {
            batchNo = inputBuffer;
            int idx = findBatchIndex(currentProductIdx, batchNo);
            lastBatchWasNew = false;
            if (idx == -1) {
              idx = findFreeBatchSlot(currentProductIdx);
              if (idx == -1) {
                errorFlash("Batch list full!");
                inputBuffer = "";
                promptBatch();
                break;
              }
              strncpy(batches[currentProductIdx][idx].batchNo,
                      batchNo.c_str(), BATCH_NO_LEN - 1);
              batches[currentProductIdx][idx].batchNo[BATCH_NO_LEN - 1] = '\0';
              lastBatchWasNew = true;
            }
            selectedBatchIdx = idx;
            currentState = STATE_SELECT_BOX;
            promptBoxColor();
          }
        } else if ((key >= '0' && key <= '9') || (key >= 'A' && key <= 'D')) {
          if (inputBuffer.length() < BATCH_NO_LEN - 1) {
            inputBuffer += key;
            lcd.setCursor(0,1); lcd.print("                    ");
            lcd.setCursor(0,1); lcd.print(inputBuffer);
          }
        }
      }
      break;

    case STATE_SELECT_BATCH:
      if (key) {
        int active = countActiveBatches(currentProductIdx);
        int totalPages = (active + 5) / 6;
        if (totalPages < 1) totalPages = 1;

        if (key == 'A') {
          if (batchPage < totalPages - 1) batchPage++;
          showBatchSelector();
        } else if (key == 'B') {
          if (batchPage > 0) batchPage--;
          showBatchSelector();
        } else if (key >= '1' && key <= '6') {
          int slotOnPage = key - '1';
          int nth = batchPage * 6 + slotOnPage;
          if (nth < active) {
            selectedBatchIdx = nthActiveBatch(currentProductIdx, nth);
            batchNo = String(batches[currentProductIdx][selectedBatchIdx].batchNo);
            currentState = STATE_SHOW_BATCH_DETAIL;
            showBatchDetail();
          }
        }
      }
      break;

    case STATE_SHOW_BATCH_DETAIL:
      if (key) {
        currentState = STATE_ENTER_PIECES;
        inputBuffer = "";
        promptPieces();
      }
      break;

    case STATE_SELECT_BOX:
      if (key >= '1' && key <= '4') {
        currentBoxColor = key - '0';
        currentState = STATE_ENTER_BOX_QTY;
        inputBuffer = "";
        promptBoxQty();
      }
      break;

    case STATE_ENTER_BOX_QTY:
      if (key) {
        if (key == '#') {
          boxQty = inputBuffer.toInt();
          currentState = STATE_ENTER_PIECES;
          inputBuffer = "";
          promptPieces();
        } else if (key >= '0' && key <= '9') {
          inputBuffer += key;
          lcd.setCursor(0,1); lcd.print(inputBuffer);
        }
      }
      break;

    case STATE_ENTER_PIECES:
      if (key) {
        if (key == '#') {
          pieceQty = inputBuffer.toInt();
          if (currentAction == 2) {
            int have = batches[currentProductIdx][selectedBatchIdx].pieces;
            if (pieceQty <= 0 || pieceQty > have) {
              errorFlash("Not enough pcs!");
              inputBuffer = "";
              promptPieces();
              break;
            }
          }
          currentState = STATE_CONFIRM;
          showConfirmation();
        } else if (key >= '0' && key <= '9') {
          inputBuffer += key;
          lcd.setCursor(0,1); lcd.print(inputBuffer);
        }
      }
      break;

    case STATE_CONFIRM:
      if (key == '1') {
        saveTransaction();
      } else if (key == '2') {
        if (currentAction == 1) {
          if (lastBatchWasNew && selectedBatchIdx != -1) {
            batches[currentProductIdx][selectedBatchIdx].batchNo[0] = '\0';
          }
          currentState = STATE_ENTER_ID;
          inputBuffer = "";
          promptProductID();
        } else {
          currentState = STATE_SELECT_BATCH;
          batchPage = 0;
          showBatchSelector();
        }
      }
      break;

    case STATE_INVENTORY_SUMMARY:
      if (key) {
        digitalWrite(GREEN_LED_PIN, LOW);
        if (key == '*') {
          currentWorker = -1;
          resetSession();
        } else {
          currentState = STATE_ENTER_ID;
          inputBuffer = "";
          promptProductID();
        }
      }
      break;
  }
}

// ============================================================
//  UI SCREENS
// ============================================================
void showIdleScreen() {
  currentState = STATE_IDLE;
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Station Ready");
  lcd.setCursor(0,1); lcd.print("Tap card to start");
  lcd.setCursor(0,2);
  if (WiFi.status() == WL_CONNECTED) lcd.print("WiFi:OK");
  else lcd.print("WiFi:OFF");
  if (queueCount > 0) { lcd.print(" Q:"); lcd.print(queueCount); }
  lcd.setCursor(0,3); lcd.print("D=Undo last");
}

void promptProductID() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Enter Product Code:");
  lcd.setCursor(0,2); lcd.print(workerNames[currentWorker]);
  lcd.setCursor(0,3); lcd.print("#=OK");
  lcd.setCursor(12,3); lcd.print("*=Menu");
}

void showProductConfirm() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Is this correct?");
  lcd.setCursor(0,1); lcd.print(productNames[currentProductIdx].substring(0,20));
  lcd.setCursor(0,2); lcd.print(productSKUs[currentProductIdx].substring(0,20));
  lcd.setCursor(0,3); lcd.print("1=Yes  2=No,re-enter");
}

void promptAction() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("1.Store");
  lcd.setCursor(0,1); lcd.print("2.Ship");
  lcd.setCursor(0,2); lcd.print("3.Add Leftover");
  lcd.setCursor(0,3); lcd.print("*=Cancel");
}

void promptBatch() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Batch No. (required)");
  lcd.setCursor(0,2); lcd.print("Letters & digits OK");
  lcd.setCursor(0,3); lcd.print("Type then #");
}

void showBatchSelector() {
  int p = currentProductIdx;
  int active = countActiveBatches(p);
  int totalPages = (active + 5) / 6;
  if (totalPages < 1) totalPages = 1;
  if (batchPage >= totalPages) batchPage = totalPages - 1;

  lcd.clear();
  lcd.setCursor(0,0);
  lcd.print("Pick Batch p");
  lcd.print(batchPage + 1);
  lcd.print("/");
  lcd.print(totalPages);

  for (int row = 0; row < 3; row++) {
    for (int col = 0; col < 2; col++) {
      int slotOnPage = row * 2 + col;
      int nth = batchPage * 6 + slotOnPage;
      if (nth < active) {
        int bIdx = nthActiveBatch(p, nth);
        String label = String(slotOnPage + 1) + "." + String(batches[p][bIdx].batchNo);
        while (label.length() < 10) label += " ";
        if (label.length() > 10) label = label.substring(0, 10);
        if (col == 0) lcd.setCursor(0, row + 1);
        else          lcd.setCursor(10, row + 1);
        lcd.print(label);
      }
    }
  }
}

void showBatchDetail() {
  int p = currentProductIdx;
  int b = selectedBatchIdx;
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Batch ");
  lcd.print(batches[p][b].batchNo);
  lcd.setCursor(0,1);
  lcd.print("R:" + String(batches[p][b].boxes[1]) +
            " B:" + String(batches[p][b].boxes[2]) +
            " G:" + String(batches[p][b].boxes[3]) +
            " Y:" + String(batches[p][b].boxes[4]));
  lcd.setCursor(0,2); lcd.print("TOT:" + String(batches[p][b].pieces) + " pcs");
  lcd.setCursor(0,3); lcd.print("Press any key ->");
}

void promptBoxColor() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Box Color?");
  lcd.setCursor(0,1); lcd.print("1.Red    2.Blue");
  lcd.setCursor(0,2); lcd.print("3.Green  4.Yellow");
}

void promptBoxQty() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("How many boxes?");
  lcd.setCursor(0,3); lcd.print("Type number, then #");
}

void promptPieces() {
  lcd.clear();
  lcd.setCursor(0,0);
  if (currentAction == 1) lcd.print("Total pieces?");
  else if (currentAction == 2) lcd.print("How many to ship?");
  else lcd.print("Leftover pieces?");
  lcd.setCursor(0,3); lcd.print("Type number, then #");
}

void showConfirmation() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print(productSKUs[currentProductIdx].substring(0,20));
  lcd.setCursor(0,1);
  if (currentAction == 1)
    lcd.print("Bx:" + String(boxQty) + " Pcs:" + String(pieceQty));
  else if (currentAction == 2)
    lcd.print("Ship " + String(pieceQty) + " pcs");
  else
    lcd.print("Leftover +" + String(pieceQty));
  lcd.setCursor(0,2);
  lcd.print("Batch:" + batchNo);
  lcd.setCursor(0,3);
  if (currentAction == 1) lcd.print("1.Save  2.Cancel");
  else                    lcd.print("1.Save  2.Re-pick");
}

// ============================================================
//  SUPERVISOR MENU
// ============================================================
void showSupervisorMenu() {
  currentState = STATE_SUPERVISOR_MENU;
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("== ADMIN PANEL ==");
  lcd.setCursor(0,1); lcd.print("1.Work  2.View Stock");
  lcd.setCursor(0,2); lcd.print("3.Sync Queue(");
  lcd.print(queueCount);
  lcd.print(")");
  lcd.setCursor(0,3); lcd.print("4.Queue Info  *=Exit");
}

void adminViewStock() {
  int stockList[MAX_PRODUCTS];
  int stockCount = 0;
  for (int i = 0; i < NUM_PRODUCTS; i++) {
    if (countActiveBatches(i) > 0) stockList[stockCount++] = i;
  }

  if (stockCount == 0) {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("No stock recorded");
    lcd.setCursor(0,3); lcd.print("Press any key...");
    while (!keypad.getKey()) delay(10);
    showSupervisorMenu();
    return;
  }

  int viewIdx = 0;
  while (true) {
    int p = stockList[viewIdx];
    lcd.clear();
    lcd.setCursor(0,0); lcd.print(productNames[p].substring(0,17));
    String pageInfo = String(viewIdx+1) + "/" + String(stockCount);
    lcd.setCursor(20 - pageInfo.length(), 0);
    lcd.print(pageInfo);
    lcd.setCursor(0,1);
    lcd.print("R:" + String(totalProductBoxes(p,1)) +
              " B:" + String(totalProductBoxes(p,2)) +
              " G:" + String(totalProductBoxes(p,3)) +
              " Y:" + String(totalProductBoxes(p,4)));
    lcd.setCursor(0,2);
    lcd.print("Btch:" + String(countActiveBatches(p)) +
              " Tot:" + String(totalProductPieces(p)));
    lcd.setCursor(0,3); lcd.print("A=Prev B=Next *=Back");

    while (true) {
      adminServer.handleClient();
      char k = keypad.getKey();
      if (k == 'B' || k == '#') {
        viewIdx = (viewIdx + 1) % stockCount;
        break;
      } else if (k == 'A') {
        viewIdx = (viewIdx - 1 + stockCount) % stockCount;
        break;
      } else if (k == '*') {
        showSupervisorMenu();
        return;
      }
    }
  }
}

void adminFlushQueue() {
  if (queueCount == 0) {
    lcd.clear(); lcd.print("Queue is empty!");
    delay(1200);
    return;
  }
  if (WiFi.status() != WL_CONNECTED) {
    lcd.clear(); lcd.print("WiFi not connected!");
    delay(1200);
    return;
  }
  lcd.clear(); lcd.print("Flushing queue...");
  flushQueue();
  lcd.init(); lcd.backlight();
  lcd.clear();
  if (queueCount == 0) {
    lcd.print("All synced!");
    digitalWrite(GREEN_LED_PIN, HIGH);
    delay(1500);
    digitalWrite(GREEN_LED_PIN, LOW);
  } else {
    lcd.print("Failed: " + String(queueCount) + " left");
    delay(1500);
  }
}

void adminViewQueue() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Offline Queue");
  lcd.setCursor(0,1); lcd.print("Pending: " + String(queueCount));
  lcd.setCursor(0,2);
  if (WiFi.status() == WL_CONNECTED) lcd.print("WiFi: Connected");
  else lcd.print("WiFi: Disconnected");
  lcd.setCursor(0,3); lcd.print("Press any key...");
  while (!keypad.getKey()) delay(10);
}

// ============================================================
//  SAVE TRANSACTION
// ============================================================
// ============================================================
//  SAVE TRANSACTION
// ============================================================
void saveTransaction() {
  int p = currentProductIdx;
  int b = selectedBatchIdx;

  if (currentAction == 1) {
    batches[p][b].boxes[currentBoxColor] += boxQty;
    batches[p][b].pieces += pieceQty;
  } else if (currentAction == 2) {
    batches[p][b].pieces -= pieceQty;
    if (batches[p][b].pieces < 0) batches[p][b].pieces = 0;
    // If batch is now empty, clear all box counts for this batch
    if (batches[p][b].pieces == 0) {
      for (int c = 0; c < 5; c++) batches[p][b].boxes[c] = 0;
    }
  } else if (currentAction == 3) {
    batches[p][b].pieces += pieceQty;
  }

  lastPIdx       = p;
  lastAction     = currentAction;
  lastBoxColor   = currentBoxColor;
  lastBoxQty     = boxQty;
  lastPieceQty   = pieceQty;
  lastBatchIdx   = b;
  lastWorkerName = workerNames[currentWorker];
  lastBatch      = batchNo;
  lastTransaction = productSKUs[p] + " " + actionName(currentAction);
  if (currentAction != 1) lastBatchWasNew = false;

  int totalQty = totalProductPieces(p);

  Serial.print("TXN | worker="); Serial.print(workerNames[currentWorker]);
  Serial.print(" | code=");      Serial.print(currentProductCode);
  Serial.print(" | sku=");       Serial.print(productSKUs[p]);
  Serial.print(" | action=");    Serial.print(actionName(currentAction));
  Serial.print(" | box=");       Serial.print(boxColorName(currentBoxColor));
  Serial.print(" | boxQty=");    Serial.print(boxQty);
  Serial.print(" | pcs=");       Serial.print(pieceQty);
  Serial.print(" | batch=");     Serial.print(batchNo);
  Serial.print(" | total=");     Serial.println(totalQty);

  String payload = "{";
  payload += "\"productID\":\"" + productSKUs[p] + "\",";
  payload += "\"productName\":\"" + productNames[p] + "\",";
  payload += "\"condition\":\"" + actionName(currentAction) + "\",";
  payload += "\"boxType\":\"" + (currentAction == 1 ? boxColorName(currentBoxColor) : String("-")) + "\",";
  payload += "\"noOfBoxes\":" + String(currentAction == 1 ? boxQty : 0) + ",";
  payload += "\"noOfPieces\":" + String(pieceQty) + ",";
  payload += "\"totalQty\":" + String(totalQty) + ",";
  payload += "\"patchNo\":\"" + batchNo + "\",";
  payload += "\"workerName\":\"" + workerNames[currentWorker] + "\"";
  payload += "}";

  bool sent = false;
  if (WiFi.status() == WL_CONNECTED) {
    lcd.clear();
    lcd.setCursor(0,0); lcd.print("Saving...");
    sent = sendToSheet(payload);
    lcd.init(); lcd.backlight();
  }

  if (!sent) {
    queueTransaction(payload);
  }

  cleanupEmptyBatches(p);
  saveBatchState();  // single save, after all changes are finalized

  digitalWrite(GREEN_LED_PIN, HIGH);
  currentState = STATE_INVENTORY_SUMMARY;
  showInventorySummary(p);
}
void showInventorySummary(int p) {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print(productNames[p].substring(0,20));
  lcd.setCursor(0,1);
  lcd.print("R:" + String(totalProductBoxes(p,1)) +
            " B:" + String(totalProductBoxes(p,2)) +
            " G:" + String(totalProductBoxes(p,3)) +
            " Y:" + String(totalProductBoxes(p,4)));
  lcd.setCursor(0,2);
  lcd.print("Batches:" + String(countActiveBatches(p)));
  lcd.setCursor(0,3);
  lcd.print("TOT:" + String(totalProductPieces(p)));
  lcd.setCursor(12,3); lcd.print("*=Menu");
}

// ============================================================
//  ERROR FLASH
// ============================================================
void errorFlash(String msg) {
  digitalWrite(RED_LED_PIN, HIGH);
  lcd.clear();
  lcd.setCursor(0,0); lcd.print(msg);
  lcd.setCursor(0,2); lcd.print("Press any key...");
  while (!keypad.getKey()) delay(10);
  digitalWrite(RED_LED_PIN, LOW);
}

// ============================================================
//  UNDO
// ============================================================
void handleUndo() {
  lcd.clear();
  lcd.setCursor(0,0); lcd.print("Last:");
  lcd.setCursor(0,1); lcd.print(lastTransaction.substring(0,20));
  lcd.setCursor(0,2); lcd.print("By: " + lastWorkerName);
  lcd.setCursor(0,3); lcd.print("1=Reverse *=Cancel");

  while (true) {
    char k = keypad.getKey();
    if (k == '1') {
      if (lastPIdx != -1 && lastBatchIdx != -1) {
        int p = lastPIdx;
        int b = lastBatchIdx;

        // Reverse the local state
        if (lastAction == 1) {
          batches[p][b].boxes[lastBoxColor] -= lastBoxQty;
          batches[p][b].pieces -= lastPieceQty;
          if (batches[p][b].boxes[lastBoxColor] < 0) batches[p][b].boxes[lastBoxColor] = 0;
          if (batches[p][b].pieces < 0) batches[p][b].pieces = 0;
          if (lastBatchWasNew) {
            batches[p][b].batchNo[0] = '\0';
            for (int c = 0; c < 5; c++) batches[p][b].boxes[c] = 0;
            batches[p][b].pieces = 0;
          }
        } else if (lastAction == 2) {
          batches[p][b].pieces += lastPieceQty;
        } else if (lastAction == 3) {
          batches[p][b].pieces -= lastPieceQty;
          if (batches[p][b].pieces < 0) batches[p][b].pieces = 0;
        }
        cleanupEmptyBatches(p);

        // Build UNDO payload — negative quantities + "UNDO X" label
        int newTotalQty = totalProductPieces(p);
        String undoCondition = "UNDO " + actionName(lastAction);

        String payload = "{";
        payload += "\"productID\":\"" + productSKUs[p] + "\",";
        payload += "\"productName\":\"" + productNames[p] + "\",";
        payload += "\"condition\":\"" + undoCondition + "\",";
        payload += "\"boxType\":\"" + (lastAction == 1 ? boxColorName(lastBoxColor) : String("-")) + "\",";
        payload += "\"noOfBoxes\":" + String(lastAction == 1 ? -lastBoxQty : 0) + ",";
        payload += "\"noOfPieces\":" + String(lastAction == 2 ? lastPieceQty : -lastPieceQty) + ",";
        payload += "\"totalQty\":" + String(newTotalQty) + ",";
        payload += "\"patchNo\":\"" + lastBatch + "\",";
        payload += "\"workerName\":\"" + lastWorkerName + "\"";
        payload += "}";

        Serial.print("UNDO | sending: "); Serial.println(payload);

        // Try to send; queue offline if it fails
        bool sent = false;
        if (WiFi.status() == WL_CONNECTED) {
          lcd.clear();
          lcd.setCursor(0,0); lcd.print("Reversing...");
          sent = sendToSheet(payload);
          lcd.init(); lcd.backlight();
        }
        if (!sent) {
          queueTransaction(payload);
        }

        // Persist the reverted state
        saveBatchState();

        lastPIdx = -1;
        lastBatchIdx = -1;
        Serial.println("UNDO | reversed");
      }
      lcd.clear(); lcd.print("Reversed!");
      digitalWrite(GREEN_LED_PIN, HIGH);
      delay(1500);
      digitalWrite(GREEN_LED_PIN, LOW);
      lastTransaction = "None";
      break;
    } else if (k == '*') break;
  }
  showIdleScreen();
}
// ============================================================
//  SESSION RESET
// ============================================================
void resetSession() {
  inputBuffer = "";
  currentProductCode = "";
  currentProductIdx  = -1;
  currentAction  = 0;
  currentBoxColor = 0;
  boxQty  = 0;
  pieceQty = 0;
  batchNo  = "";
  selectedBatchIdx = -1;
  batchPage = 0;
  showIdleScreen();
}

// ============================================================
//  LOOKUP + BATCH HELPERS
// ============================================================
int findProductIndex(String code) {
  code.toUpperCase();
  for (int i = 0; i < NUM_PRODUCTS; i++) {
    if (productCodes[i] == code) return i;
  }
  return -1;
}

int findWorkerIndex(byte* uid, byte size) {
  for (int i = 0; i < NUM_WORKERS; i++) {
    if (workerUIDSizes[i] != size) continue;
    bool ok = true;
    for (byte j = 0; j < size; j++) {
      if (workerUIDs[i][j] != uid[j]) { ok = false; break; }
    }
    if (ok) return i;
  }
  return -1;
}

int findBatchIndex(int p, String bn) {
  if (bn.length() == 0) return -1;
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] != '\0' &&
        bn.equals(String(batches[p][i].batchNo))) return i;
  }
  return -1;
}

int findFreeBatchSlot(int p) {
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] == '\0') return i;
  }
  return -1;
}

int countActiveBatches(int p) {
  int n = 0;
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] != '\0') n++;
  }
  return n;
}

int nthActiveBatch(int p, int n) {
  int count = 0;
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] != '\0') {
      if (count == n) return i;
      count++;
    }
  }
  return -1;
}

int totalProductPieces(int p) {
  int total = 0;
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] != '\0') total += batches[p][i].pieces;
  }
  return total;
}

int totalProductBoxes(int p, int color) {
  int total = 0;
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] != '\0') total += batches[p][i].boxes[color];
  }
  return total;
}

void cleanupEmptyBatches(int p) {
  for (int i = 0; i < MAX_BATCHES; i++) {
    if (batches[p][i].batchNo[0] == '\0') continue;
    int totalBoxes = 0;
    for (int c = 1; c <= 4; c++) totalBoxes += batches[p][i].boxes[c];
    if (totalBoxes == 0 && batches[p][i].pieces == 0) {
      batches[p][i].batchNo[0] = '\0';
    }
  }
}

String boxColorName(int c) {
  switch (c) {
    case 1: return "Red";    case 2: return "Blue";
    case 3: return "Green";  case 4: return "Yellow";
    default: return "-";
  }
}

String actionName(int a) {
  switch (a) {
    case 1: return "Storage";
    case 2: return "Shipping";
    case 3: return "Add Leftover";
    default: return "-";
  }
}
├── circuit.png                # Proteus schematic
<img width="1512" height="808" alt="image" src="https://github.com/user-attachments/assets/1d1edde3-8031-4a0a-829c-09b0744a5b7c" />
├── sheets.png                 # Google Sheets screenshot
<img width="1512" height="808" alt="image" src="https://github.com/user-attachments/assets/8890da8a-645f-4566-af64-cd5b2d05cabf" />

└── enclosure.png              # 3D enclosure CAD render
<img width="1197" height="658" alt="image" src="https://github.com/user-attachments/assets/02d85df0-8571-4c31-b224-f3101b5bfddb" />

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
