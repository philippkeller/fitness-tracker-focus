import SwiftUI

/// Trophy card for one new record. Fixed dark colors, so it looks the same in light mode and as a shared image.
struct RecordCard: View {
    let record: RecordHit
    let date: Date

    static let gold = LinearGradient(
        colors: [
            Color(red: 1.0, green: 0.9, blue: 0.55),
            Color(red: 0.96, green: 0.7, blue: 0.24),
            Color(red: 0.78, green: 0.52, blue: 0.14),
        ],
        startPoint: .top, endPoint: .bottom)

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("PERSONAL RECORD", systemImage: "sparkles")
                    .font(.caption2.weight(.heavy))
                    .tracking(1.5)
                Spacer()
                Text(date.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(.white.opacity(0.6))

            trophy
                .padding(.top, 18)

            Text(record.kind.title.uppercased())
                .font(.caption.weight(.heavy))
                .tracking(2)
                .foregroundStyle(Self.gold)
                .padding(.top, 14)

            Text(record.exercise)
                .font(.title2.weight(.bold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.top, 4)

            Text(record.value)
                .font(.system(size: 52, weight: .black, design: .rounded))
                .foregroundStyle(Self.gold)
                .lineLimit(1)
                .minimumScaleFactor(0.5)
                .padding(.top, 2)

            HStack(spacing: 8) {
                Label(record.gain, systemImage: "arrow.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(Color(red: 0.4, green: 0.95, blue: 0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.green.opacity(0.18), in: Capsule())
                Text("was \(record.previous)")
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(.white.opacity(0.55))
            }

            if !record.detail.isEmpty {
                Text(record.detail)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 7)
                    .background(.white.opacity(0.08), in: Capsule())
                    .padding(.top, 16)
            }

            HStack(spacing: 6) {
                Image(systemName: "dumbbell.fill")
                Text("FocusLift")
            }
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.35))
            .padding(.top, 20)
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Self.gold, lineWidth: 1.5)
                .opacity(0.6)
        }
    }

    /// Glowing trophy in a gold ring between two laurel branches.
    private var trophy: some View {
        HStack(spacing: 2) {
            Image(systemName: "laurel.leading")
            ZStack {
                Circle()
                    .fill(RadialGradient(
                        colors: [Color(red: 1, green: 0.8, blue: 0.35).opacity(0.45), .clear],
                        center: .center, startRadius: 0, endRadius: 64))
                    .frame(width: 128, height: 128)
                Circle()
                    .strokeBorder(Self.gold, lineWidth: 2)
                    .frame(width: 92, height: 92)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 44))
                    .shadow(color: .orange.opacity(0.7), radius: 12)
            }
            .frame(width: 100, height: 100)
            Image(systemName: "laurel.trailing")
        }
        .font(.system(size: 56))
        .foregroundStyle(Self.gold)
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.13, green: 0.11, blue: 0.2), Color(red: 0.04, green: 0.04, blue: 0.07)],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Color(red: 1, green: 0.7, blue: 0.25).opacity(0.3), .clear],
                center: UnitPoint(x: 0.5, y: 0.28), startRadius: 0, endRadius: 240)
        }
    }

    /// The cards as a picture for sharing (e.g. on X), stacked on a black canvas.
    @MainActor
    static func shareImage(_ records: [RecordHit], date: Date) -> Image? {
        let content = VStack(spacing: 16) {
            ForEach(records) { RecordCard(record: $0, date: date) }
        }
        .padding(28)
        .frame(width: 420)
        .background(Color.black)
        let renderer = ImageRenderer(content: content)
        renderer.scale = 3
        return renderer.uiImage.map { Image(uiImage: $0) }
    }
}

/// A record card that pops in, with a share button under it.
struct RecordRow: View {
    let record: RecordHit
    let date: Date

    @State private var appeared = false
    @State private var image: Image?

    var body: some View {
        VStack(spacing: 10) {
            RecordCard(record: record, date: date)
                .scaleEffect(appeared ? 1 : 0.85)
                .opacity(appeared ? 1 : 0)
            if let image {
                ShareLink(item: image, preview: SharePreview("\(record.exercise) – \(record.kind.title)", image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .font(.callout.bold())
                }
                .buttonStyle(.bordered)
                .tint(.orange)
            }
        }
        .onAppear {
            if image == nil { image = RecordCard.shareImage([record], date: date) }
            withAnimation(.spring(duration: 0.6, bounce: 0.4)) { appeared = true }
        }
    }
}
