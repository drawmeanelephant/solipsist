import Foundation

/// #276: sidebar navigation rules — source cycling order math and the
/// trunk-filter predicate. Pure, so ContractTests can pin them; the store
/// and sidebar call these.
enum SidebarNavigation {
    /// The id that becomes selected when walking `ids` one step from
    /// `current`. Wraps at both ends. Fewer than two sources (or a missing
    /// list entry handled below) never moves the selection off a working
    /// value.
    static func cycledSource(
        current: SourceID?,
        ids: [SourceID],
        forward: Bool
    ) -> SourceID? {
        guard ids.count > 1 else { return current }
        guard let index = ids.firstIndex(where: { $0 == current }) else {
            // No valid current selection: enter at the near end.
            return forward ? ids[0] : ids[ids.count - 1]
        }
        if forward {
            return ids[(index + 1) % ids.count]
        }
        return ids[(index - 1 + ids.count) % ids.count]
    }

    /// Trunk-filter predicate (#276): case-insensitive substring on the
    /// title; an empty (or whitespace-only) query passes everything.
    static func matches(filter query: String, title: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        return title.range(of: trimmed, options: .caseInsensitive) != nil
    }
}
