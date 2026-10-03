String formatDistance(double meters) {
  if (meters >= 1000) return '${(meters / 1000).toStringAsFixed(1)} km';
  if (meters >= 100) return '${(meters / 10).round() * 10} m';
  return '${meters.round()} m';
}
