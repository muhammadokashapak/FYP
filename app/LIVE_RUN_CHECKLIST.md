╔════════════════════════════════════════════════════════════════════════════════╗
║                     LIVE RUN CHECKLIST & INSTRUCTIONS                         ║
║                    Smart Glasses ESP32-CAM Real-Time Detection                 ║
╚════════════════════════════════════════════════════════════════════════════════╝

═══════════════════════════════════════════════════════════════════════════════════
1. PUBSPEC.YAML & DEPENDENCIES STATUS ✓
═══════════════════════════════════════════════════════════════════════════════════

Location: D:\FYP\Projects\smart_glasses\pubspec.yaml

✓ All required packages CONFIRMED PRESENT:
  • tflite_flutter: ^0.12.1      ← Real TFLite inference
  • flutter_tts: ^4.2.5           ← Voice feedback
  • http: ^1.1.0                  ← ESP32 stream connection
  • image: ^3.3.0                 ← Image decoding & resizing
  • provider: ^6.1.2              ← State management
  • permission_handler: ^11.3.1   ← Runtime permissions
  • camera: ^0.11.0+2             ← Local camera (optional)

✓ Assets configured in pubspec.yaml:
    flutter:
      uses-material-design: true
      assets:
        - assets/model/best_int8.tflite
        - assets/model/labels.txt

✓ No version conflicts detected.

═══════════════════════════════════════════════════════════════════════════════════
2. ANDROID PERMISSIONS & CLEARTEXT TRAFFIC ✓
═══════════════════════════════════════════════════════════════════════════════════

Location: D:\FYP\Projects\smart_glasses\android\app\src\main\AndroidManifest.xml

✓ ALREADY CONFIGURED - NO CHANGES NEEDED

Verified present in manifest:
  <uses-permission android:name="android.permission.INTERNET" />
  <application ... android:usesCleartextTraffic="true">

→ This allows HTTP (non-HTTPS) connections to ESP32-CAM
→ Required because ESP32 does not support HTTPS

═══════════════════════════════════════════════════════════════════════════════════
3. ASSET PATH VERIFICATION ✓
═══════════════════════════════════════════════════════════════════════════════════

CONFIRMED FILES PRESENT:
  ✓ D:\FYP\Projects\smart_glasses\assets\model\best_int8.tflite    (280 KB approx)
  ✓ D:\FYP\Projects\smart_glasses\assets\model\labels.txt            (5 lines)

PATH IN CODE:
  Location: lib/services/inference_service.dart, line 41
  Code: static const String _modelPath = 'assets/model/best_int8.tflite';
  Code: static const String _labelsPath = 'assets/model/labels.txt';

NO CHANGES NEEDED - Asset paths match pubspec.yaml configuration.

═══════════════════════════════════════════════════════════════════════════════════
4. ESP32-CAM IP ADDRESS INJECTION ✓
═══════════════════════════════════════════════════════════════════════════════════

LOCATION: lib/core/constants/app_constants.dart (lines 24-30)

✓ ALREADY UPDATED TO YOUR IP:
  static const String ip = '192.168.137.176';
  static const String streamUrl = 'http://192.168.137.176/stream';
  static const String baseUrl = 'http://192.168.137.176';
  static const String captureUrl = 'http://192.168.137.176/capture';

ALSO USED IN:
  → lib/features/camera/camera_screen.dart (line 24): _streamUrl = ESP32Config.streamUrl

TO CHANGE IP FOR NEXT TEST:
  → Edit line 24 in app_constants.dart to your new IP
  → OR use the settings dialog in the app (FAB button)

═══════════════════════════════════════════════════════════════════════════════════
5. TENSOR SHAPE VALIDATION LOGIC ✓
═══════════════════════════════════════════════════════════════════════════════════

Location: lib/services/inference_service.dart, lines 125-166

✓ ENHANCED LOGGING ADDED

When first frame is processed, console will show:

  [InferenceIsolate] ========== TENSOR SHAPE VALIDATION ==========
  [InferenceIsolate] Model: assets/model/best_int8.tflite
  [InferenceIsolate] Input Shape: [1, H, W, 3]
  [InferenceIsolate] === INPUT TENSORS (1) ===
  [InferenceIsolate] Input[0]: name="input_1", shape=[1, 320, 240, 3], type=TensorType.uint8
  [InferenceIsolate] === OUTPUT TENSORS (4) ===
  [InferenceIsolate] Output[0]: name="output_0", shape=[1, 100, 4], type=TensorType.float32
  [InferenceIsolate] Output[1]: name="output_1", shape=[1, 100], type=TensorType.float32
  [InferenceIsolate] Output[2]: name="output_2", shape=[1, 100], type=TensorType.float32
  [InferenceIsolate] Output[3]: name="output_3", shape=[1], type=TensorType.float32
  [InferenceIsolate] ASSUMPTION: Standard SSD format with 4 outputs:
    [0] boxes     [1, N, 4]  (normalized: top, left, bottom, right)
    [1] classes   [1, N]     (class indices as float)
    [2] scores    [1, N]     (confidence scores)
    [3] count     [1]        (number of detections)

IMPORTANT: If output shapes differ from above, screenshot and send me the exact shapes.
This tells us if the parsing logic in _parseDetections() needs adjustment.

═══════════════════════════════════════════════════════════════════════════════════
6. DEBUG & RUN PROTOCOL
═══════════════════════════════════════════════════════════════════════════════════

STEP 1: Install dependencies
  $ cd D:\FYP\Projects\smart_glasses
  $ flutter clean
  $ flutter pub get

STEP 2: Verify your device is connected
  $ flutter devices
  (Should show your Android/iOS device or emulator)

STEP 3: Run in DEBUG mode with VERBOSE logging
  $ flutter run -v 2>&1 | tee run.log

  This will:
    ✓ Capture all console output to run.log
    ✓ Show detailed TensorFlow/MJPEG logs
    ✓ Display Flutter build messages
    ✓ Show app initialization sequence

STEP 4: Watch the console for these key messages (in order):

  [InferenceService] Loading TFLite model from assets/model/best_int8.tflite
  [InferenceService] Model initialized successfully
  [InferenceService] === INPUT TENSORS ===
  [InferenceService] === OUTPUT TENSORS ===
  [MjpegStreamService] Connected successfully. Streaming frames...
  [MjpegStreamService] Emitted frame (XXXX bytes)
  [InferenceIsolate] ========== TENSOR SHAPE VALIDATION ==========

STEP 5: On device, allow INTERNET permission (if prompted)

STEP 6: Tap the settings FAB (gear icon) and verify stream URL is:
  http://192.168.137.52/stream

═══════════════════════════════════════════════════════════════════════════════════
7. IP CONNECTIVITY TEST (BEFORE RUNNING APP)
═══════════════════════════════════════════════════════════════════════════════════

Verify your ESP32 is reachable from PC:

  $ ping 192.168.137.52
    (Should see: "Reply from 192.168.137.52: bytes=32 time=XX ms")

Verify the MJPEG stream is active:

  $ curl http://192.168.137.52/stream -v
    (Should show: "HTTP/1.1 200 OK" + JPEG data)

If ping fails:
  → Check WiFi connection on both PC and ESP32
  → Verify they're on the same WiFi network
  → Check ESP32 IP using Serial Monitor

If curl shows 404:
  → ESP32 firmware may need different stream endpoint
  → Try: http://192.168.137.52:81/stream (port 81)
  → Or: http://192.168.137.52/mjpeg (different endpoint)

═══════════════════════════════════════════════════════════════════════════════════
8. EXPECTED BEHAVIOR DURING FIRST RUN
═══════════════════════════════════════════════════════════════════════════════════

Timeline (after app launches):

  0-2s:   App initialization
          - "Initializing services..." message shows
          - TFLite model loads
          - Inference service ready

  2-5s:   MJPEG connection attempt
          - "Connecting to stream..." 
          - First frame bytes received
          - Status changes to "● Live"
          - FPS counter starts (should show 1-8 fps)

  5-8s:   First inference
          - Frame appears on screen (may be black while decoding)
          - Every 3rd frame runs inference
          - If object in frame: bounding box appears
          - TTS speaks announcement (if device has speakers)

  9s+:    Continuous streaming
          - Live detection updates
          - Bounding boxes update as objects move
          - Bottom panel shows detected objects
          - Total detection count increments

═══════════════════════════════════════════════════════════════════════════════════
9. TROUBLESHOOTING QUICK REFERENCE
═══════════════════════════════════════════════════════════════════════════════════

SYMPTOM: "File Not Found" error
  → Cause: Assets not found
  → Fix: Run `flutter clean && flutter pub get`
  → Verify: assets/model/ files exist

SYMPTOM: App crashes on startup
  → Cause: TFLite model is corrupted
  → Fix: Re-download best_int8.tflite from your training output
  → Check: File size should be 280+ KB

SYMPTOM: Stream shows "Offline" (red indicator)
  → Cause: Cannot reach ESP32
  → Fix: Verify IP address (ping 192.168.137.52)
  → Check: Both devices on same WiFi
  → Try: Change URL in app settings (FAB)

SYMPTOM: Bounding boxes don't appear
  → Cause: Output tensor format differs from SSD assumption
  → Fix: Check console for "TENSOR SHAPE VALIDATION" logs
  → Send: Screenshot of actual tensor shapes
  → We'll: Update _parseDetections() parsing logic

SYMPTOM: No voice output
  → Cause: Device mute, TTS not initialized, or no detections
  → Check: Device unmuted + volume up
  → Check: Bottom panel shows "Detected objects:"
  → Check: Console shows "[TtsService] Speaking: ..."

SYMPTOM: High CPU/lag
  → Cause: Inference running every frame (not every 3rd)
  → Check: Detection Provider line 159 has % 3 check
  → Fix: Increase frame skip ratio if needed

═══════════════════════════════════════════════════════════════════════════════════
10. FILE LOCATIONS SUMMARY
═══════════════════════════════════════════════════════════════════════════════════

Key files you may need to modify:

IP Address & Stream Config:
  → D:\FYP\Projects\smart_glasses\lib\core\constants\app_constants.dart (line 24)

Tensor Parsing Logic:
  → D:\FYP\Projects\smart_glasses\lib\services\inference_service.dart (line 225)
     (_parseDetections function)

Confidence Threshold:
  → D:\FYP\Projects\smart_glasses\lib\services\inference_service.dart (line 40)
     (_confidenceThreshold = 0.50) — Change to 0.60 if too many false positives

FPS & Frame Throttle:
  → D:\FYP\Projects\smart_glasses\lib\services\mjpeg_stream_service.dart (line 13)
     (maxFps = 8) — Change to 4 if CPU is overloaded

Detection Inference Interval:
  → D:\FYP\Projects\smart_glasses\lib\providers/detection_provider.dart (line 159)
     (% 3 means every 3rd frame) — Change to % 1 for real-time, % 5 for slow phones

Distance Focal Length (camera calibration):
  → D:\FYP\Projects\smart_glasses\lib\services/distance_estimator.dart (line 12)
     (focalLengthPx = 280.0) — Adjust based on calibration

═══════════════════════════════════════════════════════════════════════════════════
11. READY TO LAUNCH?
═══════════════════════════════════════════════════════════════════════════════════

PRE-RUN CHECKLIST:

  ☐ Device connected via USB cable (or emulator running)
  ☐ flutter devices shows your target device
  ☐ ESP32-CAM powered on and WiFi connected
  ☐ PC on same WiFi as ESP32
  ☐ Verified: ping 192.168.137.52 works
  ☐ Verified: curl http://192.168.137.52/stream shows JPEG data
  ☐ android/app/src/main/AndroidManifest.xml has usesCleartextTraffic=true
  ☐ assets/model/best_int8.tflite exists (280+ KB)
  ☐ assets/model/labels.txt exists (5 classes)
  ☐ All .dart files compile (flutter analyze returns no errors)

READY? Run:
  $ flutter run -v

After app starts, wait 10 seconds for initialization and watch console.

═══════════════════════════════════════════════════════════════════════════════════

STAY READY TO HELP:
  If bounding boxes don't appear or voice doesn't trigger, I'm ready to:
    → Adjust tensor parsing logic
    → Re-calibrate focal length
    → Troubleshoot MJPEG stream issues
    → Debug confidence thresholds
    → Check label mismatches

Just send:
  1. Screenshot of tensor validation log output
  2. Screenshot of app screen (what do you see?)
  3. Console log (flutter run -v output)
  4. Exact error messages (if any)

Good luck! 🚀
