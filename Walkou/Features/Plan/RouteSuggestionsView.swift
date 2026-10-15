import SwiftUI
import MapKit

/// Shows three routes that match the step goal, with their gems, and lets the user pick one.
struct RouteSuggestionsView: View {
    let plan: WorkoutPlan

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @AppStorage(SettingsKey.distanceUnit) private var unit: DistanceUnit = .kilometers

    @State private var routes: [PlannedRoute] = []
    @State private var selectedID: UUID?
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var camera: MapCameraPosition = .userLocation(fallback: .automatic)
    @State private var placingBonusFor: Set<UUID> = []
    @State private var arrows: [UUID: [Arrow]] = [:]
    @State private var selectionTask: Task<Void, Never>?

    private var selectedRoute: PlannedRoute? {
        routes.first { $0.id == selectedID } ?? routes.first
    }

    var body: some View {
        map
            .safeAreaInset(edge: .bottom, spacing: 0) { bottomPanel }
            .overlay { statusOverlay }
            .navigationTitle(plan.mode == .loop ? "Loop routes" : "One-way routes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await load() }
                    } label: {
                        Image(systemName: "shuffle")
                    }
                    .disabled(isLoading)
                    .accessibilityLabel("Suggest other routes")
                }
            }
            .task {
                if routes.isEmpty { await load() }
            }
            .onChange(of: selectedID) { _, _ in
                // Swiping the cards changes the selection many times; act once it settles.
                selectionTask?.cancel()
                selectionTask = Task {
                    try? await Task.sleep(for: .milliseconds(250))
                    guard !Task.isCancelled else { return }
                    frameSelectedRoute(animated: true)
                    placeBonusGemsIfNeeded()
                }
            }
            .onDisappear { selectionTask?.cancel() }
    }

    // MARK: - Map

    private var map: some View {
        // No rotation, so the direction arrows always point the right way.
        Map(position: $camera, interactionModes: [.pan, .zoom]) {
            UserAnnotation()

            ForEach(routes.filter { $0.id != selectedRoute?.id }) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color.opacity(0.45), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let route = selectedRoute {
                // Bonus detours under the route line.
                ForEach(route.gems.filter { !$0.detourPath.isEmpty }) { gem in
                    MapPolyline(coordinates: gem.detourPath)
                        .stroke(Color(hex: 0x1FB863), style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [1, 7]))
                }

                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color.opacity(0.25), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

                ForEach(arrows[route.id] ?? []) { arrow in
                    Annotation("", coordinate: arrow.coordinate, anchor: .center) {
                        Image(systemName: "chevron.up")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(route.color)
                            .frame(width: 18, height: 18)
                            .background(.white, in: Circle())
                            .rotationEffect(.degrees(arrow.bearing))
                    }
                    .annotationTitles(.hidden)
                }

                ForEach(route.gems) { gem in
                    Annotation("", coordinate: gem.coordinate, anchor: .center) {
                        VStack(spacing: 2) {
                            GemImage(kind: gem.kind, size: gem.kind.mapSize)
                            if let steps = gem.detourSteps {
                                Text("+\(Format.steps(steps)) steps")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 3)
                                    .background(Color(hex: 0x1FB863), in: Capsule())
                            }
                        }
                    }
                    .annotationTitles(.hidden)
                }

                if let start = route.start {
                    Annotation("Start", coordinate: start) {
                        RoutePin(symbol: "figure.walk", color: route.color)
                    }
                }
                if route.kind == .oneWay, let end = route.end {
                    Annotation("Finish", coordinate: end) {
                        RoutePin(symbol: "flag.checkered", color: .black)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .mapControls {
            MapScaleView()
        }
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 14) {
            if let route = selectedRoute {
                gemPreviewPill(route)
            }

            if !routes.isEmpty {
                ScrollView(.horizontal) {
                    LazyHStack(spacing: 12) {
                        ForEach(routes) { route in
                            RouteCard(
                                route: route,
                                plan: plan,
                                unit: unit,
                                isSelected: route.id == selectedRoute?.id
                            )
                            .containerRelativeFrame(.horizontal) { length, _ in length * 0.8 }
                            .id(route.id)
                            .onTapGesture {
                                withAnimation(.snappy) { selectedID = route.id }
                            }
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollIndicators(.hidden)
                .scrollTargetBehavior(.viewAligned)
                .scrollPosition(id: $selectedID)
                .contentMargins(.horizontal, 16, for: .scrollContent)
            }

            Button {
                guard let route = selectedRoute else { return }
                Haptics.tap()
                model.startWorkout(plan: plan, route: route)
                dismiss()
            } label: {
                Label("START \(plan.activity.verb.uppercased())", systemImage: plan.activity.symbol)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(selectedRoute == nil)
            .opacity(selectedRoute == nil ? 0.5 : 1)
            .padding(.horizontal, 16)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
        .background(.regularMaterial)
    }

    private func gemPreviewPill(_ route: PlannedRoute) -> some View {
        let pendingBonus = route.bonusGemsPlaced ? 0 : GemPlanner.bonusCount(forDistance: route.distance)
        let count = route.gems.count + pendingBonus
        let points = route.gemPoints + pendingBonus * GemKind.bonus.points
        return HStack(spacing: 6) {
            GemImage(kind: .common, size: 18, glow: false)
            Text("\(count) gems on this \(plan.mode == .loop ? "loop" : "route") · up to \(points) pts")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.white)
        }
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 7)
        .background(Theme.gemInk.opacity(0.92), in: Capsule())
    }

    @ViewBuilder
    private var statusOverlay: some View {
        if isLoading {
            VStack(spacing: 14) {
                ProgressView().controlSize(.large)
                Text("Finding \(Format.steps(plan.goalSteps))-step routes…")
                    .font(.system(size: 16, weight: .semibold))
            }
            .padding(28)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        } else if let errorMessage {
            VStack(spacing: 14) {
                Image(systemName: "map")
                    .font(.system(size: 34, weight: .semibold))
                    .foregroundStyle(Theme.orange)
                Text(errorMessage)
                    .font(.system(size: 15, weight: .medium))
                    .multilineTextAlignment(.center)
                Button("Try again") { Task { await load() } }
                    .font(.system(size: 16, weight: .bold))
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        }
    }

    // MARK: - Loading

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        model.location.startPreviewUpdates()
        var origin = model.location.lastLocation?.coordinate
        // Give GPS a few seconds to get a first fix.
        var attempts = 0
        while origin == nil && attempts < 20 {
            try? await Task.sleep(for: .milliseconds(500))
            origin = model.location.lastLocation?.coordinate
            attempts += 1
        }
        guard let origin else {
            errorMessage = model.location.isDenied
                ? "Location access is off. Turn it on in Settings to get routes."
                : "We can't find your location yet. Make sure you're outdoors or near a window."
            return
        }

        do {
            // Planning and gem placement run off the main thread so the screen never stalls.
            let plan = self.plan
            let found = try await Task.detached(priority: .userInitiated) {
                try await RoutePlanner().suggestions(from: origin, plan: plan).map { route in
                    var route = route
                    route.gems = GemPlanner.routeGems(for: route)
                    return route
                }
            }.value
            placingBonusFor = []
            arrows = Dictionary(uniqueKeysWithValues: found.map { ($0.id, Self.directionArrows(for: $0)) })
            routes = found
            selectedID = found.first?.id
            // Let the map lay out with its new content before moving the camera, otherwise the
            // change can be dropped while the map is still following the user's location.
            try? await Task.sleep(for: .milliseconds(150))
            frameSelectedRoute(animated: false)
            placeBonusGemsIfNeeded()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func placeBonusGemsIfNeeded() {
        guard let route = selectedRoute, !route.bonusGemsPlaced, !placingBonusFor.contains(route.id) else { return }
        placingBonusFor.insert(route.id)
        let stride = plan.activity.strideLength
        Task {
            let bonus = await Task.detached(priority: .utility) {
                await GemPlanner.bonusGems(for: route, strideLength: stride)
            }.value
            if let index = routes.firstIndex(where: { $0.id == route.id }) {
                withAnimation(.snappy) {
                    routes[index].gems.append(contentsOf: bonus)
                    routes[index].bonusGemsPlaced = true
                }
            }
            placingBonusFor.remove(route.id)
        }
    }

    /// Fits the selected route (and you) into the visible part of the map.
    private func frameSelectedRoute(animated: Bool) {
        guard let route = selectedRoute, !route.coordinates.isEmpty else { return }
        var points = route.coordinates
        if let here = model.location.lastLocation?.coordinate { points.append(here) }
        let lats = points.map(\.latitude), lons = points.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        let latSpan = max(0.004, (maxLat - minLat) * 1.5)
        let lonSpan = max(0.004, (maxLon - minLon) * 1.4)
        let region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: MKCoordinateSpan(latitudeDelta: latSpan, longitudeDelta: lonSpan)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.5)) { camera = .region(region) }
        } else {
            camera = .region(region)
        }
    }

    struct Arrow: Identifiable {
        let id: Int
        let coordinate: CLLocationCoordinate2D
        let bearing: Double
    }

    /// Small arrows along the route showing which way it goes.
    private static func directionArrows(for route: PlannedRoute) -> [Arrow] {
        let tracker = RouteTracker(route: route)
        let total = tracker.totalDistance
        guard total > 200 else { return [] }
        let count = min(8, max(3, Int(total / 600)))
        // Offset by half a gem spacing so arrows sit between gems.
        return (0..<count).compactMap { index in
            let along = total * (Double(index) + 0.5) / Double(count) + GemPlanner.spacing / 2
            guard along < total - 30,
                  let point = tracker.coordinate(atDistance: along),
                  let before = tracker.coordinate(atDistance: along - 12),
                  let after = tracker.coordinate(atDistance: along + 12) else { return nil }
            return Arrow(id: index, coordinate: point, bearing: Geo.bearing(from: before, to: after))
        }
    }
}

// MARK: - Pieces

private struct RouteCard: View {
    let route: PlannedRoute
    let plan: WorkoutPlan
    let unit: DistanceUnit
    let isSelected: Bool

    var body: some View {
        let steps = route.estimatedSteps(for: plan.activity)
        let difference = plan.goalSteps > 0 ? Double(steps - plan.goalSteps) / Double(plan.goalSteps) : 0
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Capsule().fill(route.color).frame(width: 28, height: 6).padding(.top, 8)
                Spacer()
                Text(differenceLabel(difference))
                    .font(.system(size: 12, weight: .bold))
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(abs(difference) <= 0.1 ? Theme.green.opacity(0.18) : Theme.orange.opacity(0.18), in: Capsule())
                    .foregroundStyle(abs(difference) <= 0.1 ? Theme.green : Theme.orange)
            }
            Text(route.name)
                .font(.system(size: 18, weight: .bold))
                .lineLimit(2, reservesSpace: true)
            HStack(spacing: 0) {
                MetricTile(title: "Distance", value: Format.distanceValue(route.distance, unit: unit), unit: unit.abbreviation)
                MetricTile(title: "Steps", value: "~\(Format.steps(steps))")
                MetricTile(title: "Time", value: Format.durationEstimate(plan.activity.estimatedDuration(forDistance: route.distance)))
            }
            Rectangle().fill(Theme.separator).frame(height: 1)
            HStack(spacing: 10) {
                gemCount(.common, "\(route.gemCount(.common))")
                gemCount(.rare, "\(route.gemCount(.rare))")
                gemCount(.legendary, "\(route.gemCount(.legendary))")
                let bonus = route.bonusGemsPlaced ? route.gemCount(.bonus) : GemPlanner.bonusCount(forDistance: route.distance)
                if bonus > 0 { gemCount(.bonus, "+\(bonus)") }
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? route.color : .clear, lineWidth: 2.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    private func gemCount(_ kind: GemKind, _ value: String) -> some View {
        HStack(spacing: 3) {
            GemImage(kind: kind, size: 20, glow: false)
            Text(value).font(.system(size: 14, weight: .bold))
        }
    }

    private func differenceLabel(_ difference: Double) -> String {
        let percent = Int((difference * 100).rounded())
        if abs(percent) <= 2 { return "On target" }
        return percent > 0 ? "+\(percent)% steps" : "\(percent)% steps"
    }
}

struct RoutePin: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .bold))
            .foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(color, in: Circle())
            .overlay(Circle().strokeBorder(.white, lineWidth: 3))
            .shadow(color: .black.opacity(0.25), radius: 4, y: 2)
    }
}
