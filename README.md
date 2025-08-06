# ISABELLE: Offline Vision Assistant for the Blind

**Built for the Google - Gemma 3n Impact Challenge 2025**

---

## 📌 Project Overview

ISABELLE is a voice-activated AI assistant for the visually impaired. Activated by saying:

> “Isabelle, what is in front?”

It captures the scene, runs the **Gemma 3n E4B-it-int4** LLM via MediaPipe Tasks entirely on-device, and speaks out a description using built-in TTS—all **offline** and **private**.

---

## ✅ Key Feature

- 🎯 Real-time object/scene description (“what is in front?”)
- ✅ Tested live with a blind individual at a local NGO
- ✅ Runs fully offline on **Google Pixel 8 Pro**

---

## 🏗️ Technical Architecture

- **Frontend**: Flutter (`main.dart`, `camera_service.dart`)
- **Android Native**: Kotlin (`Gemma3nProcessor.kt`) using MediaPipe Tasks
- **Model**: `Gemma_3n_E4B-it-int4.task` (hosted on GCS, not included in repo)
- **TTS**: Offline Text-to-Speech
- **Privacy**: No network calls, telemetry disabled

---

## 🧠 Prompt Logic

Prompt template sent to the model:

> You are ISABELLE, a blind-assistive AI assistant running on a phone. Briefly describe what is in front of the user based on the image.

---

## 📦 Installation

To build the app:

```bash
flutter pub get
flutter build apk --release
