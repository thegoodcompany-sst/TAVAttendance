import SwiftUI

struct AttendanceTakerView: View {
    @EnvironmentObject var auth: AuthManager
    
    var body: some View {
        NavigationStack {
            VStack {
                Image(systemName: "person.text.rectangle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.tint)
                    .padding()
                
                Text("Attendance Taker")
                    .font(.title)
                    .fontWeight(.semibold)
                
                Text("Tutor view for taking attendance")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
                
                Spacer()
                
                // TODO: Add attendance taking functionality
                
                Spacer()
            }
            .navigationTitle("Take Attendance")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        if let profile = auth.profile, profile.roles.contains(.admin) {
                            Button {
                                auth.switchRole(to: .admin)
                            } label: {
                                Label("Switch to Admin", systemImage: "person.badge.key")
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
        }
    }
}

#Preview {
    AttendanceTakerView()
        .environmentObject(AuthManager.shared)
}
