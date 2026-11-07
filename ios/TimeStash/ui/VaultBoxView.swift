import SwiftUI

/// The box that fills up as the user banks time.
///
/// Drawn rather than shipped as an image so it can fill to any fraction and
/// stay crisp in both light and dark mode.
///
/// ⚠️ 2026-11-08：旧版用 `ZStack(alignment: .bottom)` + `offset` 定位，
/// 结果**填充块和箱盖都掉到了框子外面** —— 商店截图里能看到一条蓝色横条
/// 悬在框子底下（2026-11-08 截图实测）。根因：`ZStack` 的 `.bottom` 对齐
/// 已经把子视图贴到底边，再叠一个 `offset` 就等于又推出去一次。
/// 现在改成**显式 `.position(x:y:)` 定位**，每个部件的坐标都写死在
/// 计算好的矩形里，不再依赖对齐 + 偏移的组合。
struct VaultBoxView: View {
    let totalSeconds: Int
    /// Seconds that fill the box completely. Defaults to the next milestone.
    var targetSeconds: Int = 8 * 60 * 60
    var lineWidth: CGFloat = 3

    private var progress: Double {
        guard targetSeconds > 0 else { return 0 }
        return min(1, Double(totalSeconds) / Double(targetSeconds))
    }

    /// How many hour-lines the box is divided into — one per hour of the
    /// milestone the user is working towards.
    private var bandCount: Int {
        max(1, Int(ceil(Double(targetSeconds) / 3600.0)))
    }

    /// The shape of the box: a lid on top, a body below it.
    private struct Layout {
        let lid: CGRect
        let body: CGRect
    }

    private func layout(width: CGFloat, height: CGFloat) -> Layout {
        let inset: CGFloat = lineWidth + 5
        let lidHeight: CGFloat = 22
        let lidOverhang: CGFloat = 8
        let body = CGRect(
            x: inset,
            y: lidHeight,
            width: max(0, width - inset * 2),
            height: max(0, height - lidHeight - inset)
        )
        let lid = CGRect(
            x: max(0, body.minX - lidOverhang),
            y: 2,
            width: min(width, body.width + lidOverhang * 2),
            height: lidHeight - 6
        )
        return Layout(lid: lid, body: body)
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let height = geo.size.height
            let box = layout(width: width, height: height)

            // The banked time, filling from the bottom of the body.
            let fillHeight = box.body.height * progress
            let fillRect = CGRect(
                x: box.body.minX,
                y: box.body.maxY - fillHeight,
                width: box.body.width,
                height: fillHeight
            )

            ZStack {
                // The inside of the box, so it reads as a container and not
                // as an empty placeholder.
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.06))
                    .frame(width: box.body.width, height: box.body.height)
                    .position(x: box.body.midX, y: box.body.midY)

                // Hour lines, so the fill reads as countable time.
                ForEach(1..<max(1, bandCount), id: \.self) { index in
                    let fraction = CGFloat(index) / CGFloat(bandCount)
                    Rectangle()
                        .fill(Color.secondary.opacity(0.14))
                        .frame(width: box.body.width, height: 1)
                        .position(
                            x: box.body.midX,
                            y: box.body.minY + box.body.height * fraction
                        )
                }

                // The banked time.
                if progress > 0 {
                    Rectangle()
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.accentColor.opacity(0.95),
                                    Color.accentColor.opacity(0.62),
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .frame(width: fillRect.width, height: fillRect.height)
                        .overlay(alignment: .top) {
                            Rectangle()
                                .fill(Color.white.opacity(0.35))
                                .frame(height: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .position(x: fillRect.midX, y: fillRect.midY)
                }

                // The outline of the body.
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        style: StrokeStyle(
                            lineWidth: lineWidth,
                            dash: progress > 0 ? [7, 6] : []
                        )
                    )
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: box.body.width, height: box.body.height)
                    .position(x: box.body.midX, y: box.body.midY)

                // The lid.
                RoundedRectangle(cornerRadius: 6)
                    .fill(Color.secondary.opacity(0.5))
                    .frame(width: box.lid.width, height: box.lid.height)
                    .position(x: box.lid.midX, y: box.lid.midY)

                // The handle on the lid — this is what makes it read as a
                // box rather than a bar.
                RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(style: StrokeStyle(lineWidth: 3))
                    .foregroundStyle(Color.secondary.opacity(0.5))
                    .frame(width: 54, height: 12)
                    .position(x: box.lid.midX, y: box.lid.midY - 3)
            }
            .frame(width: width, height: height)
        }
        .aspectRatio(1.15, contentMode: .fit)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("vault_box_accessibility"))
        .accessibilityValue(Text(VaultFormat.duration(totalSeconds)))
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
