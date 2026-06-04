<h1 align="center">🧠 CHASHM AI — Smart Assistive Headset</h1>

<p align="center">
  <b>AI-powered real-time object detection system with voice feedback for assistive vision</b><br>
  <i>Empowering visually impaired individuals through intelligent perception</i>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/AI-Computer%20Vision-blue?style=for-the-badge">
  <img src="https://img.shields.io/badge/Model-YOLO-green?style=for-the-badge">
  <img src="https://img.shields.io/badge/Backend-FastAPI-black?style=for-the-badge">
  <img src="https://img.shields.io/badge/Hardware-ESP32--CAM-orange?style=for-the-badge">
</p>

---

## 🚀 Overview

**CHASHM AI** is a full-stack intelligent assistive system designed to help visually impaired users perceive their surroundings in real-time.

By combining **embedded hardware**, **deep learning**, and **real-time communication**, the system detects objects from a live camera feed and converts them into **audible feedback**, enabling users to navigate the world more independently.

---

## ✨ Key Highlights

- 🎯 **Real-Time Object Detection** using custom-trained YOLO model (.tflite)  
- 📷 **Live Video Streaming** via ESP32-CAM  
- ⚡ **High-Performance Backend** with FastAPI + OpenCV  
- 🌐 **Real-Time UI Updates** using WebSockets  
- 🔊 **Voice Feedback System** with Text-to-Speech  
- 🚀 **Optimized Inference** using INT8 quantization for low latency  

---

## 🏗️ System Architecture

```text
ESP32-CAM → FastAPI Backend → YOLO Model → Detection Output
                                      ↓
                           Text-to-Speech Engine
                                      ↓
                              Audio Feedback
                                      ↓
                          Real-Time Web Interface
