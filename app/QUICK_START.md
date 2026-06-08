════════════════════════════════════════════════════════════════════════════════
                          QUICK START - LIVE RUN
════════════════════════════════════════════════════════════════════════════════

📋 PRE-RUN (5 MINUTES)

1. Ping ESP32:
   $ ping 192.168.137.176
   
2. Verify MJPEG stream:
   $ curl http://192.168.137.176/stream -v

3. Clean & build:
   $ flutter clean && flutter pub get

🚀 LAUNCH (RUN THIS)

   $ flutter run -v

✅ WHAT TO EXPECT

Timeline:
  0-3s:   App loads, TFLite model initializes
  3-6s:   MJPEG connects to ESP32
  6-8s:   First frame appears on screen
  8-12s:  First detection runs, bounding box appears

Console messages to watch for:
  ✓ [InferenceService] Model initialized successfully
  ✓ [MjpegStreamService] Connected successfully
  ✓ [InferenceIsolate] ========== TENSOR SHAPE VALIDATION =========
  ✓ [TtsService] Speaking: [object] detected

UI indicators:
  ✓ Status shows "● Live" (green dot)
  ✓ FPS counter shows 1-8
  ✓ Bounding boxes appear with confidence %
  ✓ Voice announces detection (if device unmuted)

════════════════════════════════════════════════════════════════════════════════
                          CRITICAL FILE LOCATIONS
════════════════════════════════════════════════════════════════════════════════

IP ADDRESS:
  → lib/core/constants/app_constants.dart, line 24
  → Currently set to: 192.168.137.176 ✓

TENSOR LOGGING:
  → lib/services/inference_service.dart, lines 125-166
  → Will print actual output shapes on first inference

ASSET PATHS:
  → assets/model/best_int8.tflite ✓ (confirmed present)
  → assets/model/labels.txt ✓ (confirmed present)

ANDROID PERMISSIONS:
  → android/app/src/main/AndroidManifest.xml
  → usesCleartextTraffic=true ✓ (already set for HTTP)
  → INTERNET permission ✓ (already present)

════════════════════════════════════════════════════════════════════════════════
                          TENSOR VALIDATION OUTPUT
════════════════════════════════════════════════════════════════════════════════

When first frame processes, console shows (example):

  [InferenceIsolate] ========== TENSOR SHAPE VALIDATION ==========
  [InferenceIsolate] Model: assets/model/best_int8.tflite
  [InferenceIsolate] Input Shape: [1, 320, 240, 3]
  [InferenceIsolate] === INPUT TENSORS (1) ===
  [InferenceIsolate] Input[0]: name="input_1", shape=[1, 320, 240, 3], type=TensorType.uint8
  [InferenceIsolate] === OUTPUT TENSORS (4) ===
  [InferenceIsolate] Output[0]: name="output_0", shape=[1, 100, 4], type=TensorType.float32
  [InferenceIsolate] Output[1]: name="output_1", shape=[1, 100], type=TensorType.float32
  [InferenceIsolate] Output[2]: name="output_2", shape=[1, 100], type=TensorType.float32
  [InferenceIsolate] Output[3]: name="output_3", shape=[1], type=TensorType.float32
  [InferenceIsolate] ASSUMPTION: Standard SSD format...

EXPECTED:
  ✓ Input tensor is [1, H, W, 3] with type TensorType.uint8 (INT8)
  ✓ 4 output tensors (boxes, classes, scores, count)

IF DIFFERENT: Send me the screenshot, I'll adjust parsing.

════════════════════════════════════════════════════════════════════════════════
                          TROUBLESHOOTING (1-MINUTE FIXES)
════════════════════════════════════════════════════════════════════════════════

"File Not Found" error
  → flutter clean && flutter pub get

App crashes on startup
  → Check if best_int8.tflite is > 200 KB
  → Re-download model if corrupted

Stream shows "Offline"
  → ping 192.168.137.176 (should respond)
  → Check WiFi: both on same network?
  → Try changing IP in app (FAB settings)

No bounding boxes appearing
  → Check console for tensor shapes
  → If shapes differ from assumption, tell me
  → May need to adjust _parseDetections() function

No voice output
  → Device unmuted + volume up?
  → Console should show "[TtsService] Speaking: ..."
  → Check if detections are actually found (bottom panel)

════════════════════════════════════════════════════════════════════════════════
                          CONTACT POINTS
════════════════════════════════════════════════════════════════════════════════

If something breaks:

1. Send console log:
   $ flutter run -v 2>&1 > run.log
   (Then attach run.log)

2. Tell me:
   ✓ What do you see on screen?
   ✓ Any error messages?
   ✓ What does "● Live" say?
   ✓ Console: does inference print tensor shapes?

3. I'll adjust:
   ✓ Tensor parsing logic
   ✓ IP address or endpoint
   ✓ Confidence threshold
   ✓ Frame rate / FPS

════════════════════════════════════════════════════════════════════════════════

READY? → $ flutter run -v

Then watch for the tensor validation message. That's your green light. 🟢
