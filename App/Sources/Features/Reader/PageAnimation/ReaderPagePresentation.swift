import SwiftUI

struct ReaderPagePresentation<Content: View, Next: View, Previous: View>: View {
    let mode: Int
    let page: Int
    let progress: Double
    var enabled = true
    var canPrevious = true
    var canNext = true
    var forward = true
    var touchSlop: Double = 10
    var pageHeight: Double = 0
    let turn: (Bool) async -> Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let next: () -> Next
    @ViewBuilder let previous: () -> Previous

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

    }

    @ViewBuilder private var animatedContent: some View {
        switch ReaderPresentationState(mode: mode, progress: progress, height: 0).animation {
        case .slide, .cover:
            HorizontalPageContainer(page: page, slide: mode == 1, forward: forward,
                enabled: enabled && progress == 0, canPrevious: canPrevious, canNext: canNext,
                touchSlop: touchSlop, turn: turn, content: content, next: next, previous: previous)
        case .simulation:
            if progress > 0 { content().modifier(NoAnimTransition()) }
            else { SimulationPageTransition(page: page, content: content) }
        case .scroll:
            ScrollPageContainer(progress: progress, page: page, pageHeight: pageHeight, turn: turn) {
                VStack(spacing: 0) { content(); next() }
            }
        case .none:
            content().modifier(NoAnimTransition())
        }
    }
}

private struct HorizontalPageContainer<Content: View, Next: View, Previous: View>: View {
    let page: Int
    let slide: Bool
    let forward: Bool
    let enabled: Bool
    let canPrevious: Bool
    let canNext: Bool
    let touchSlop: Double
    let turn: (Bool) async -> Bool
    @ViewBuilder let content: () -> Content
    @ViewBuilder let next: () -> Next
    @ViewBuilder let previous: () -> Previous
    @State private var offset: Double = 0
    @State private var settling = false
    @State private var horizontal: Bool?
    @State private var turnTask: Task<Void, Never>?
    @State private var gestureID = UUID()

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let offsets = ReaderHorizontalDrag(translation: offset, projected: offset, width: width).offsets(slide: slide)
            ZStack {
                pageContent.offset(x: offsets.current).zIndex(0)
                if offset < 0 {
                    next().offset(x: offsets.next).zIndex(1).accessibilityHidden(true)
                }
                if offset > 0 {
                    previous().offset(x: offsets.previous).zIndex(1).accessibilityHidden(true)
                }
            }.frame(width: width, height: geometry.size.height).clipped().contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: max(10, touchSlop))
                    .onChanged { value in
                        guard enabled, !settling else { return }
                        if horizontal == nil { horizontal = abs(value.translation.width) > abs(value.translation.height) }
                        guard horizontal == true else { return }
                        let delta = value.translation.width
                        offset = min(width, max(-width, delta)) * ((delta < 0 ? canNext : canPrevious) ? 1 : 0.15)
                    }
                    .onEnded { value in
                        defer { horizontal = nil }
                        guard enabled, !settling, horizontal == true else { return }
                        let target = ReaderHorizontalDrag(translation: value.translation.width,
                            projected: value.predictedEndTranslation.width, width: width)
                            .destination(canPrevious: canPrevious, canNext: canNext)
                        settle(target: target, width: width)
                    })
        }
        .onChange(of: page) { _, _ in resetOffset() }
        .onChange(of: enabled) { _, enabled in if !enabled && !settling { resetOffset() } }
        .onDisappear { gestureID = UUID(); turnTask?.cancel(); resetOffset(); settling = false }
    }

    @ViewBuilder private var pageContent: some View {
        if offset != 0 || settling { content() }
        else if slide {
            ZStack { content().modifier(SlidePageTransition(page: page, forward: forward)) }
                .animation(.easeOut(duration: 0.25), value: page)
        } else {
            ZStack { content().modifier(CoverPageTransition(page: page, forward: forward)) }
                .animation(.easeOut(duration: 0.25), value: page)
        }
    }

    private func settle(target: Bool?, width: Double) {
        settling = true
        let id = UUID(); gestureID = id
        withAnimation(.easeOut(duration: 0.2), completionCriteria: .logicallyComplete) {
            offset = target.map { $0 ? -width : width } ?? 0
        } completion: {
            guard gestureID == id else { return }
            guard let target else { settling = false; return }
            turnTask = Task { @MainActor in
                _ = await turn(target)
                guard gestureID == id else { return }
                resetOffset(); settling = false; turnTask = nil
            }
        }
    }

    private func resetOffset() {
        var transaction = Transaction(); transaction.disablesAnimations = true
        withTransaction(transaction) { offset = 0 }
    }
}
