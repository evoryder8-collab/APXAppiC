import SwiftUI

/*
 * How a sheet should feel.
 *
 * Most of what the app opens is something a person glances at and dismisses:
 * the workout they are about to start, today's supplements, the calendar they
 * are copying a day from. Those have no business taking the whole screen and
 * hiding the context they were opened from. They come up part height, with the
 * screen behind still live and still touchable, and can be pulled to full only
 * if the person wants that.
 *
 * The exceptions earn it: building a meal, the water interface and a live
 * workout are the task, not a glance at it, and stay as they are.
 */
extension View {
    /// A glanceable sheet: part height, dismissible, context still visible.
    func apexTransientSheet(_ smallest: PresentationDetent = .medium) -> some View {
        self
            .presentationDetents([smallest, .large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
            .presentationBackgroundInteraction(.enabled(upThrough: smallest))
    }

    /// A sheet that is the task itself and wants the whole screen.
    func apexTaskSheet() -> some View {
        self
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
            .presentationCornerRadius(30)
    }
}
