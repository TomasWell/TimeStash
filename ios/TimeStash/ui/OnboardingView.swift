import Combine
import SwiftUI

/// Four screens, in order:
///
/// 1. the problem, in the user's own words
/// 2. how the box works
/// 3. **try it right now** — a one-minute task so the box visibly moves
/// 4. one number that makes every later estimate smarter
///
/// Screen 3 is the one that matters: a new user must see the box fill before
/// they leave the app.
struct OnboardingView: View {
    @EnvironmentObject private var store: VaultStore

    let onFinish: () -> Void

    @State private var page = 0
    @State private var experienceTaskID: Int64?
    @State private var experienceElapsed = 0
    @State private var baselineMinutes = 30

    /// One shared tick for the one-minute experiment.
    private let tick = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private let totalPages = 4

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                problemPage.tag(0)
                mechanismPage.tag(1)
                experiencePage.tag(2)
                baselinePage.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            footer
        }
        .onReceive(tick) { _ in
            if experienceTaskID != nil {
                experienceElapsed += 1
            }
        }
    }

    // MARK: - Page 1

    private var problemPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 62))
                .foregroundStyle(.tint)
            Text(L("onboarding_1_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(L("onboarding_1_body"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 2

    private var mechanismPage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "shippingbox.fill")
                .font(.system(size: 62))
                .foregroundStyle(.tint)

            VStack(alignment: .leading, spacing: 16) {
                step(number: 1, key: "onboarding_2_step1")
                step(number: 2, key: "onboarding_2_step2")
                step(number: 3, key: "onboarding_2_step3")
            }
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    private func step(number: Int, key: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.accentColor))
            Text(L(key))
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
    }

    // MARK: - Page 3

    private var experiencePage: some View {
        VStack(spacing: 18) {
            Spacer()

            Text(L("onboarding_3_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)

            if experienceTaskID == nil {
                Text(L("onboarding_3_body"))
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)

                Button {
                    startExperience()
                } label: {
                    Text(L("onboarding_3_try"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 40)
                .accessibilityIdentifier("onboardingTryButton")
            } else {
                VStack(spacing: 14) {
                    // The box fills as the minute runs out — the point of
                    // this screen is to see it move.
                    VaultBoxView(totalSeconds: experienceElapsed, targetSeconds: 60)
                        .frame(maxWidth: 190)
                    Text(VaultFormat.clock(experienceElapsed))
                        .font(.system(size: 34, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Button {
                        finishExperience()
                    } label: {
                        Text(L("onboarding_3_finish"))
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                            .foregroundStyle(.white)
                    }
                    .padding(.horizontal, 60)
                    .accessibilityIdentifier("onboardingFinishButton")
                }
            }

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Page 4

    private var baselinePage: some View {
        VStack(spacing: 18) {
            Spacer()
            Image(systemName: "target")
                .font(.system(size: 56))
                .foregroundStyle(.tint)
            Text(L("onboarding_4_title"))
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text(L("onboarding_4_body"))
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            VStack {
                Text("\(baselineMinutes) min")
                    .font(.system(size: 40, weight: .bold, design: .rounded))
                    .monospacedDigit()
                Slider(value: Binding(
                    get: { Double(baselineMinutes) },
                    set: { baselineMinutes = Int($0.rounded()) }
                ), in: 5...180, step: 5)
                .accessibilityIdentifier("onboardingBaselineSlider")
            }
            .padding(.horizontal, 40)
            .padding(.top, 8)

            Spacer()
        }
        .padding(.horizontal, 32)
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 16) {
            if page < totalPages - 1 {
                Button {
                    withAnimation { page += 1 }
                } label: {
                    Text(L("onboarding_next"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("onboardingNextButton")
            } else {
                Button {
                    store.baselineEstimateSeconds = baselineMinutes * 60
                    onFinish()
                } label: {
                    Text(L("onboarding_start"))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(RoundedRectangle(cornerRadius: 14).fill(Color.accentColor))
                        .foregroundStyle(.white)
                }
                .accessibilityIdentifier("onboardingStartButton")
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 18)
    }

    // MARK: - The 60-second experiment

    private func startExperience() {
        // The title is localized **now**, not when the ledger renders it —
        // the task title is user-visible data, not a key.
        let task = store.createSampleTask(
            title: L("onboarding_3_task_title"),
            category: .other,
            estimatedSeconds: 60
        )
        guard let id = task?.id else { return }
        store.start(taskID: id)
        experienceTaskID = id
        experienceElapsed = 0
    }

    private func finishExperience() {
        guard let id = experienceTaskID else { return }
        store.finish(taskID: id)
        experienceTaskID = nil
        withAnimation { page = 3 }
    }
}
