import SwiftUI

struct ChatRoomListView: View {
  @EnvironmentObject private var store: InstaChatStore

  var body: some View {
    Group {
      if store.isLoadingRooms && store.rooms.isEmpty {
        ProgressView("Loading chats")
      } else if store.rooms.isEmpty {
        VStack(spacing: 10) {
          Image(systemName: "message")
            .font(.system(size: 42))
            .foregroundStyle(.secondary)
          Text("No Chats")
            .font(.headline)
          Text("New conversations will appear here.")
            .font(.subheadline)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
      } else {
        List(store.rooms) { room in
          NavigationLink(value: room) {
            ChatRoomRow(room: room)
          }
        }
        #if os(iOS)
        .listStyle(.insetGrouped)
        #else
        .listStyle(.inset)
        #endif
        .refreshable {
          await store.loadRooms()
        }
      }
    }
    .navigationTitle(store.configuration.title)
    .navigationDestination(for: InstaChatRoom.self) { room in
      ChatDetailView(room: room)
        .environmentObject(store)
    }
    .alert("Chat Error", isPresented: Binding(get: { store.errorMessage != nil }, set: { _ in })) {
      Button("OK", role: .cancel) {}
    } message: {
      Text(store.errorMessage ?? "")
    }
  }
}

private struct ChatRoomRow: View {
  var room: InstaChatRoom

  var body: some View {
    HStack(spacing: 12) {
      AvatarView(title: room.title, url: room.avatarURL, size: 48)

      VStack(alignment: .leading, spacing: 4) {
        HStack {
          Text(room.title)
            .font(.headline)
            .foregroundStyle(.primary)
            .lineLimit(1)

          Spacer()

          if let updatedAt = room.updatedAt {
            Text(updatedAt, style: .time)
              .font(.caption)
              .foregroundStyle(.secondary)
          }
        }

        Text(room.subtitle ?? "Tap to open conversation")
          .font(.subheadline)
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }

      if room.unreadCount > 0 {
        Circle()
          .fill(.red)
          .frame(width: 10, height: 10)
          .accessibilityLabel("Unread messages")
      }
    }
    .padding(.vertical, 6)
  }
}

struct AvatarView: View {
  var title: String
  var url: URL?
  var size: CGFloat

  var body: some View {
    ZStack {
      Circle()
        .fill(Color.gray.opacity(0.14))

      if let url {
        AsyncImage(url: url) { phase in
          switch phase {
          case let .success(image):
            image.resizable().scaledToFill()
          default:
            initials
          }
        }
        .clipShape(Circle())
      } else {
        initials
      }
    }
    .frame(width: size, height: size)
  }

  private var initials: some View {
    Text(String(title.prefix(1)).uppercased())
      .font(.headline)
      .foregroundStyle(.secondary)
  }
}
