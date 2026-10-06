import 'package:eripoo/design_system/design_system.dart';
import 'package:flutter/material.dart';

/// Every design-system component on one scrollable page, used by the test
/// matrix and the visual review captures. Test-only: not part of the app.
///
/// Literal strings here are test data, standing in for content.
class ComponentSheet extends StatelessWidget {
  const ComponentSheet({super.key});

  @override
  Widget build(BuildContext context) {
    const gap = SizedBox(height: EripooSpacing.xl);
    return ListView(
      padding: const EdgeInsets.symmetric(vertical: EripooSpacing.xl),
      children: [
        ReadableColumn(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const EripooOfflineBanner(),
              gap,
              Text(
                'Observe ton quartier',
                style: context.textStyles.headlineSmall,
              ),
              const SizedBox(height: EripooSpacing.sm),
              Text(
                'Note trois problèmes que rencontrent les gens autour de toi.',
                style: context.textStyles.bodyLarge,
              ),
              gap,
              const EripooProgress(done: 4, total: 12, label: 'Quête 2'),
              gap,
              const EripooStepTrack(
                steps: [
                  'Exploration',
                  'Validation',
                  'Construction',
                  'Préparation',
                  'Lancement',
                ],
                currentIndex: 1,
              ),
              gap,
              EripooCard(
                onTap: () {},
                semanticLabel: 'Mission : parle à 3 personnes',
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Mission', style: context.textStyles.labelMedium),
                    const SizedBox(height: EripooSpacing.xs),
                    Text(
                      'Parle à 3 personnes',
                      style: context.textStyles.titleMedium,
                    ),
                  ],
                ),
              ),
              gap,
              const EripooTextField(
                label: 'Qui rencontre ce problème ?',
                hint: 'Ex. les vendeuses du marché',
              ),
              const SizedBox(height: EripooSpacing.lg),
              const EripooTextField(
                label: 'Dans quelle situation ?',
                isOptional: true,
                errorText: 'Écris au moins un mot.',
              ),
              gap,
              EripooButton(label: 'Continuer', onPressed: () {}, expand: true),
              const SizedBox(height: EripooSpacing.md),
              EripooButton(
                label: 'Plus tard',
                variant: EripooButtonVariant.secondary,
                onPressed: () {},
                expand: true,
              ),
              const SizedBox(height: EripooSpacing.md),
              EripooButton(
                label: 'Enregistrement…',
                isLoading: true,
                onPressed: () {},
                expand: true,
              ),
              const SizedBox(height: EripooSpacing.md),
              EripooButton(
                label: 'Supprimer',
                variant: EripooButtonVariant.danger,
                onPressed: () {},
              ),
              gap,
              EripooHelpButton(onSelected: (_) {}),
              gap,
              const Wrap(
                spacing: EripooSpacing.lg,
                runSpacing: EripooSpacing.lg,
                children: [
                  EripooBadge(
                    name: 'Chercheur de vérité',
                    icon: Icons.search,
                    earned: true,
                  ),
                  EripooBadge(
                    name: 'Première vente',
                    icon: Icons.storefront,
                    earned: false,
                  ),
                ],
              ),
              gap,
              const SizedBox(height: 280, child: EripooErrorView()),
            ],
          ),
        ),
      ],
    );
  }
}
