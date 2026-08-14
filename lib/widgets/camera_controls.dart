import 'package:flutter/material.dart';

class RecordButton extends StatelessWidget {
  const RecordButton({
    super.key,
    required this.isRecording,
    required this.onTap,
  });

  final bool isRecording;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: SizedBox(
        width: 76,
        height: 76,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 4),
              ),
            ),
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: isRecording ? 32 : 64,
              height: isRecording ? 32 : 64,
              decoration: BoxDecoration(
                color: Colors.red,
                borderRadius: BorderRadius.circular(isRecording ? 8 : 32),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class SwitchCameraButton extends StatelessWidget {
  const SwitchCameraButton({
    super.key,
    required this.enabled,
    required this.onTap,
  });

  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: const Icon(Icons.cameraswitch, color: Colors.white),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        fixedSize: const Size(56, 56),
      ),
    );
  }
}

/// Small round icon button used for the flash toggle and settings entry
/// point in the top bar of the camera screen.
class TopIconButton extends StatelessWidget {
  const TopIconButton({
    super.key,
    required this.icon,
    required this.onTap,
    this.enabled = true,
    this.highlighted = false,
  });

  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: enabled ? onTap : null,
      icon: Icon(
        icon,
        color: highlighted ? Colors.amber : Colors.white,
      ),
      style: IconButton.styleFrom(
        backgroundColor: Colors.black.withValues(alpha: 0.4),
        fixedSize: const Size(44, 44),
      ),
    );
  }
}

/// Horizontal row of tappable zoom presets (e.g. 0.5x/1x/2x/3x), only
/// showing presets that fall within the current camera's zoom range.
class ZoomPresetRow extends StatelessWidget {
  const ZoomPresetRow({
    super.key,
    required this.minZoom,
    required this.maxZoom,
    required this.currentZoom,
    required this.onSelect,
  });

  final double minZoom;
  final double maxZoom;
  final double currentZoom;
  final ValueChanged<double> onSelect;

  static const _candidates = [0.5, 1.0, 2.0, 3.0];

  @override
  Widget build(BuildContext context) {
    final presets = _candidates
        .where((zoom) => zoom >= minZoom && zoom <= maxZoom)
        .toList();
    if (presets.length < 2) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        for (final zoom in presets)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: GestureDetector(
              onTap: () => onSelect(zoom),
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (currentZoom - zoom).abs() < 0.05
                      ? Colors.amber
                      : Colors.black.withValues(alpha: 0.4),
                ),
                alignment: Alignment.center,
                child: Text(
                  zoom == zoom.roundToDouble()
                      ? '${zoom.toInt()}x'
                      : '${zoom}x',
                  style: TextStyle(
                    color: (currentZoom - zoom).abs() < 0.05
                        ? Colors.black
                        : Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
