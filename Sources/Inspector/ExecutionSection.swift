import SwiftUI

/// Machine-local execution knobs. These write UserDefaults only — never
/// `boris.json` (D2).
struct ExecutionSection: View {
    @AppStorage(BorisExecutionKnobs.jobsKey) private var jobs = 1
    @AppStorage(BorisExecutionKnobs.incrementalKey) private var incremental = false
    @AppStorage(BorisExecutionKnobs.quietKey) private var quiet = false

    static let jobsKey = BorisExecutionKnobs.jobsKey
    static let incrementalKey = BorisExecutionKnobs.incrementalKey
    static let quietKey = BorisExecutionKnobs.quietKey
    static let jobsRange = BorisExecutionKnobs.jobsRange

    var body: some View {
        Stepper(value: $jobs, in: BorisExecutionKnobs.jobsRange) {
            LabeledContent("Jobs", value: "\(clampedJobs)")
        }
        .onChange(of: jobs) { _, newValue in
            if !BorisExecutionKnobs.jobsRange.contains(newValue) {
                jobs = min(max(newValue, BorisExecutionKnobs.jobsRange.lowerBound), BorisExecutionKnobs.jobsRange.upperBound)
            }
        }
        Toggle("Incremental", isOn: $incremental)
        Toggle("Quiet", isOn: $quiet)
        Text("Machine-local. Not written to boris.json.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var clampedJobs: Int {
        min(max(jobs, BorisExecutionKnobs.jobsRange.lowerBound), BorisExecutionKnobs.jobsRange.upperBound)
    }
}
