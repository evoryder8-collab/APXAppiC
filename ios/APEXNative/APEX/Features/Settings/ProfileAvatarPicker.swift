import SwiftUI
import PhotosUI

/// The profile picture, and the way to change it.
///
/// Falls back to the built-in portrait for the bespoke accounts and to initials
/// for everyone else, so a new account has something reasonable before it has
/// chosen anything.
struct ProfileAvatarPicker: View {
    @Environment(AppSession.self) private var session
    @State private var language = LanguageState.shared
    @State private var picked: PhotosPickerItem?
    @State private var uploading = false
    @State private var preview: UIImage?

    private var profile: Profile? { session.profile }

    var body: some View {
        PhotosPicker(selection: $picked, matching: .images, photoLibrary: .shared()) {
            ZStack {
                avatar
                    .frame(width: 76, height: 76)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(.white.opacity(0.9), lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.10), radius: 10, y: 4)

                if uploading {
                    Circle().fill(.black.opacity(0.35)).frame(width: 76, height: 76)
                    ProgressView().tint(.white)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 24, height: 24)
                    .background(APEXColor.violet, in: Circle())
                    .overlay(Circle().stroke(.white, lineWidth: 1.5))
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(language.text("Change profile picture"))
        .onChange(of: picked) { _, item in
            guard let item else { return }
            Task { await upload(item) }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let preview {
            Image(uiImage: preview).resizable().scaledToFill()
        } else if let persona = profile?.persona {
            PortraitImage(name: persona.portraitName).scaledToFill()
        } else {
            ZStack {
                APEXColor.violet.opacity(0.16)
                Text(initials)
                    .font(APEXFont.display(24))
                    .foregroundStyle(APEXColor.violet)
            }
        }
    }

    private var initials: String {
        let name = profile?.displayName ?? "APEX"
        return String(name.split(separator: " ").prefix(2).compactMap(\.first)).uppercased()
    }

    private func upload(_ item: PhotosPickerItem) async {
        uploading = true
        defer { uploading = false }
        guard
            let data = try? await item.loadTransferable(type: Data.self),
            let image = UIImage(data: data),
            /* Resized and compressed here, on the phone. A camera roll photo is
               routinely several megabytes and is about to be shown at 76
               points across. */
            let prepared = AvatarImage.prepare(image)
        else {
            session.alertMessage = language.text("That picture could not be read.")
            return
        }
        preview = UIImage(data: prepared)
        await session.setAvatar(data: prepared)
    }
}
