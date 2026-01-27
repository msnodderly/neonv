import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "doc.text.magnifyingglass")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("NeoNV")
        }
        .padding()
        .frame(minWidth: 600, minHeight: 400)
    }
}

#Preview {
    ContentView()
}
