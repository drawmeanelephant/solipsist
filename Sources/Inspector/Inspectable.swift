import Foundation

/// A section the drawer can render. The Inspector lane owns the views;
/// chrome only asks the current selection for its sections.
struct InspectorSection: Identifiable, Sendable {
    let id: String
    let title: String
}

protocol Inspectable {
    var inspectorSections: [InspectorSection] { get }
}
