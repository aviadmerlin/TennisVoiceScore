# TennisVoiceScore 🎾

A hands-free iOS tennis score tracker controlled entirely by voice commands — no tapping required during the match.

## The Problem

When playing tennis, keeping track of the score mid-game means stopping, arguing, or fumbling with your phone. I couldn't find an app that handled this fully hands-free, so I built one.

## How It Works

Each player wears an earbud. When a point is scored, just say:

- **Hebrew:** `"נקודה ל[שם]"` or `"[שם] נקודה"`
- **English:** `"Point to [name]"`

The app registers the point, updates the score according to official tennis rules, and reads it out loud — so both players always know where they stand.

Other voice commands:
| Command | Hebrew | English |
|---|---|---|
| Undo last point | `"בטל"` | `"undo"` |
| Read current score | `"תוצאה"` | `"score"` |
| Point by number | `"אחד"` / `"שתיים"` | `"one"` / `"two"` |

## Features

- 🎙️ Voice command recognition (Hebrew & English)
- 📢 AI-powered TTS announcements (Azure via Cloudflare Worker, with system fallback)
- 🎾 Full tennis scoring: points → games, deuce, advantage
- ↩️ Undo last point
- 🌐 Bilingual UI (Hebrew / English)
- 🎧 Bluetooth earbud support

## Tech Stack

- Swift / SwiftUI
- `Speech` framework (SFSpeechRecognizer)
- `AVFoundation` (audio session, TTS fallback)
- Cloudflare Worker + Azure TTS (AI voice announcements)

## Requirements

- iOS 16+
- Real device (microphone required — simulator won't work)
- Microphone & Speech Recognition permissions

## How to Run

1. Clone the repo
2. Open `TennisVoiceScore.xcodeproj` in Xcode
3. Connect a real iOS device
4. Build & run
5. Enter player names, tap the mic, and start playing
