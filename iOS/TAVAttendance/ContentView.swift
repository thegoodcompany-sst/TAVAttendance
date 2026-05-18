import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                Text("TAV Attendance")
                    .font(.title)
                    .fontWeight(.semibold)
            }
            .navigationTitle("Attendance")
        }
    }
}

#Preview {
    ContentView()
}
