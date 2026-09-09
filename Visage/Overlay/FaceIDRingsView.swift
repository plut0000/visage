import SwiftUI

enum ScanVisualState: Equatable {
    case idle
    case scanning
    case success
    case failure
}

struct FaceIDRingsView: View {
    let state: ScanVisualState

    @State private var spin = false
    @State private var pulse = false
    @State private var shake: CGFloat = 0
    @State private var checkProgress: CGFloat = 0

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { index in
                Capsule(style: .continuous)
                    .strokeBorder(ringColor.opacity(ringOpacity(index)), lineWidth: ringWidth(index))
                    .frame(width: ringSize(index).width, height: ringSize(index).height)
                    .rotation3DEffect(.degrees(spin ? 18 : -18), axis: (x: 1, y: 0, z: 0))
                    .rotationEffect(.degrees(spin ? Double(index + 1) * 22 : Double(index + 1) * -16))
                    .scaleEffect(pulse && state == .scanning ? 1.04 : 1)
            }

            if state == .success {
                CheckmarkShape()
                    .trim(from: 0, to: checkProgress)
                    .stroke(Color.green, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                    .frame(width: 28, height: 28)
            }

            if state == .failure {
                Image(systemName: "xmark")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(.red)
            }
        }
        .offset(x: shake)
        .onChange(of: state) { _, newValue in
            handle(newValue)
        }
        .onAppear { handle(state) }
    }

    private var ringColor: Color {
        switch state {
        case .success: return .green
        case .failure: return .red
        default: return .white
        }
    }

    private func ringSize(_ index: Int) -> CGSize {
        let base: CGFloat = 36
        let extra = CGFloat(index) * 16
        return CGSize(width: base + extra, height: (base + extra) * 0.92)
    }

    private func ringWidth(_ index: Int) -> CGFloat {
        index == 0 ? 2.4 : 1.6
    }

    private func ringOpacity(_ index: Int) -> Double {
        switch state {
        case .idle: return 0.18 - Double(index) * 0.03
        case .scanning: return 0.9 - Double(index) * 0.18
        case .success: return 0.85
        case .failure: return 0.7
        }
    }

    private func handle(_ newValue: ScanVisualState) {
        switch newValue {
        case .idle:
            withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                spin = true
            }
            pulse = false
            checkProgress = 0
        case .scanning:
            withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) {
                spin = true
            }
            withAnimation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true)) {
                pulse = true
            }
        case .success:
            pulse = false
            spin = false
            withAnimation(.easeOut(duration: 0.35)) {
                checkProgress = 1
            }
        case .failure:
            pulse = false
            spin = false
            withAnimation(.default) {
                shake = 10
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                withAnimation(.default) { shake = -8 }
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.16) {
                withAnimation(.default) { shake = 0 }
            }
        }
    }
}

private struct CheckmarkShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.minX + rect.width * 0.38, y: rect.maxY - rect.height * 0.18))
        path.addLine(to: CGPoint(x: rect.maxX - rect.width * 0.1, y: rect.minY + rect.height * 0.18))
        return path
    }
}

struct OverlayRootView: View {
    @Bindable var controller: OverlayController

    var body: some View {
        GeometryReader { geo in
            VStack {
                pill
                    .onTapGesture {
                        controller.handleRetryTap()
                    }
                Spacer()
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding(.top, 2)
    }

    private var pill: some View {
        let expanded = controller.phase == .scanning || controller.phase == .success || controller.phase == .failure
        return ZStack {
            RoundedRectangle(cornerRadius: expanded ? 28 : 18, style: .continuous)
                .fill(.black)
            FaceIDRingsView(state: visualState)
                .padding(.top, expanded ? 18 : 2)
        }
        .frame(width: expanded ? 220 : 168, height: expanded ? 132 : 34)
        .opacity(controller.phase == .hidden ? 0 : 1)
        .animation(.spring(duration: 0.42, bounce: 0.18), value: expanded)
        .animation(.easeInOut(duration: 0.2), value: controller.phase)
    }

    private var visualState: ScanVisualState {
        switch controller.phase {
        case .scanning: return .scanning
        case .success: return .success
        case .failure: return .failure
        default: return .idle
        }
    }
}
