import SwiftUI
import MapKit

/// Shows three routes that match the step goal and lets the user pick one.
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
                focusOnSelectedRoute()
            }
    }

    // MARK: - Map

    private var map: some View {
        Map(position: $camera) {
            UserAnnotation()

            ForEach(routes.filter { $0.id != selectedRoute?.id }) { route in
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color.opacity(0.4), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
            }

            if let route = selectedRoute {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color.opacity(0.25), style: StrokeStyle(lineWidth: 16, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: route.coordinates)
                    .stroke(route.color, style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))

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
            MapCompass()
            MapScaleView()
        }
    }

    // MARK: - Bottom panel

    private var bottomPanel: some View {
        VStack(spacing: 14) {
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
            let found = try await RoutePlanner().suggestions(from: origin, plan: plan)
            withAnimation(.snappy) {
                routes = found
                selectedID = found.first?.id
            }
            focusOnSelectedRoute()
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func focusOnSelectedRoute() {
        guard let route = selectedRoute, !route.coordinates.isEmpty else { return }
        let rect = MKPolyline(coordinates: route.coordinates, count: route.coordinates.count).boundingMapRect
        // Pad generously, with extra room at the bottom for the route cards.
        let padded = MKMapRect(
            x: rect.minX - rect.width * 0.2,
            y: rect.minY - rect.height * 0.25,
            width: rect.width * 1.4,
            height: rect.height * 1.9
        )
        withAnimation(.easeInOut(duration: 0.6)) {
            camera = .rect(padded)
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
        }
        .padding(16)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .strokeBorder(isSelected ? route.color : .clear, lineWidth: 2.5)
        )
        .contentShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
