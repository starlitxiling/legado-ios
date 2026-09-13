import SwiftUI

struct ReaderPagePresentation<Content: View, Next: View>: View {
    let mode: Int
    let page: Int
    let progress: Double
    let turn: (Bool) async -> Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let next: () -> Next
    @State private var previousPage: Int?
    @State private var forward = true

    var body: some View {
        GeometryReader { geometry in
            let state = ReaderPresentationState(mode: mode, progress: progress, height: geometry.size.height)
            ZStack(alignment: .top) {
                animatedContent
                if state.revealHeight > 0 {
                    next().frame(width: geometry.size.width, height: geometry.size.height)
                        .mask(alignment: .top) { Rectangle().frame(height: state.revealHeight) }
                    Rectangle().fill(Color.accentColor).frame(height: 1).offset(y: state.lineOffset)
                }
            }.clipped()
        }
        .onChange(of: page, initial: true) { old, new in
            forward = new >= (previousPage ?? old)
            previousPage = new
        }
    }

    @ViewBuilder private var animatedContent: some View {
        switch ReaderPresentationState(mode: mode, progress: progress, height: 0).animation {
        case .slide:
            ZStack { content().modifier(SlidePageTransition(page: page, forward: forward)) }
                .clipped().animation(progress > 0 ? nil : .easeOut(duration: 0.25), value: page)
        case .simulation:
            if progress > 0 { content().modifier(NoAnimTransition()) }
            else { SimulationPageTransition(page: page, content: content) }
        case .scroll:
            ScrollPageContainer(progress: progress, page: page, turn: turn) {
                VStack(spacing: 0) { content(); next() }
            }
        case .none:
            content().modifier(NoAnimTransition())
        case .cover:
            ZStack { content().modifier(CoverPageTransition(page: page)) }
                .clipped().animation(progress > 0 ? nil : .easeOut(duration: 0.25), value: page)
        }
    }
}
