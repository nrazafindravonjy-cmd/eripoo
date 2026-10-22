import '../../../data/local/app_database.dart';
import '../../project/data/project_repository.dart';
import '../domain/creation_fees.dart';

/// The user's own progress on the preparation: documents ready and the
/// numbers typed for the fee estimate. Kept in a project section that the
/// Project screen does not show (no schema), synchronised encrypted like
/// every section.
class Preparation {
  const Preparation({
    this.ready = const {},
    this.capitalMga,
    this.taxId,
    this.monthlyRentMga,
    this.leaseMonths,
    this.represented = false,
  });

  /// Checklist items marked ready.
  final Set<String> ready;
  final int? capitalMga;
  final String? taxId;
  final int? monthlyRentMga;
  final int? leaseMonths;
  final bool represented;

  /// What the estimate needs, once capital and activity are known.
  CreationFeeInput? get feeInput => capitalMga == null || taxId == null
      ? null
      : CreationFeeInput(
          capitalMga: capitalMga!,
          taxId: taxId!,
          monthlyRentMga: monthlyRentMga,
          leaseMonths: monthlyRentMga == null ? null : leaseMonths,
          represented: represented,
        );

  Map<String, Object?> toFields() => {
    'ready': ready.toList()..sort(),
    'capital_mga': capitalMga,
    'tax_id': taxId,
    'monthly_rent_mga': monthlyRentMga,
    'lease_months': leaseMonths,
    'represented': represented,
  };

  static Preparation fromFields(Map<String, Object?> f) => Preparation(
    ready: {for (final v in (f['ready'] as List<Object?>?) ?? const []) '$v'},
    capitalMga: f['capital_mga'] as int?,
    taxId: f['tax_id'] as String?,
    monthlyRentMga: f['monthly_rent_mga'] as int?,
    leaseMonths: f['lease_months'] as int?,
    represented: f['represented'] as bool? ?? false,
  );

  Preparation copyWith({
    Set<String>? ready,
    int? Function()? capitalMga,
    String? Function()? taxId,
    int? Function()? monthlyRentMga,
    int? Function()? leaseMonths,
    bool? represented,
  }) => Preparation(
    ready: ready ?? this.ready,
    capitalMga: capitalMga == null ? this.capitalMga : capitalMga(),
    taxId: taxId == null ? this.taxId : taxId(),
    monthlyRentMga: monthlyRentMga == null
        ? this.monthlyRentMga
        : monthlyRentMga(),
    leaseMonths: leaseMonths == null ? this.leaseMonths : leaseMonths(),
    represented: represented ?? this.represented,
  );
}

class PreparationService {
  PreparationService(AppDatabase db) : _projects = ProjectRepository(db);

  final ProjectRepository _projects;

  /// Section key; deliberately absent from the content's section list.
  static const sectionKey = 'formalization_prep';

  Future<Preparation> of(String projectId) async {
    final section = await _projects.section(projectId, sectionKey);
    return section == null
        ? const Preparation()
        : Preparation.fromFields(section.fields);
  }

  Future<void> save(String projectId, Preparation preparation) =>
      _projects.saveSection(
        projectId: projectId,
        sectionKey: sectionKey,
        fields: preparation.toFields(),
      );

  Future<void> setReady(String projectId, String itemId, bool ready) async {
    final current = await of(projectId);
    await save(
      projectId,
      current.copyWith(
        ready: ready
            ? {...current.ready, itemId}
            : ({...current.ready}..remove(itemId)),
      ),
    );
  }
}
