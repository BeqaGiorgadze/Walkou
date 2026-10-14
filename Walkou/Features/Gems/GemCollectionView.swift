import SwiftUI
import SwiftData

/// "Your Gems": level, shelf of every gem type, rarest finds.
struct GemCollectionView: View {
    @Query(sort: \WorkoutRecord.startDate, order: .reverse) private var workouts: [WorkoutRecord]

    private var lifetime: GemTally { workouts.reduce(GemTally()) { $0 + $1.gemTally } }
    private var lifetimePoints: Int { workouts.reduce(0) { $0 + $1.gemPoints } }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Your Gems")
                    .font(.system(size: 34, weight: .bold))

                levelCard

                Text("Shelf").font(.system(size: 22, weight: .bold))
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 4), spacing: 10) {
                    ForEach(GemKind.shelfOrder) { kind in
                        shelfTile(kind)
                    }
                }

                if !rarestFinds.isEmpty {
                    Text("Rarest finds").font(.system(size: 22, weight: .bold))
                    VStack(spacing: 0) {
                        ForEach(Array(rarestFinds.enumerated()), id: \.offset) { index, find in
                            HStack(spacing: 14) {
                                GemImage(kind: find.kind, size: 44)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(find.kind.shelfName).font(.system(size: 17, weight: .bold))
                                    Text(find.subtitle)
                                        .font(.system(size: 13))
                                        .foregroundStyle(Theme.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 10)
                            if index < rarestFinds.count - 1 {
                                Rectangle().fill(Theme.separator).frame(height: 1)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
                }

                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Gem Shop").font(.system(size: 20, weight: .bold))
                        Text("Coming next: spend points on themes")
                            .font(.system(size: 14, weight: .medium))
                            .opacity(0.9)
                    }
                    Spacer()
                    Image(systemName: "lock.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Color(hex: 0x1C1C28))
                        .frame(width: 40, height: 40)
                        .background(.white, in: Circle())
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
                .background(LinearGradient(colors: [Theme.orange, Color(hex: 0xFF5C9A)], startPoint: .leading, endPoint: .trailing),
                            in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 24)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
    }

    private var levelCard: some View {
        let level = GemLevel.forPoints(lifetimePoints)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("LEVEL \(level.number)")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(Color(hex: 0xFFD25A))
                    Text(level.title)
                        .font(.hero(26))
                        .foregroundStyle(.white)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(Format.steps(lifetime.total))
                        .font(.system(size: 26, weight: .bold))
                        .foregroundStyle(.white)
                    Text("gems found")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.65))
                }
            }
            LevelProgressView(points: lifetimePoints)
        }
        .padding(20)
        .background(Theme.gemBackground, in: RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
    }

    private func shelfTile(_ kind: GemKind) -> some View {
        let count = lifetime[kind]
        let found = count > 0
        return VStack(spacing: 4) {
            GemImage(kind: kind, size: 50, glow: found)
                .opacity(found ? 1 : 0.18)
                .saturation(found ? 1 : 0)
            Text(kind.shelfName)
                .font(.system(size: 11, weight: .semibold))
                .multilineTextAlignment(.center)
                .lineLimit(2, reservesSpace: true)
            Text(found ? "×\(count)" : (kind.isSeasonal ? "🔒 Seasonal" : "Not found"))
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(found ? Theme.indigo : Theme.textSecondary)
        }
        .padding(.top, 12)
        .padding(.bottom, 10)
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20, style: .continuous))
    }

    private struct Find {
        let kind: GemKind
        let subtitle: String
    }

    /// Latest workouts with a legendary or special gem, rarest kind first.
    private var rarestFinds: [Find] {
        let rarity: [GemKind] = [.legendary, .heart, .amber, .rare]
        var finds: [Find] = []
        for workout in workouts {
            let tally = workout.gemTally
            guard let kind = rarity.first(where: { tally[$0] > 0 }), kind != .rare || finds.count < 1 else { continue }
            let place = workout.routeName ?? workout.title
            finds.append(Find(kind: kind, subtitle: "\(place) · \(workout.startDate.formatted(.dateTime.day().month(.abbreviated)))"))
            if finds.count == 3 { break }
        }
        return finds
    }
}
