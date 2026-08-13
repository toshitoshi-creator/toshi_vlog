import 'package:flutter/material.dart';

import '../models/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  const PaywallScreen({super.key, required this.subscriptionService});

  final SubscriptionService subscriptionService;

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  @override
  void initState() {
    super.initState();
    widget.subscriptionService.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.subscriptionService.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (!mounted) return;
    if (widget.subscriptionService.isPremium) {
      Navigator.of(context).pop();
      return;
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final service = widget.subscriptionService;
    final product = service.product;

    return Scaffold(
      appBar: AppBar(title: const Text('プレミアムプラン')),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(
              Icons.workspace_premium,
              size: 64,
              color: Colors.amber,
            ),
            const SizedBox(height: 16),
            Text(
              'プレミアムに登録すると、まとめ動画の各クリップを何度でも作り直しできるようになります。',
              style: Theme.of(context).textTheme.bodyLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            if (!service.isAvailable)
              const Text('この端末では購入機能を利用できません', textAlign: TextAlign.center)
            else if (product == null)
              const Center(child: CircularProgressIndicator())
            else ...[
              FilledButton(
                onPressed: service.purchasePending ? null : service.buy,
                child: service.purchasePending
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text('${product.title} - ${product.price} / 月'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: service.purchasePending ? null : service.restore,
                child: const Text('購入を復元'),
              ),
            ],
            if (service.errorMessage != null) ...[
              const SizedBox(height: 16),
              Text(
                service.errorMessage!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
