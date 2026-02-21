//
//  SplashView.swift
//  TennisVoiceScore
//

import SwiftUI
import AVFoundation

// MARK: - Splash View

struct SplashView: View {
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0

    var body: some View {
        ZStack {
            // Background
            Color(.systemBackground)
                .ignoresSafeArea()

            // Subtle glow behind logo (blurred circle)
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 140, height: 140)
                .clipShape(Circle())
                .blur(radius: 24)
                .opacity(0.5)
                .scaleEffect(scale)

            // Circular logo
            Image("AppLogo")
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 120, height: 120)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
                .shadow(color: .accentColor.opacity(0.25), radius: 20, x: 0, y: 0)
                .scaleEffect(scale)
                .opacity(opacity)
        }
        .onAppear {
            playSplashSound()
            withAnimation(.easeOut(duration: 0.5)) {
                scale = 1.0
                opacity = 1.0
            }
        }
    }

    private func playSplashSound() {
        guard let url = Bundle.main.url(forResource: "splash", withExtension: "mp3") else { return }
        do {
            let player = try AVAudioPlayer(contentsOf: url)
            player.play()
        } catch {}
    }
}

// MARK: - Root View

struct RootView: View {
    @State private var showSplash = true

    var body: some View {
        ZStack {
            ContentView()
                .opacity(showSplash ? 0 : 1)
                .animation(.easeInOut(duration: 0.4), value: showSplash)

            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .zIndex(1)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: showSplash)
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) {
                showSplash = false
            }
        }
    }
}

#Preview("Splash") {
    SplashView()
}

#Preview("Root") {
    RootView()
}
