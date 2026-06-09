import Foundation
import SwiftUI

struct AppError: Identifiable, LocalizedError {
    let id = UUID()
    let message: String
    let underlyingError: Error?

    init(_ message: String, underlyingError: Error? = nil) {
        self.message = message
        self.underlyingError = underlyingError
    }

    var errorDescription: String? { message }
    var recoverySuggestion: String? {
        underlyingError.map { "Details: \($0.localizedDescription)" }
    }
}

extension View {
    func errorAlert(error: Binding<AppError?>) -> some View {
        alert("Error", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        ), presenting: error.wrappedValue) { _ in
            Button("OK", role: .cancel) { error.wrappedValue = nil }
        } message: { err in
            Text(err.message)
        }
    }

    func errorAlertWithRetry(error: Binding<AppError?>, retry: @escaping () -> Void) -> some View {
        alert("Error", isPresented: Binding(
            get: { error.wrappedValue != nil },
            set: { if !$0 { error.wrappedValue = nil } }
        ), presenting: error.wrappedValue) { _ in
            Button("Retry", action: retry)
            Button("Dismiss", role: .cancel) { error.wrappedValue = nil }
        } message: { err in
            Text(err.message)
        }
    }
}