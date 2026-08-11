import SwiftUI

struct StatisticsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        let stats = appState.statisticsStore.stats
        Form {
            Section("All time") {
                StatisticRow(icon: "pawprint.fill", label: "Cat interventions", value: "\(stats.detectionCount)")
                StatisticRow(icon: "keyboard.fill", label: "Accidental keys blocked", value: "\(stats.blockedEventCount)")
                StatisticRow(icon: "shield.fill", label: "Protection time", value: formattedDuration(stats.totalProtectionDuration))
            }
            if let date = stats.lastDetectionDate {
                Section {
                    Text("Last detection \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Text("\(stats.blockedEventCount) mysterious characters prevented.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func formattedDuration(_ duration: TimeInterval) -> String {
        let seconds = Int(duration.rounded())
        if seconds < 60 { return "\(seconds)s" }
        return "\(seconds / 60)m \(seconds % 60)s"
    }
}

private struct StatisticRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .frame(width: 22)
            Text(label)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .monospacedDigit()
        }
    }
}
