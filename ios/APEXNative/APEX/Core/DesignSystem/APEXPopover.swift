import SwiftUI

/*
 * A real popup, not a sheet pretending to be one.
 *
 * A bottom sheet at half height is still a sheet: it is anchored to the bottom
 * edge, it takes a fixed slice of the screen whether the content needs it or
 * not, and content longer than that slice has to be scrolled. What the web does
 * instead is a small card floating over a dimmed page, sized to whatever it
 * holds, showing the whole thing at once.
 *
 * UIKit and SwiftUI can do exactly that; a sheet was simply the wrong tool.
 * This centres a card, sizes it to its content, caps it at a share of the
 * screen so a long list can still scroll rather than run off, and dims what is
 * behind without hiding it.
 */
struct APEXPopover<PopoverContent: View>: ViewModifier {
    @Binding var isPresented: Bool
    var maxHeightFraction: CGFloat = 0.78
    @ViewBuilder var popover: () -> PopoverContent

    func body(content: Content) -> some View {
        content.overlay {
            if isPresented {
                GeometryReader { proxy in
                    ZStack {
                        /* Dim, and dismiss on a tap outside. */
                        Color.black.opacity(0.28)
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture { dismiss() }
                            .transition(.opacity)

                        card(maxHeight: proxy.size.height * maxHeightFraction)
                            .frame(maxWidth: min(proxy.size.width - 64, 372))
                            .transition(.scale(scale: 0.94).combined(with: .opacity))
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .ignoresSafeArea()
                .zIndex(100)
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isPresented)
    }

    private func card(maxHeight: CGFloat) -> some View {
        /* Hugs its content, and only becomes scrollable once it would outgrow
           the screen. A plain ScrollView would always claim the full height and
           leave the card half empty. */
        /*
         * The cap belongs to the scrolling branch alone. Applying it to both
         * handed the hugging branch the whole allowance as its proposal, and it
         * took it: the card came out full height with the content stranded in
         * the middle of it.
         */
        ViewThatFits(in: .vertical) {
            popover()
                .padding(15)
                .fixedSize(horizontal: false, vertical: true)
            ScrollView {
                popover().padding(15)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxHeight: maxHeight)
        }
        .background(APEXColor.canvas, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .stroke(.white.opacity(0.7), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.22), radius: 40, y: 18)
        .accessibilityAddTraits(.isModal)
    }

    private func dismiss() {
        isPresented = false
    }
}

extension View {
    /// Floats a card over this view, sized to what it holds.
    func apexPopover<Content: View>(
        isPresented: Binding<Bool>,
        maxHeightFraction: CGFloat = 0.78,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        modifier(APEXPopover(isPresented: isPresented, maxHeightFraction: maxHeightFraction, popover: content))
    }

    /// The same, keyed off an optional item.
    func apexPopover<Item: Identifiable, Content: View>(
        item: Binding<Item?>,
        maxHeightFraction: CGFloat = 0.78,
        @ViewBuilder content: @escaping (Item) -> Content
    ) -> some View {
        modifier(
            APEXPopover(
                isPresented: Binding(
                    get: { item.wrappedValue != nil },
                    set: { if !$0 { item.wrappedValue = nil } }
                ),
                maxHeightFraction: maxHeightFraction,
                popover: { if let value = item.wrappedValue { content(value) } }
            )
        )
    }
}

/// A popup's own header: a title, an optional subtitle and a close control.
struct APEXPopoverHeader: View {
    let title: String
    var subtitle: String?
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(APEXFont.display(20))
                    .foregroundStyle(APEXColor.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(APEXFont.body(12, weight: .semibold))
                        .foregroundStyle(APEXColor.secondaryInk)
                }
            }
            Spacer(minLength: 6)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(APEXColor.secondaryInk)
                    .frame(width: 34, height: 34)
                    .background(.white.opacity(0.8), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close")
        }
    }
}
