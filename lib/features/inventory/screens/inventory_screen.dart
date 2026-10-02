import 'package:flutter/material.dart';

import '../repositories/asset_repository.dart';
import 'assets_screen.dart';

class InventoryScreen extends StatelessWidget {
  const InventoryScreen({super.key, required this.assetRepository});

  final AssetRepository assetRepository;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Inventory',
              style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            const SizedBox(height: 6),
            Text(
              'Manage assets and consumables.',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 32),
            LayoutBuilder(
              builder: (context, constraints) {
                final cardWidth = constraints.maxWidth >= 900
                    ? (constraints.maxWidth - 24) / 2
                    : constraints.maxWidth;
                return Wrap(
                  spacing: 24,
                  runSpacing: 24,
                  children: [
                    SizedBox(
                      width: cardWidth,
                      child: _InventoryCard(
                        icon: Icons.precision_manufacturing_rounded,
                        title: 'Assets',
                        description:
                            'Machinery, equipment and durable items.',
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) =>
                                AssetsScreen(repository: assetRepository),
                          ),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: cardWidth,
                      child: _InventoryCard(
                        icon: Icons.inventory_2_rounded,
                        title: 'Consumables',
                        description:
                            'Thread, stabiliser, beads, sequins and supplies.',
                        enabled: false,
                        onTap: () {},
                      ),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _InventoryCard extends StatelessWidget {
  const _InventoryCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
    this.enabled = true,
  });

  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: enabled ? onTap : null,
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Row(
            children: [
              Icon(icon, size: 40),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    Text(description),
                    if (!enabled) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Coming next',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                    ],
                  ],
                ),
              ),
              if (enabled)
                const Icon(Icons.arrow_forward_ios_rounded, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}
