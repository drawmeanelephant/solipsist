import SwiftUI

/// Machine-local execution knobs. These write UserDefaults only — never
/// `boris.json` (D2).
struct ExecutionSection: View {
    @AppStorage(Self.jobsKey) private var jobs = 1
    @AppStorage(Self.incrementalKey) private var incremental = false
    @AppStorage(Self.quietKey) private var quiet = false

    static let jobsKey = "solipsist.execution.jobs"
    static let incrementalKey = "solipsist.execution.incremental"
    static let quietKey = "solipsist.execution.quiet"
    static let jobsRange = 1...64

    var body: some View {
        Stepper(value: $jobs, in: Self.jobsRange) {
            LabeledContent("Jobs", value: "\(clampedJobs)")
        }
        .onChange(of: jobs) { _, newValue in
            if !Self.jobsRange.contains(newValue) {
                jobs = min(max(newValue, Self.jobsRange.lowerBound), Self.jobsRange.upperBound)
            }
        }
        Toggle("Incremental", isOn: $incremental)
        Toggle("Quiet", isOn: $quiet)
        Text("Machine-local. Not written to boris.json.")
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var clampedJobs: Int {
        min(max(jobs, Self.jobsRange.lowerBound), Self.jobsRange.upperBound)
    }
}
