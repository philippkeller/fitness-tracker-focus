import SwiftUI

/// A shareable card for the records one exercise set in a workout. Uses fixed dark colors so the
/// rendered image looks the same in light and dark mode.
struct RecordCard: View {
    let record: ExerciseRecord
    let workoutName: String
    let date: Date

    static let gold = Color(red: 1.0, green: 0.80, blue: 0.30)
    static let deepGold = Color(red: 0.72, green: 0.48, blue: 0.10)
    private static let green = Color(red: 0.35, green: 0.85, blue: 0.50)

    var body: some View {
        VStack(spacing: 20) {
            header
            medal
            VStack(spacing: 6) {
                Text(record.hits.count > 1 ? "NEW PERSONAL RECORDS" : "NEW PERSONAL RECORD")
                    .font(.caption.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(Self.gold)
                Text(record.exercise)
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.6)
            }
            VStack(spacing: 10) {
                ForEach(record.hits) { hit in
                    hitRow(hit)
                }
            }
            setList
        }
        .padding(24)
        .foregroundStyle(.white)
        .background(background)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Self.gold.opacity(0.35), lineWidth: 1))
        .environment(\.colorScheme, .dark)
    }

    private var header: some View {
        HStack {
            Label("FocusLift", systemImage: "dumbbell.fill")
                .font(.footnote.weight(.bold))
            Spacer()
            Text(date.formatted(date: .abbreviated, time: .omitted))
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.6))
        }
    }

    private var medal: some View {
        HStack(spacing: 6) {
            Image(systemName: "laurel.leading")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Self.gold.opacity(0.85))
            ZStack {
                Circle()
                    .fill(AngularGradient(
                        colors: [Self.gold, Self.deepGold, Self.gold, .white.opacity(0.9), Self.gold, Self.deepGold, Self.gold],
                        center: .center))
                Circle()
                    .strokeBorder(.white.opacity(0.55), lineWidth: 2)
                    .padding(8)
                Image(systemName: "trophy.fill")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundStyle(Color(red: 0.35, green: 0.22, blue: 0.02))
            }
            .frame(width: 96, height: 96)
            .shadow(color: Self.gold.opacity(0.55), radius: 22)
            Image(systemName: "laurel.trailing")
                .font(.system(size: 44, weight: .medium))
                .foregroundStyle(Self.gold.opacity(0.85))
        }
    }

    private func hitRow(_ hit: RecordHit) -> some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text(hit.kind.title.uppercased())
                    .font(.caption2.weight(.semibold))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.6))
                Text(hit.value)
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 4) {
                Text(hit.gain)
                    .font(.subheadline.weight(.bold))
                    .monospacedDigit()
                    .foregroundStyle(Self.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Self.green.opacity(0.15), in: Capsule())
                Text("was \(hit.previous)")
                    .font(.caption)
                    .monospacedDigit()
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .padding(14)
        .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    /// Today's sets with the record sets highlighted, so it's clear where the record happened.
    private var setList: some View {
        VStack(spacing: 0) {
            ForEach(Array(record.sets.enumerated()), id: \.element.id) { index, set in
                let hits = record.hits(for: set)
                HStack(spacing: 10) {
                    Text("\(index + 1)")
                        .font(.caption.weight(.bold))
                        .frame(width: 22, height: 22)
                        .background(hits.isEmpty ? Color.white.opacity(0.1) : Self.gold, in: Circle())
                        .foregroundStyle(hits.isEmpty ? Color.white.opacity(0.7) : Color.black)
                    Text(Fmt.set(set))
                        .font(.subheadline.weight(hits.isEmpty ? .regular : .semibold))
                        .monospacedDigit()
                    Spacer(minLength: 8)
                    if !hits.isEmpty {
                        Label(hits.map(\.kind.badge).joined(separator: " · "), systemImage: "medal.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(Self.gold)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                .foregroundStyle(hits.isEmpty ? Color.white.opacity(0.7) : Color.white)
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(hits.isEmpty ? Color.clear : Self.gold.opacity(0.12),
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            Text(workoutName)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.5))
                .padding(.top, 10)
        }
    }

    private var background: some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.10, green: 0.11, blue: 0.16), Color(red: 0.03, green: 0.03, blue: 0.05)],
                startPoint: .top, endPoint: .bottom)
            RadialGradient(
                colors: [Self.gold.opacity(0.28), .clear],
                center: UnitPoint(x: 0.5, y: 0.18), startRadius: 0, endRadius: 240)
        }
    }
}

/// Renders a record card to an image and offers it in the share sheet (X, Messages, Photos…).
struct RecordShareButton: View {
    let record: ExerciseRecord
    let workoutName: String
    let date: Date
    @Environment(\.displayScale) private var displayScale
    @State private var image: Image?
    @State private var renderFailed = false

    var body: some View {
        Group {
            if let image {
                ShareLink(item: image, preview: SharePreview(record.exercise, image: image)) {
                    Label("Share", systemImage: "square.and.arrow.up")
                        .frame(maxWidth: .infinity)
                }
            } else if renderFailed {
                Button("Retry share image") { render() }
                    .frame(maxWidth: .infinity)
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(RecordCard.deepGold)
        .task { render() }
    }

    @MainActor
    private func render() {
        renderFailed = false
        // Include the border in the 360 pt canvas: at 3× the export is 1080 px wide.
        let card = RecordCard(record: record, workoutName: workoutName, date: date)
            .frame(width: 324)
            .padding(18)
            .environment(\.dynamicTypeSize, .medium)
            .background(Color.black)
        let renderer = ImageRenderer(content: card)
        renderer.scale = max(displayScale, 3)
        if let uiImage = renderer.uiImage {
            image = Image(uiImage: uiImage)
        } else {
            renderFailed = true
        }
    }
}
