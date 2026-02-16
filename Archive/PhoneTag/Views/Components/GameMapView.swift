import SwiftUI
import MapKit

struct GameMapView: View {
    @Binding var cameraPosition: MapCameraPosition
    let homeBase: CLLocationCoordinate2D?
    let tempHomeBase: CLLocationCoordinate2D?
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

                    // Saved home base
                    if let hb = homeBase {
                        Annotation("Home Base", coordinate: hb) {
                            Image(systemName: "house.fill")
                                .font(.title2)
                                .foregroundStyle(.green)
                                .shadow(radius: 2)
                        }
                        MapCircle(center: hb, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(.green.opacity(0.15))
                            .stroke(.green, lineWidth: 2)
                    }

                    // Temporary pin during placement
                    if let temp = tempHomeBase {
                        Annotation("Home Base", coordinate: temp) {
                            Image(systemName: "house.fill")
                                .font(.title2)
                                .foregroundStyle(.orange)
                                .shadow(radius: 2)
                        }
                        MapCircle(center: temp, radius: GameConstants.homeBaseRadius)
                            .foregroundStyle(.orange.opacity(0.15))
                            .stroke(.orange.opacity(0.5), lineWidth: 1)
                    }

                    // Safe bases
                    ForEach(safeBases) { safeBase in
                        Annotation("Safe", coordinate: safeBase.location) {
                            Image(systemName: safeBase.type == .hitTag ? "shield.fill" : "shield")
                                .font(.caption)
                                .foregroundStyle(.yellow)
                                .shadow(radius: 2)
                        }
                        MapCircle(center: safeBase.location, radius: GameConstants.safeBaseRadius)
                            .foregroundStyle(.yellow.opacity(0.1))
                            .stroke(.yellow.opacity(0.6), lineWidth: 1)
                    }

                    // Submitted tags
                    ForEach(tags) { tag in
                        let coord = CLLocationCoordinate2D(
                            latitude: tag.guessedLocation.latitude,
                            longitude: tag.guessedLocation.longitude
                        )
                        let isHit = tag.isHit
                        let radius = tag.tagType == .basic
                            ? GameConstants.basicTagRadius
                            : GameConstants.wideRadiusTagRadius

                        Annotation(isHit ? "Hit" : "Miss", coordinate: coord) {
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
