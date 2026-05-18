import SwiftUI

struct ClassListView: View {
    @EnvironmentObject var auth: AuthManager
    
    @State private var classes: [String] = []
    
    var body: some View {
        NavigationStack {
            Group {
                if classes.isEmpty {
                    ContentUnavailableView {
                        Label("No Classes", systemImage: "book.closed")
                    } description: {
                        Text("There are no classes available at this time.")
                    }
                } else {
                    List(classes, id: \.self) { className in
                        Text(className)
                    }
                }
            }
            .navigationTitle("Classes")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let profile = auth.profile, profile.roles.contains(.tutor) {
                            Button {
                                auth.switchRole(to: .tutor)
                            } label: {
                                Label("Switch to Tutor", systemImage: "person.fill.checkmark")
                            }
                        }
                        
                        Divider()
                        
                        Button(role: .destructive) {
                            auth.logout()
                        } label: {
                            Label("Logout", systemImage: "rectangle.portrait.and.arrow.right")
                        }
                    } label: {
                        Image(systemName: "person.crop.circle")
                    }
                }
            }
            .task {
                await loadClasses()
            }
        }
    }
    
    private func loadClasses() async {
        // TODO: Implement actual API call to fetch classes
        // Simulate network delay
        try? await Task.sleep(for: .seconds(1))
        
        // Mock data
        classes = [
            "Mathematics 101",
            "Physics 202",
            "Chemistry 303",
            "Biology 404"
        ]
    }
}

#Preview {
    ClassListView()
        .environmentObject(AuthManager.shared)
}
