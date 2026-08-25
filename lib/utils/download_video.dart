import 'dart:io';

import 'package:flutter/material.dart';
import 'package:gal/gal.dart';

import '../models/download_quota.dart';
import '../models/subscription_service.dart';
import '../screens/paywall_screen.dart';

/// Saves [file] to the camera roll, gated by [subscriptionService]/
/// [downloadQuota]'s free-download quota (opens the paywall instead if the
/// quota is exhausted and not premium), and shows a snackbar with the
/// result via [context] — which must still be mounted when this resolves.
/// Callers own their own loading-indicator state around this call.
///
/// [bypassQuota] skips the quota gate entirely without consuming a slot
/// from it — used for a one-off download unlocked by watching a rewarded
/// ad rather than by the daily free-download count.
Future<void> downloadCompiledVideo({
  required BuildContext context,
  required File file,
  required SubscriptionService subscriptionService,
  required DownloadQuota downloadQuota,
  bool bypassQuota = false,
}) async {
  final canDownload =
      bypassQuota ||
      subscriptionService.isPremium ||
      downloadQuota.remainingFreeDownloads > 0;
  if (!canDownload) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PaywallScreen(subscriptionService: subscriptionService),
      ),
    );
    return;
  }

  String message;
  try {
    var hasAccess = await Gal.hasAccess();
    if (!hasAccess) {
      hasAccess = await Gal.requestAccess();
    }
    if (!hasAccess) {
      message = '写真ライブラリへのアクセスが許可されていません';
    } else {
      await Gal.putVideo(file.path, album: 'ToshiVlog');
      if (!subscriptionService.isPremium && !bypassQuota) {
        await downloadQuota.recordDownload();
      }
      message = 'カメラロールに保存しました';
    }
  } catch (_) {
    message = '保存に失敗しました';
  }
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
}
