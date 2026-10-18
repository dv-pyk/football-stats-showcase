import SwiftUI
import PhotosUI

/// Add or edit one roster player: name, jersey number, keeper flag, and a face photo
/// cropped to a circle. Pushed/presented from `RosterEditorView`.
struct PlayerEditorView: View {
    @ObservedObject var rosterStore: RosterStore
    let teamName: String
    let existingPlayer: RosterPlayer?

    @Environment(\.dismiss) private var dismiss

    @State private var name: String
    @State private var jerseyNumber: String
    @State private var isKeeper: Bool
    @State private var initials: String
    @State private var avatar: UIImage?
    @State private var pickerItem: PhotosPickerItem?
    @State private var pickedSourceImage: UIImage?

    init(rosterStore: RosterStore, teamName: String, existingPlayer: RosterPlayer?) {
        self.rosterStore = rosterStore
        self.teamName = teamName
        self.existingPlayer = existingPlayer
        _name = State(initialValue: existingPlayer?.name ?? "")
        _jerseyNumber = State(initialValue: existingPlayer?.jerseyNumber ?? "")
        _isKeeper = State(initialValue: existingPlayer?.isKeeper ?? false)
        _initials = State(initialValue: existingPlayer?.initials ?? "")
        _avatar = State(initialValue: existingPlayer.flatMap { rosterStore.avatarImage(for: $0.id) })
    }

    /// What the fallback badge would show right now, live as `name`/`initials` change —
    /// shown as the field's placeholder so it's obvious a blank field still defaults to
    /// something sensible.
    private var derivedInitialsPreview: String {
        RosterPlayer(name: name.isEmpty ? "?" : name).displayInitials
    }

    var body: some View {
        Form {
            Section {
                HStack {
                    Spacer()
                    photoPickerButton
                    Spacer()
                }
                .listRowBackground(Color.clear)
            }

            Section("Player") {
                TextField("Name", text: $name)
                    .textInputAutocapitalization(.words)
                TextField("Jersey number (optional)", text: $jerseyNumber)
                    .keyboardType(.numberPad)
                Toggle("This player is the keeper", isOn: $isKeeper)
            }

            Section {
                TextField(derivedInitialsPreview, text: $initials)
                    .textInputAutocapitalization(.characters)
                    .onChange(of: initials) { _, newValue in
                        if newValue.count > 3 {
                            initials = String(newValue.prefix(3))
                        }
                    }
            } header: {
                Text("Initials")
            } footer: {
                Text("Shown instead of a photo wherever this player doesn't have one. Leave blank to use \(derivedInitialsPreview), based on their name.")
            }
        }
        .navigationTitle(existingPlayer == nil ? "Add Player" : "Edit Player")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .onChange(of: pickerItem) { _, newItem in
            Task {
                guard
                    let newItem,
                    let data = try? await newItem.loadTransferable(type: Data.self),
                    let image = UIImage(data: data)
                else { return }
                pickedSourceImage = image
            }
        }
        .sheet(item: $pickedSourceImage.asIdentifiableImage) { boxed in
            NavigationStack {
                PhotoCropView(source: boxed.image) { cropped in
                    avatar = cropped
                    pickedSourceImage = nil
                }
            }
        }
    }

    private var photoPickerButton: some View {
        PhotosPicker(selection: $pickerItem, matching: .images) {
            Group {
                if let avatar {
                    Image(uiImage: avatar)
                        .resizable()
                        .scaledToFill()
                } else {
                    VStack(spacing: 6) {
                        Image(systemName: "camera.fill")
                            .font(.title2)
                        Text("Add Photo")
                            .font(.caption)
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Color(.systemGray5))
                }
            }
            .frame(width: 120, height: 120)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    private func save() {
        let trimmedInitials = initials.trimmingCharacters(in: .whitespaces)
        let player = RosterPlayer(
            id: existingPlayer?.id ?? UUID(),
            name: name.trimmingCharacters(in: .whitespaces),
            jerseyNumber: jerseyNumber.trimmingCharacters(in: .whitespaces).isEmpty ? nil : jerseyNumber,
            isKeeper: isKeeper,
            initials: trimmedInitials.isEmpty ? nil : trimmedInitials
        )
        if let avatar {
            rosterStore.saveAvatar(avatar, for: player.id)
        }
        rosterStore.addOrUpdatePlayer(player, to: teamName)
        dismiss()
    }
}

/// `sheet(item:)` needs `Identifiable`; wraps a plain `UIImage` just for that.
private struct IdentifiableImage: Identifiable {
    let id = UUID()
    let image: UIImage
}

private extension Binding where Value == UIImage? {
    var asIdentifiableImage: Binding<IdentifiableImage?> {
        Binding<IdentifiableImage?>(
            get: { wrappedValue.map(IdentifiableImage.init) },
            set: { wrappedValue = $0?.image }
        )
    }
}

/// Pinch-to-zoom, drag-to-reposition circular crop. Renders the final square JPEG source
/// at full resolution via `UIGraphicsImageRenderer` (not a SwiftUI view snapshot), so photo
/// quality doesn't depend on how large the on-screen crop circle happened to be.
private struct PhotoCropView: View {
    let source: UIImage
    let onCrop: (UIImage) -> Void

    @Environment(\.dismiss) private var dismiss

    private let cropDiameter: CGFloat = 260
    // Group photos put faces small in the frame, so this needs real headroom — the crop
    // only ever ends up small on screen anyway (chart badge, list thumbnail), so some
    // softness from zooming past the source's native resolution is an acceptable trade.
    private let maxZoom: CGFloat = 15
    private let outputSize: CGFloat = 300

    @State private var committedScale: CGFloat = 1
    @GestureState private var pinchScale: CGFloat = 1
    @State private var committedOffset: CGSize = .zero
    @GestureState private var dragOffset: CGSize = .zero

    private var baseFillScale: CGFloat {
        let size = source.size
        guard size.width > 0, size.height > 0 else { return 1 }
        return max(cropDiameter / size.width, cropDiameter / size.height)
    }

    private var currentScale: CGFloat {
        min(max(committedScale * pinchScale, 1), maxZoom)
    }

    private var displayScale: CGFloat { baseFillScale * currentScale }

    private var renderedSize: CGSize {
        CGSize(width: source.size.width * displayScale, height: source.size.height * displayScale)
    }

    private func clamp(_ raw: CGSize, renderedSize: CGSize) -> CGSize {
        let maxX = max(0, (renderedSize.width - cropDiameter) / 2)
        let maxY = max(0, (renderedSize.height - cropDiameter) / 2)
        return CGSize(width: min(max(raw.width, -maxX), maxX), height: min(max(raw.height, -maxY), maxY))
    }

    private var liveOffset: CGSize {
        let raw = CGSize(
            width: committedOffset.width + dragOffset.width,
            height: committedOffset.height + dragOffset.height
        )
        return clamp(raw, renderedSize: renderedSize)
    }

    var body: some View {
        VStack(spacing: 20) {
            Spacer(minLength: 0)

            ZStack {
                Image(uiImage: source)
                    .resizable()
                    .frame(width: renderedSize.width, height: renderedSize.height)
                    .offset(liveOffset)
            }
            .frame(width: cropDiameter, height: cropDiameter)
            .clipShape(Circle())
            .overlay(Circle().strokeBorder(.white.opacity(0.85), lineWidth: 2))
            .contentShape(Rectangle())
            .gesture(
                MagnificationGesture()
                    .updating($pinchScale) { value, state, _ in state = value }
                    .onEnded { value in
                        committedScale = min(max(committedScale * value, 1), maxZoom)
                        committedOffset = clamp(committedOffset, renderedSize: renderedSize)
                    }
            )
            .simultaneousGesture(
                DragGesture()
                    .updating($dragOffset) { value, state, _ in state = value.translation }
                    .onEnded { value in
                        let raw = CGSize(
                            width: committedOffset.width + value.translation.width,
                            height: committedOffset.height + value.translation.height
                        )
                        committedOffset = clamp(raw, renderedSize: renderedSize)
                    }
            )

            Text("Pinch to zoom, drag to reposition")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)
        }
        .navigationTitle("Crop Photo")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Use Photo") {
                    onCrop(renderCroppedSquare())
                    dismiss()
                }
            }
        }
    }

    private func renderCroppedSquare() -> UIImage {
        let scale = displayScale
        let rendered = renderedSize
        let offset = liveOffset
        let topLeft = CGPoint(
            x: (cropDiameter - rendered.width) / 2 + offset.width,
            y: (cropDiameter - rendered.height) / 2 + offset.height
        )
        let cropOriginInSource = CGPoint(x: -topLeft.x / scale, y: -topLeft.y / scale)
        let cropSizeInSource = cropDiameter / scale
        let finalScale = outputSize / cropSizeInSource
        let drawnSize = CGSize(width: source.size.width * finalScale, height: source.size.height * finalScale)
        let drawnOrigin = CGPoint(x: -cropOriginInSource.x * finalScale, y: -cropOriginInSource.y * finalScale)

        // Pin scale to 1x: UIGraphicsImageRenderer defaults to the device's screen scale
        // (3x on this phone), which would silently render 900x900 pixels for a "300"
        // output instead of the intended 300x300 — tripling both dimensions and roughly
        // 9x-ing the saved JPEG's file size for no visual benefit at this thumbnail size.
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: outputSize, height: outputSize), format: format)
        return renderer.image { _ in
            source.draw(in: CGRect(origin: drawnOrigin, size: drawnSize))
        }
    }
}

#Preview {
    NavigationStack {
        PlayerEditorView(rosterStore: RosterStore(), teamName: PresetHomeTeam.defaultName, existingPlayer: nil)
    }
}
