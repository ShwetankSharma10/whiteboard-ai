import 'dart:math' as math;
import 'dart:ui';

/// High-precision Web Mercator projection utility converting between
/// geographical Latitude/Longitude coordinates and 2D Whiteboard Scene space.
class MercatorProjection {
  const MercatorProjection({this.worldSize = 4096.0});

  /// The width and height of the flat world plane in whiteboard scene units.
  final double worldSize;

  /// Clamps latitude to Web Mercator limits (-85.05112878 to 85.05112878 degrees).
  static const double maxLatitude = 85.05112877980659;
  static const double minLatitude = -85.05112877980659;

  /// Converts (latitude, longitude) in degrees to a 2D scene [Offset].
  Offset latLngToScene(double latitude, double longitude) {
    final clampedLat = latitude.clamp(minLatitude, maxLatitude);
    final clampedLng = longitude.clamp(-180.0, 180.0);

    // X coordinate: linear map from [-180, 180] to [0, worldSize]
    final x = (clampedLng + 180.0) / 360.0 * worldSize;

    // Y coordinate: Mercator projection formula
    final sinLat = math.sin(clampedLat * math.pi / 180.0);
    final yNorm =
        0.5 - math.log((1.0 + sinLat) / (1.0 - sinLat)) / (4.0 * math.pi);
    final y = yNorm * worldSize;

    return Offset(x, y);
  }

  /// Converts a 2D scene [Offset] back to (latitude, longitude) in degrees.
  (double lat, double lng) sceneToLatLng(Offset scenePoint) {
    final lng = (scenePoint.dx / worldSize) * 360.0 - 180.0;

    final yNorm = 0.5 - (scenePoint.dy / worldSize);
    final latRad =
        2.0 * math.atan(math.exp(yNorm * 2.0 * math.pi)) - (math.pi / 2.0);
    final lat = latRad * 180.0 / math.pi;

    return (lat.clamp(minLatitude, maxLatitude), lng.clamp(-180.0, 180.0));
  }

  /// Calculates geodesic distance between two points in kilometers (Haversine formula).
  static double distanceBetweenKm(
    double lat1,
    double lng1,
    double lat2,
    double lng2,
  ) {
    const earthRadiusKm = 6371.0;
    final dLat = (lat2 - lat1) * math.pi / 180.0;
    final dLng = (lng2 - lng1) * math.pi / 180.0;

    final a =
        math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLng / 2) *
            math.sin(dLng / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadiusKm * c;
  }
}

/// Metadata tracking the geographic location and identity of the person
/// who last edited the whiteboard.
class LastEditorLocation {
  const LastEditorLocation({
    required this.latitude,
    required this.longitude,
    required this.locationName,
    required this.editorName,
    required this.updatedAtMs,
  });

  final double latitude;
  final double longitude;
  final String locationName;
  final String editorName;
  final int updatedAtMs;

  Offset get scenePosition =>
      const MercatorProjection().latLngToScene(latitude, longitude);

  Map<String, dynamic> toJson() => {
    'latitude': latitude,
    'longitude': longitude,
    'locationName': locationName,
    'editorName': editorName,
    'updatedAtMs': updatedAtMs,
  };

  factory LastEditorLocation.fromJson(Map<String, dynamic> json) {
    return LastEditorLocation(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 20.5937,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 78.9629,
      locationName: (json['locationName'] as String?) ?? 'Unknown Location',
      editorName: (json['editorName'] as String?) ?? 'Editor',
      updatedAtMs: (json['updatedAtMs'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Pre-populated reference locations for quick whiteboard search and demo pin dropping.
class MapLocationPreset {
  const MapLocationPreset({
    required this.name,
    required this.country,
    required this.latitude,
    required this.longitude,
    this.category = 'City',
    this.region = '',
  });

  final String name;
  final String country;
  final double latitude;
  final double longitude;
  final String category; // 'Tech Hub', 'Cloud Region', 'Capital', 'Finance'
  final String region; // 'North America', 'Europe', 'Asia Pacific', 'Latin America', 'Middle East & Africa'

  static List<MapLocationPreset> search(String query) {
    if (query.trim().isEmpty) return presets;
    final q = query.trim().toLowerCase();
    return presets
        .where(
          (p) =>
              p.name.toLowerCase().contains(q) ||
              p.country.toLowerCase().contains(q) ||
              p.category.toLowerCase().contains(q) ||
              p.region.toLowerCase().contains(q),
        )
        .toList();
  }

  static MapLocationPreset? findNearest(double lat, double lng) {
    if (presets.isEmpty) return null;
    MapLocationPreset? closest;
    double minDistance = double.infinity;
    for (final p in presets) {
      final d = MercatorProjection.distanceBetweenKm(
        lat,
        lng,
        p.latitude,
        p.longitude,
      );
      if (d < minDistance) {
        minDistance = d;
        closest = p;
      }
    }
    return closest;
  }

  static const List<MapLocationPreset> presets = [
    // Tech Hubs - North America
    MapLocationPreset(
      name: 'San Francisco (Silicon Valley)',
      country: 'United States',
      latitude: 37.7749,
      longitude: -122.4194,
      category: 'Tech Hub',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'Seattle',
      country: 'United States',
      latitude: 47.6062,
      longitude: -122.3321,
      category: 'Tech Hub',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'New York City',
      country: 'United States',
      latitude: 40.7128,
      longitude: -74.0060,
      category: 'Finance',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'Austin',
      country: 'United States',
      latitude: 30.2672,
      longitude: -97.7431,
      category: 'Tech Hub',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'Boston',
      country: 'United States',
      latitude: 42.3601,
      longitude: -71.0589,
      category: 'Tech Hub',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'Toronto',
      country: 'Canada',
      latitude: 43.6532,
      longitude: -79.3832,
      category: 'Tech Hub',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'Vancouver',
      country: 'Canada',
      latitude: 49.2827,
      longitude: -123.1207,
      category: 'Tech Hub',
      region: 'North America',
    ),

    // Cloud Regions - Americas
    MapLocationPreset(
      name: 'AWS us-east-1 (N. Virginia)',
      country: 'United States',
      latitude: 38.8048,
      longitude: -77.0469,
      category: 'Cloud Region',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'AWS us-west-2 (Oregon)',
      country: 'United States',
      latitude: 45.5152,
      longitude: -122.6784,
      category: 'Cloud Region',
      region: 'North America',
    ),
    MapLocationPreset(
      name: 'GCP us-central1 (Iowa)',
      country: 'United States',
      latitude: 41.8780,
      longitude: -93.0977,
      category: 'Cloud Region',
      region: 'North America',
    ),

    // Tech Hubs & Capitals - Europe
    MapLocationPreset(
      name: 'London',
      country: 'United Kingdom',
      latitude: 51.5074,
      longitude: -0.1278,
      category: 'Finance',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Berlin',
      country: 'Germany',
      latitude: 52.5200,
      longitude: 13.4050,
      category: 'Tech Hub',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Paris',
      country: 'France',
      latitude: 48.8566,
      longitude: 2.3522,
      category: 'Capital',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Amsterdam',
      country: 'Netherlands',
      latitude: 52.3676,
      longitude: 4.9041,
      category: 'Tech Hub',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Dublin (Silicon Docks)',
      country: 'Ireland',
      latitude: 53.3498,
      longitude: -6.2603,
      category: 'Tech Hub',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Stockholm',
      country: 'Sweden',
      latitude: 59.3293,
      longitude: 18.0686,
      category: 'Tech Hub',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Zurich',
      country: 'Switzerland',
      latitude: 47.3769,
      longitude: 8.5417,
      category: 'Finance',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Madrid',
      country: 'Spain',
      latitude: 40.4168,
      longitude: -3.7038,
      category: 'Capital',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Rome',
      country: 'Italy',
      latitude: 41.9028,
      longitude: 12.4964,
      category: 'Capital',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'Warsaw',
      country: 'Poland',
      latitude: 52.2297,
      longitude: 21.0122,
      category: 'Tech Hub',
      region: 'Europe',
    ),

    // Cloud Regions - Europe
    MapLocationPreset(
      name: 'AWS eu-west-1 (Ireland)',
      country: 'Ireland',
      latitude: 53.3501,
      longitude: -6.2662,
      category: 'Cloud Region',
      region: 'Europe',
    ),
    MapLocationPreset(
      name: 'AWS eu-central-1 (Frankfurt)',
      country: 'Germany',
      latitude: 50.1109,
      longitude: 8.6821,
      category: 'Cloud Region',
      region: 'Europe',
    ),

    // Tech Hubs & Capitals - Asia Pacific
    MapLocationPreset(
      name: 'Bengaluru (Silicon Valley of India)',
      country: 'India',
      latitude: 12.9716,
      longitude: 77.5946,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Hyderabad (Cyberabad)',
      country: 'India',
      latitude: 17.3850,
      longitude: 78.4867,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'New Delhi',
      country: 'India',
      latitude: 28.6139,
      longitude: 77.2090,
      category: 'Capital',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Mumbai',
      country: 'India',
      latitude: 19.0760,
      longitude: 72.8777,
      category: 'Finance',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Singapore',
      country: 'Singapore',
      latitude: 1.3521,
      longitude: 103.8198,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Tokyo',
      country: 'Japan',
      latitude: 35.6762,
      longitude: 139.6503,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Seoul',
      country: 'South Korea',
      latitude: 37.5665,
      longitude: 126.9780,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Sydney',
      country: 'Australia',
      latitude: -33.8688,
      longitude: 151.2093,
      category: 'Finance',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Melbourne',
      country: 'Australia',
      latitude: -37.8136,
      longitude: 144.9631,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Shenzhen',
      country: 'China',
      latitude: 22.5431,
      longitude: 114.0579,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Beijing',
      country: 'China',
      latitude: 39.9042,
      longitude: 116.4074,
      category: 'Capital',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Hong Kong',
      country: 'Hong Kong',
      latitude: 22.3193,
      longitude: 114.1694,
      category: 'Finance',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Jakarta',
      country: 'Indonesia',
      latitude: -6.2088,
      longitude: 106.8456,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Bangkok',
      country: 'Thailand',
      latitude: 13.7563,
      longitude: 100.5018,
      category: 'Capital',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'Taipei',
      country: 'Taiwan',
      latitude: 25.0330,
      longitude: 121.5654,
      category: 'Tech Hub',
      region: 'Asia Pacific',
    ),

    // Cloud Regions - Asia Pacific
    MapLocationPreset(
      name: 'AWS ap-south-1 (Mumbai)',
      country: 'India',
      latitude: 19.0760,
      longitude: 72.8777,
      category: 'Cloud Region',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'AWS ap-southeast-1 (Singapore)',
      country: 'Singapore',
      latitude: 1.3521,
      longitude: 103.8198,
      category: 'Cloud Region',
      region: 'Asia Pacific',
    ),
    MapLocationPreset(
      name: 'AWS ap-northeast-1 (Tokyo)',
      country: 'Japan',
      latitude: 35.6895,
      longitude: 139.6917,
      category: 'Cloud Region',
      region: 'Asia Pacific',
    ),

    // Latin America
    MapLocationPreset(
      name: 'São Paulo',
      country: 'Brazil',
      latitude: -23.5505,
      longitude: -46.6333,
      category: 'Finance',
      region: 'Latin America',
    ),
    MapLocationPreset(
      name: 'Buenos Aires',
      country: 'Argentina',
      latitude: -34.6037,
      longitude: -58.3816,
      category: 'Capital',
      region: 'Latin America',
    ),
    MapLocationPreset(
      name: 'Mexico City',
      country: 'Mexico',
      latitude: 19.4326,
      longitude: -99.1332,
      category: 'Capital',
      region: 'Latin America',
    ),
    MapLocationPreset(
      name: 'Santiago',
      country: 'Chile',
      latitude: -33.4489,
      longitude: -70.6693,
      category: 'Capital',
      region: 'Latin America',
    ),
    MapLocationPreset(
      name: 'Bogotá',
      country: 'Colombia',
      latitude: 4.7110,
      longitude: -74.0721,
      category: 'Capital',
      region: 'Latin America',
    ),
    MapLocationPreset(
      name: 'AWS sa-east-1 (São Paulo)',
      country: 'Brazil',
      latitude: -23.5475,
      longitude: -46.6361,
      category: 'Cloud Region',
      region: 'Latin America',
    ),

    // Middle East & Africa
    MapLocationPreset(
      name: 'Dubai',
      country: 'United Arab Emirates',
      latitude: 25.2048,
      longitude: 55.2708,
      category: 'Finance',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Tel Aviv',
      country: 'Israel',
      latitude: 32.0853,
      longitude: 34.7818,
      category: 'Tech Hub',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Riyadh',
      country: 'Saudi Arabia',
      latitude: 24.7136,
      longitude: 46.6753,
      category: 'Capital',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Nairobi (Silicon Savannah)',
      country: 'Kenya',
      latitude: -1.2921,
      longitude: 36.8219,
      category: 'Tech Hub',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Cape Town',
      country: 'South Africa',
      latitude: -33.9249,
      longitude: 18.4241,
      category: 'Tech Hub',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Johannesburg',
      country: 'South Africa',
      latitude: -26.2041,
      longitude: 28.0473,
      category: 'Finance',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'Cairo',
      country: 'Egypt',
      latitude: 30.0444,
      longitude: 31.2357,
      category: 'Capital',
      region: 'Middle East & Africa',
    ),
    MapLocationPreset(
      name: 'AWS me-central-1 (UAE)',
      country: 'United Arab Emirates',
      latitude: 25.2769,
      longitude: 55.2962,
      category: 'Cloud Region',
      region: 'Middle East & Africa',
    ),
  ];
}
