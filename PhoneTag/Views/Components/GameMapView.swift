import SwiftUI
import MapKit

struct GameMapView: View {
    @Binding var cameraPosition: MapCameraPosition
    let homeBase: CLLocationCoordinate2D?        // my safe zone 1
    let homeBase2: CLLocationCoordinate2D?       // my safe zone 2
    let homeBaseColor: Color
    let otherPlayersHomeBases: [(name: String, coordinate: CLLocationCoordinate2D, color: Color)]
    let tempHomeBase: CLLocationCoordinate2D?
    let safeZonePlacementNumber: Int             // 1 or 2 — which zone the temp pin belongs to
    let safeBases: [SafeBase]
    let tags: [Tag]
    let radarResult: RadarResult?
    let myTripwires: [Tripwire]
    let isSettingBase: Bool
    let isTagging: Bool
    var onTap: ((CLLocationCoordinate2D) -> Void)?
    var onCenterChanged: ((CLLocationCoordinate2D) -> Void)?

    var body: some View {
        ZStack {
            MapReader { proxy in
                Map(position: $cameraPosition) {
                    UserAnnotation()

                    // My Safe Zone 1
                    if let hb = homeBase {
                        Annotation("Safe Zone 1", coordinate: hb) {
                            ZStack {
                                Circle()
                                    .fill(homeBaseColor.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "shield.fill")
                                    .font(.callout)
                                    .foregroundStyle(homeBaseColor)
                            }
                            .shadow(radius: 2)
                        }
                        MapCircle(center: hb, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(homeBaseColor.opacity(0.15))
                            .stroke(homeBaseColor, lineWidth: 2)
                    }

                    // My Safe Zone 2
                    if let hb2 = homeBase2 {
                        Annotation("Safe Zone 2", coordinate: hb2) {
                            ZStack {
                                Circle()
                                    .fill(homeBaseColor.opacity(0.2))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "shield.lefthalf.filled")
                                    .font(.callout)
                                    .foregroundStyle(homeBaseColor)
                            }
                            .shadow(radius: 2)
                        }
                        MapCircle(center: hb2, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(homeBaseColor.opacity(0.15))
                            .stroke(homeBaseColor, lineWidth: 2)
                    }

                    // Other players' safe zones
                    ForEach(Array(otherPlayersHomeBases.enumerated()), id: \.offset) { _, player in
                        Annotation(player.name, coordinate: player.coordinate) {
                            ZStack {
                                Circle()
                                    .fill(player.color.opacity(0.2))
                                    .frame(width: 28, height: 28)
                                Image(systemName: "shield.fill")
                                    .font(.caption)
                                    .foregroundStyle(player.color)
                            }
                            .shadow(radius: 2)
                        }
                        MapCircle(center: player.coordinate, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(player.color.opacity(0.15))
                            .stroke(player.color, lineWidth: 2)
                    }

                    // Temporary pin during safe zone placement
                    if let temp = tempHomeBase {
                        let label = "Safe Zone \(safeZonePlacementNumber)"
                        Annotation(label, coordinate: temp) {
                            ZStack {
                                Circle()
                                    .fill(Color.orange.opacity(0.25))
                                    .frame(width: 32, height: 32)
                                Image(systemName: "shield.fill")
                                    .font(.callout)
                                    .foregroundStyle(.orange)
                            }
                            .shadow(radius: 2)
                        }
                        MapCircle(center: temp, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(.orange.opacity(0.15))
                            .stroke(.orange.opacity(0.5), lineWidth: 1)
                    }

                    // Safe bases — hits show "[target] tagged!", misses show "Miss"
                    // Home bases are rendered separately above; filter them out here.
                    ForEach(safeBases.filter { $0.type != .homeBase }) { safeBase in
                        let isHit = safeBase.type == .hitTag
                        let label: String = {
                            guard isHit else { return "Miss" }
                            // Prefer target name (who got hit); fall back to tagger name for old data
                            if let name = safeBase.targetName { return "\(name) tagged!" }
                            if let name = safeBase.taggerName { return "\(name) tagged!" }
                            return "Tagged!"
                        }()
                        Annotation(label, coordinate: safeBase.location) {
                            Image(systemName: isHit ? "burst.fill" : "xmark.circle.fill")
                                .font(.caption)
                                .foregroundStyle(isHit ? .red : .orange)
                                .shadow(radius: 2)
                        }
                        // Use the stored radius so hit zones (80m) render larger than miss zones (50m)
                        MapCircle(center: safeBase.location, radius: safeBase.effectiveRadius)
                            .foregroundStyle(isHit ? .red.opacity(0.08) : .orange.opacity(0.06))
                            .stroke(isHit ? .red.opacity(0.5) : .orange.opacity(0.4), lineWidth: 1)
                    }

                    // In-session submitted tags (ephemeral; backed by safe bases after reload)
                    ForEach(tags) { tag in
                        let coord = CLLocationCoordinate2D(
                            latitude: tag.guessedLocation.latitude,
                            longitude: tag.guessedLocation.longitude
                        )
                        let isHit = tag.isHit
                        let label: String = {
                            if case .hit(_, _, let name) = tag.result {
                                return "\(name) tagged!"
                            }
                            return "Miss"
                        }()
                        let radius = tag.tagType == .basic
                            ? GameConstants.basicTagRadius
                            : GameConstants.wideRadiusTagRadius

                        Annotation(label, coordinate: coord) {
                            Image(systemName: isHit ? "burst.fill" : "xmark.circle.fill")
                                .font(.title3)
                                .foregroundStyle(isHit ? .red : .orange)
                                .shadow(radius: 2)
                        }
                        MapCircle(center: coord, radius: radius)
                            .foregroundStyle(isHit ? .red.opacity(0.1) : .orange.opacity(0.08))
                            .stroke(isHit ? .red.opacity(0.5) : .orange.opacity(0.4), lineWidth: 1.5)
                    }

                    // Radar circles (two candidate locations)
                    if let radar = radarResult {
                        ForEach(Array(radar.locations.enumerated()), id: \.offset) { index, coord in
                            let label = index == 0 ? "A" : "B"
                            Annotation(label, coordinate: coord) {
                                Text(label)
                                    .font(.caption.bold())
                                    .foregroundStyle(.white)
                                    .frame(width: 24, height: 24)
                                    .background(.blue, in: Circle())
                                    .shadow(color: .blue.opacity(0.6), radius: 4)
                            }
                            MapCircle(center: coord, radius: radar.radius)
                                .foregroundStyle(.blue.opacity(0.06))
                                .stroke(.blue.opacity(0.35), lineWidth: 2)
                        }
                    }

                    // Tripwires (only the current player's)
                    ForEach(myTripwires) { tripwire in
                        if let center = tripwire.path.first {
                            let isTriggered = tripwire.triggeredBy != nil
                            Annotation("Tripwire", coordinate: center) {
                                Image(systemName: isTriggered ? "bolt.circle.fill" : "sensor.fill")
                                    .font(.caption)
                                    .foregroundStyle(isTriggered ? .orange : .purple)
                                    .shadow(color: .purple.opacity(0.5), radius: 3)
                            }
                            MapCircle(center: center, radius: GameConstants.tripwireRadius)
                                .foregroundStyle(
                                    isTriggered
                                        ? .orange.opacity(0.12)
                                        : .purple.opacity(0.1)
                                )
                                .stroke(
                                    isTriggered ? .orange.opacity(0.6) : .purple.opacity(0.5),
                                    lineWidth: 1.5
                                )
                        }
                    }
                }
                .mapStyle(.standard(elevation: .realistic))
                .mapControls {
                    MapUserLocationButton()
                    MapCompass()
                    MapScaleView()
                }
                .onMapCameraChange(frequency: .continuous) { context in
                    onCenterChanged?(context.region.center)
                }
                .onTapGesture { screenPoint in
                    guard isSettingBase,
                          let coordinate = proxy.convert(screenPoint, from: .local) else { return }
                    onTap?(coordinate)
                }
            }

            // Crosshair overlay when tagging
            if isTagging {
                Image(systemName: "scope")
                    .font(.system(size: 48))
                    .foregroundStyle(.red.opacity(0.8))
                    .allowsHitTesting(false)
            }
        }
    }
}
