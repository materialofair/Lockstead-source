import SwiftUI
import FamilyControls

/// Let the system render token labels; never resolve or persist application names ourselves.
struct SelectionPreview: View {
    let selection: FamilyActivitySelection
    var title: LocalizedStringKey
    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: XL.Space.s) {
            Text(title).font(.footnote.weight(.semibold)).foregroundStyle(XL.muted)
            if selection.applicationTokens.isEmpty && selection.categoryTokens.isEmpty {
                Text("experience.apps.empty").font(.footnote).foregroundStyle(XL.muted)
            } else {
                ForEach(Array(selection.applicationTokens).prefix(expanded ? selection.applicationTokens.count : 5), id: \.self) { token in
                    Label(token).labelStyle(.titleAndIcon)
                }
                ForEach(Array(selection.categoryTokens).prefix(expanded ? selection.categoryTokens.count : max(0, 5 - selection.applicationTokens.count)), id: \.self) { token in
                    Label(token).labelStyle(.titleAndIcon)
                }
                if selection.applicationTokens.count + selection.categoryTokens.count > 5 {
                    Button(expanded ? "experience.apps.less" : "experience.apps.more") { expanded.toggle() }
                        .font(.footnote.weight(.medium))
                }
            }
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
