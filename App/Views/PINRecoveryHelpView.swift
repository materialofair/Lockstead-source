import SwiftUI

struct PINRecoveryHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            XLScreen {
                XLCard {
                    VStack(alignment: .leading, spacing: XL.Space.m) {
                        Text("pin.recovery.remember", tableName: "PINExperience")
                        Text("pin.recovery.biometric", tableName: "PINExperience")
                        Text("pin.recovery.system", tableName: "PINExperience")
                        Text("pin.recovery.persistence", tableName: "PINExperience")
                    }
                    .foregroundStyle(XL.ink)
                }
            }
            .navigationTitle(String(localized: "pin.recovery.title", table: "PINExperience"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { Button("common.close") { dismiss() } }
        }
        .tint(XL.primary)
    }
}
