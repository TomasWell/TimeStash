import SwiftUI

/// The box that fills up as the user banks time.
///
/// Drawn rather than shipped as an image so it can fill to any fraction and
/// stay crisp in both light and dark mode. Each band is one hour of saved
/// time — the texture is there to say "this was time you did not have to spend".
struct VaultBoxView: View {
    let totalSeconds: Int
    /// Seconds that fill the box completely. Defaults to the next milestone.
    var targetSeconds: Int = 8 * 60 * 60
    var lineWidth: CGFloat = 3

    private var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(1, Double(totalSeconds) / Double(targetSeconds))
    }

    private var fullHours: Int {
        Int(Double(totalSeconds) / 3600.0)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let innerInset: CGFloat = lineWidth + 4
            let inner = CGRect(
                x: innerInset,
                y: innerInset,
                width: max(0, width - innerInset * 2),
                height: max(0, height - innerInset * 2)
            )

            ZStack(alignment: .bottom) {
                // The banked time, filling from the bottom.
                if progress > 0 {
                    let fillHeight = inner.height * progress
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [Color.accentColor.opacity(0.95), Color.accentColor.opacity(0.6)],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: inner.width, height: fillHeight)
                        .overlay(alignment: .top) {
                            // Hour lines, so the fill reads as countable time.
                            hourLines(in: inner, fillHeight: fillHeight)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .offset(x: inner.minX, y: inner.maxY - fillHeight)
                }

                // The empty part of the box.
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(style: StrokeStyle(lineWidth: lineWidth, dash: progress > 0 ? [6, 5] : []))
                    .foregroundStyle(Color.secondary.opacity(0.45))
                    .padding(innerInset)

                // The lid.
                Rectangle()
                    .fill(Color.secondary.opacity(0.45))
                    .frame(width: inner.width + lineWidth * 2, height: lineWidth)
                    .offset(x: inner.minX, y: inner.minY - lineWidth / 2)
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(1.25, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("vault_box_accessibility"))
        .accessibilityValue(Text(VaultFormat.duration(totalSeconds)))
    }

    /// Horizontal separators every hour of banked time.
    private func hourLines(in rect: CGRect, fillHeight: CGFloat) -> some View {
        let hours = max(1, Int(ceil(Double(fillHeight) / Double(rect.height) * Double(max(1, fullHours)))))
        return VStack(spacing: 0) {
            ForEach(0..<max(1, hours), id: \.self) { _ in
                Rectangle()
                    .fill(Color.white.opacity(0.18))
                    .frame(height: 1)
                Spacer(minLength: 0)
            }
        }
        .frame(width: rect.width, height: fillHeight, alignment: .top)
    }
}

/// The big number under the box.
struct VaultTotalView: View {
    let totalSeconds: Int
    var caption: String?

    var body: some View {
        VStack(spacing: 4) {
            Text(VaultFormat.duration(totalSeconds))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
            if let caption {
                Text(caption)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
    }
}

/// Green when the task came in under its estimate, orange when it overran.
struct DeviationBadge: View {
    let deviationSeconds: Int

    private var isAhead: Bool { deviationSeconds < 0 }

    var body: some View {
        Text(
            isAhead
                ? L("badge_saved", VaultFormat.compactDuration(-deviationSeconds))
                : L("badge_over", VaultFormat.compactDuration(deviationSeconds))
        )
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(
                Capsule().fill(isAhead ? Color.green.opacity(0.16) : Color.orange.opacity(0.16))
            )
            .foregroundStyle(isAhead ? Color.green : Color.orange)
    }
}
