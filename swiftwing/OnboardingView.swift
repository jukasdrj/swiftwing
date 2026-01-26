import SwiftUI

/// Onboarding flow shown on first app launch
/// 3 slides: Welcome, Camera Permission, Core Features
struct OnboardingView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false
    @State private var currentPage = 0

    var onComplete: () -> Void

    var body: some View {
        ZStack {
            // Black Swiss background
            Color.swissBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Page indicator
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index == currentPage ? Color.internationalOrange : Color.white.opacity(0.3))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 60)
                .padding(.bottom, 40)

                // Slides
                TabView(selection: $currentPage) {
                    Slide1Welcome()
                        .tag(0)

                    Slide2CameraPermission()
                        .tag(1)

                    Slide3CoreFeatures()
                        .tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))

                // Bottom buttons
                VStack(spacing: 16) {
                    if currentPage == 2 {
                        // Get Started button (final slide)
                        Button(action: completeOnboarding) {
                            Text("Get Started")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.swissBackground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.internationalOrange)
                                .cornerRadius(12)
                        }
                        .transition(.opacity)
                    } else {
                        // Next button
                        Button(action: { withAnimation { currentPage += 1 } }) {
                            Text("Next")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundColor(.swissBackground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 56)
                                .background(Color.internationalOrange)
                                .cornerRadius(12)
                        }
                        .transition(.opacity)
                    }

                    // Skip button
                    Button(action: completeOnboarding) {
                        Text("Skip")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(.white.opacity(0.6))
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 40)
            }
        }
        .animation(.spring(duration: 0.3), value: currentPage)
    }

    private func completeOnboarding() {
        hasCompletedOnboarding = true
        onComplete()
    }
}

// MARK: - Slide 1: Welcome
struct Slide1Welcome: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Hero icon: Book spine with orange stripe
            ZStack {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.white)
                    .frame(width: 120, height: 180)

                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.internationalOrange)
                    .frame(width: 24, height: 180)
                    .offset(x: -48)
            }

            VStack(spacing: 16) {
                Text("Welcome to SwiftWing")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.swissText)
                    .multilineTextAlignment(.center)

                Text("Scan book spines with your camera.\nGet instant metadata from AI.\nBuild your digital library in seconds.")
                    .font(.system(size: 17))
                    .foregroundColor(.swissText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Slide 2: Camera Permission
struct Slide2CameraPermission: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Camera icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.1))
                    .frame(width: 160, height: 160)

                Image(systemName: "camera.fill")
                    .font(.system(size: 64))
                    .foregroundColor(.internationalOrange)
            }

            VStack(spacing: 16) {
                Text("Camera Access")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundColor(.swissText)
                    .multilineTextAlignment(.center)

                Text("SwiftWing needs camera access to scan book spines.\n\nYour photos are never stored — we only send them to our AI for instant recognition.")
                    .font(.system(size: 17))
                    .foregroundColor(.swissText.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Slide 3: Core Features
struct Slide3CoreFeatures: View {
    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            VStack(spacing: 24) {
                // Feature 1: Scan
                FeatureRow(
                    icon: "camera.viewfinder",
                    title: "Instant Scanning",
                    description: "Point your camera at book spines and tap to capture"
                )

                // Feature 2: AI Recognition
                FeatureRow(
                    icon: "wand.and.stars",
                    title: "AI Recognition",
                    description: "Real-time metadata from our Talaria AI backend"
                )

                // Feature 3: Library Management
                FeatureRow(
                    icon: "books.vertical.fill",
                    title: "Digital Library",
                    description: "Search, browse, and manage your collection"
                )

                // Feature 4: Offline Mode
                FeatureRow(
                    icon: "wifi.slash",
                    title: "Offline Queue",
                    description: "Scan offline, auto-upload when connected"
                )
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

// MARK: - Feature Row Component
struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Image(systemName: icon)
                .font(.system(size: 28))
                .foregroundColor(.internationalOrange)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.swissText)

                Text(description)
                    .font(.system(size: 15))
                    .foregroundColor(.swissText.opacity(0.7))
            }

            Spacer()
        }
    }
}

#Preview {
    OnboardingView(onComplete: {})
        .preferredColorScheme(.dark)
}
