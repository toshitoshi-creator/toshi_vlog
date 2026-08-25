import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Thin wrapper around a single Google AdMob rewarded ad: preloads one in
/// the background and shows it on request when the caller needs to unlock
/// something (see 編集 tab's download flow for non-premium users who've
/// used up today's free downloads), resolving to whether the reward was
/// actually earned — i.e. the ad was watched through, not dismissed early
/// or failed to load.
///
/// These are Google's public TEST ad unit IDs (always fill with a clearly
/// labeled test ad, never generate real revenue) — replace with real ad
/// unit IDs from your own AdMob account before release, alongside the App
/// IDs in AndroidManifest.xml/Info.plist. See https://admob.google.com.
class RewardedAdService extends ChangeNotifier {
  static String get _adUnitId => Platform.isIOS
      ? 'ca-app-pub-3940256099942544/1712485313'
      : 'ca-app-pub-3940256099942544/5224354917';

  RewardedAd? _ad;
  bool _isLoading = false;

  bool get isReady => _ad != null;

  Future<void> init() async {
    await MobileAds.instance.initialize();
    unawaited(_load());
  }

  Future<void> _load() async {
    if (_isLoading || _ad != null) return;
    _isLoading = true;
    await RewardedAd.load(
      adUnitId: _adUnitId,
      request: const AdRequest(),
      rewardedAdLoadCallback: RewardedAdLoadCallback(
        onAdLoaded: (ad) {
          _ad = ad;
          _isLoading = false;
          notifyListeners();
        },
        onAdFailedToLoad: (error) {
          _ad = null;
          _isLoading = false;
        },
      ),
    );
  }

  /// Shows the preloaded ad if one is ready, returning whether the reward
  /// was actually earned. Always tries to preload the next one afterward
  /// (or immediately, if none was ready to show at all).
  Future<bool> showAd() async {
    final ad = _ad;
    if (ad == null) {
      unawaited(_load());
      return false;
    }
    _ad = null;
    var earned = false;
    final dismissed = Completer<void>();
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
      onAdFailedToShowFullScreenContent: (ad, error) {
        ad.dispose();
        if (!dismissed.isCompleted) dismissed.complete();
      },
    );
    await ad.show(
      onUserEarnedReward: (ad, reward) {
        earned = true;
      },
    );
    await dismissed.future;
    unawaited(_load());
    return earned;
  }

  @override
  void dispose() {
    _ad?.dispose();
    super.dispose();
  }
}
