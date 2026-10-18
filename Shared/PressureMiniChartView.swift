import SwiftUI

struct PressureMiniChartView: View {
    let buckets: [Double]
    var height: CGFloat = 28
    var barWidth: CGFloat?

    var body: some View {
        let maxValue = max(buckets.map { abs($0) }.max() ?? 1, 1)

        GeometryReader { geometry in
            let spacing: CGFloat = 1
            let resolvedBarWidth = barWidth ?? max(
                2,
                (geometry.size.width - spacing * CGFloat(max(buckets.count - 1, 0))) / CGFloat(max(buckets.count, 1))
            )

            VStack(spacing: 2) {
                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(Array(buckets.enumerated()), id: \.offset) { _, value in
                        PressureMiniBar(
                            value: value,
                            maxValue: maxValue,
                            height: height,
                            barWidth: resolvedBarWidth
                        )
                    }
                }

                Rectangle()
                    .fill(Color.secondary.opacity(0.35))
                    .frame(height: 1)
            }
        }
        .frame(height: height + 3)
    }
}

private struct PressureMiniBar: View {
    let value: Double
    let maxValue: Double
    let height: CGFloat
    let barWidth: CGFloat

    var body: some View {
        let normalized = min(abs(value) / maxValue, 1)
        let barHeight = max(CGFloat(normalized) * (height / 2), value == 0 ? 2 : 4)

        VStack(spacing: 0) {
            if value >= 0 {
                Spacer(minLength: 0)
                RoundedRectangle(cornerRadius: 1)
                    .fill(value == 0 ? Color.secondary.opacity(0.2) : Color.green)
                    .frame(width: barWidth, height: barHeight)
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: height / 2)
            } else {
                Rectangle()
                    .fill(Color.clear)
                    .frame(height: height / 2)
                RoundedRectangle(cornerRadius: 1)
                    .fill(Color.red)
                    .frame(width: barWidth, height: barHeight)
                Spacer(minLength: 0)
            }
        }
        .frame(width: barWidth, height: height)
    }
}
