import SwiftUI

#if os(iOS)
/// Simple progress view for import operations
struct ImportProgressView: View {
    let progress: ImportProgress

    var body: some View {
        VStack(spacing: 20) {
            ProgressView(value: progress.percentage)
                .progressViewStyle(.linear)
                .padding(.horizontal)

            Text(progress.description)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .padding()
        .presentationDetents([.height(150)])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    ImportProgressView(progress: .importing(current: 50, total: 100))
}
#endif
