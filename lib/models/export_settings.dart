/// The compiled video's output resolution. [hd] matches the app's internal
/// working canvas (no extra encode pass); [uhd] upscales in a final ffmpeg
/// pass and requires a premium subscription.
enum ExportResolution {
  hd(width: 720, height: 1280, label: 'HD'),
  uhd(width: 2160, height: 3840, label: '4K');

  const ExportResolution({
    required this.width,
    required this.height,
    required this.label,
  });

  final int width;
  final int height;
  final String label;

  static ExportResolution fromName(String? name) => values.firstWhere(
    (r) => r.name == name,
    orElse: () => ExportResolution.hd,
  );
}
