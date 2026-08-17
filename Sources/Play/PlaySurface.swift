import SwiftUI

/// Marker for views that fill the play slot. One implementation per source
/// kind, owned by that kind's folder under `Sources/Play/`.
protocol PlaySurface: View {}
