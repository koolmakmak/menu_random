import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config.dart';

class NearbyShop {
  final String name;
  final String address;
  final double rating;
  final double lat;
  final double lng;

  NearbyShop({
    required this.name,
    required this.address,
    required this.rating,
    required this.lat,
    required this.lng,
  });
}

/// ค้นหาร้านอาหารจริงใกล้ตำแหน่ง
/// หลัก: Geoapify Places API (ฟรี ใช้ดีในไทย)
/// สำรอง: Foursquare Places API + OpenStreetMap Overpass
class NearbyPlacesService {
  // Overpass mirrors (fallback)
  static const _overpassEndpoints = [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
    'https://overpass.private.coffee/api/interpreter',
    'https://overpass.osm.ch/api/interpreter',
  ];

  static Future<List<NearbyShop>> searchNearbyRestaurants({
    required double lat,
    required double lng,
  }) async {
    // ใช้ Geoapify เป็นหลัก (เร็ว ไม่ต้องไล่สำรองหลายตัว)
    if (geoapifyApiKey.isNotEmpty && geoapifyApiKey != 'YOUR_GEOAPIFY_KEY') {
      return _searchGeoapify(lat: lat, lng: lng);
    }

    // ถ้าไม่มี Geoapify จะลอง Foursquare
    if (foursquareApiKey.isNotEmpty && foursquareApiKey != 'YOUR_FOURSQUARE_KEY') {
      final shops = await _searchFoursquare(lat: lat, lng: lng);
      if (shops.isNotEmpty) return shops;
    }

    // สุดท้ายใช้ Overpass
    return _searchOverpass(lat: lat, lng: lng);
  }

  static Future<List<NearbyShop>> _searchGeoapify({
    required double lat,
    required double lng,
  }) async {
    final uri = Uri.parse('https://api.geoapify.com/v2/places').replace(queryParameters: {
      'apiKey': geoapifyApiKey,
      'categories': 'catering.restaurant,catering.fast_food,catering.cafe',
      'filter': 'circle:$lng,$lat,3000',
      'bias': 'proximity:$lng,$lat',
      'limit': '20',
    });

    try {
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      debugPrint('Geoapify ${response.statusCode}');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final features = (data['features'] as List?) ?? [];
        final shops = <NearbyShop>[];
        for (final f in features) {
          final props = (f['properties'] as Map<String, dynamic>?) ?? {};
          final name = props['name'] as String?;
          if (name == null || name.isEmpty) continue;
          shops.add(NearbyShop(
            name: name,
            address: props['formatted'] ?? '',
            rating: 0,
            lat: (props['lat'] as num?)?.toDouble() ?? lat,
            lng: (props['lon'] as num?)?.toDouble() ?? lng,
          ));
        }
        return shops;
      }
      debugPrint('Geoapify error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('Geoapify error: $e');
    }
    return [];
  }

  static Future<List<NearbyShop>> _searchFoursquare({
    required double lat,
    required double lng,
  }) async {
    const url = 'https://api.foursquare.com/v3/places/search';
    final uri = Uri.parse(url).replace(queryParameters: {
      'll': '$lat,$lng',
      'radius': '3000',
      'categoryId': '13000', // restaurant & food
      'limit': '20',
    });

    try {
      final response = await http.get(uri, headers: {
        'Authorization': foursquareApiKey,
        'Accept': 'application/json',
      }).timeout(const Duration(seconds: 8));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final results = (data['results'] as List?) ?? [];
        final shops = <NearbyShop>[];
        for (final r in results) {
          final name = r['name'] as String?;
          if (name == null || name.isEmpty) continue;
          final geocodes = (r['geocodes']?['main'] as Map<String, dynamic>?) ?? {};
          final location = (r['location'] as Map<String, dynamic>?) ?? {};
          shops.add(NearbyShop(
            name: name,
            address: location['address'] ?? '',
            rating: 0,
            lat: (geocodes['latitude'] as num?)?.toDouble() ?? lat,
            lng: (geocodes['longitude'] as num?)?.toDouble() ?? lng,
          ));
        }
        // เรียงตามระยะทาง
        shops.sort((a, b) => _distance(lat, lng, a.lat, a.lng)
            .compareTo(_distance(lat, lng, b.lat, b.lng)));
        return shops;
      }
      debugPrint('Foursquare error ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('Foursquare error: $e');
    }
    return [];
  }

  static Future<List<NearbyShop>> _searchOverpass({
    required double lat,
    required double lng,
  }) async {
    final query = '''
[out:json][timeout:15];
(
  node["amenity"~"restaurant|fast_food|cafe"](around:3000,$lat,$lng);
  way["amenity"~"restaurant|fast_food|cafe"](around:3000,$lat,$lng);
);
out center 20;
''';

    for (final url in _overpassEndpoints) {
      try {
        final response = await http
            .post(Uri.parse(url), body: {'data': query})
            .timeout(const Duration(seconds: 8));
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          final elements = (data['elements'] as List?) ?? [];
          final shops = <NearbyShop>[];
          for (final e in elements) {
            final tags = e['tags'] as Map<String, dynamic>? ?? {};
            final name = tags['name'];
            if (name is String && name.isNotEmpty) {
              final center = (e['center'] != null)
                  ? e['center'] as Map<String, dynamic>
                  : e as Map<String, dynamic>;
              final shopLat = (center['lat'] as num?)?.toDouble() ?? lat;
              final shopLng = (center['lon'] as num?)?.toDouble() ?? lng;
              shops.add(NearbyShop(
                name: name,
                address: tags['addr:street'] ?? tags['addr:full'] ?? '-',
                rating: 0,
                lat: shopLat,
                lng: shopLng,
              ));
            }
          }
          shops.sort((a, b) => _distance(lat, lng, a.lat, a.lng)
              .compareTo(_distance(lat, lng, b.lat, b.lng)));
          return shops;
        }
        debugPrint('Overpass error $url ${response.statusCode}');
      } catch (e) {
        debugPrint('Overpass error $url: $e');
      }
    }
    return [];
  }

  // ระยะห่างแบบ Haversine (เมตร)
  static double _distance(double lat1, double lng1, double lat2, double lng2) {
    const r = 6371000.0;
    const d2r = 3.141592653589793 / 180;
    final dLat = (lat2 - lat1) * d2r;
    final dLng = (lng2 - lng1) * d2r;
    final a = math.pow(math.sin(dLat / 2), 2) +
        math.cos(lat1 * d2r) *
            math.cos(lat2 * d2r) *
            math.pow(math.sin(dLng / 2), 2);
    return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
  }
}
