import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../finance/application/finance_service.dart';
import '../../hypotheses/application/research_service.dart';
import '../../hypotheses/domain/hypothesis_states.dart';
import '../../project/data/project_repository.dart';
import '../../project/domain/project.dart';
import '../../tools/application/competitor_service.dart';

/// A hypothesis that reached a conclusion, with what was concluded.
class ConcludedHypothesis {
  const ConcludedHypothesis({
    required this.statement,
    required this.category,
    required this.outcome,
    this.conclusion,
  });

  final String statement;
  final HypothesisCategory category;
  final HypothesisStatus outcome;

  /// The latest conclusion written by the user.
  final String? conclusion;
}

/// Everything the user has done on a project, read once: what the
/// canvas, the file and the pitch deck are built from. Nothing here is
/// generated: each value is the user's own work or a computed number.
class ProjectSynthesis {
  const ProjectSynthesis({
    required this.project,
    required this.sections,
    required this.concluded,
    required this.hypotheses,
    required this.experimentsDone,
    required this.observations,
    required this.interviews,
    required this.competitors,
    required this.finance,
  });

  final Project project;

  /// Section fields by section key.
  final Map<String, Map<String, Object?>> sections;
  final List<ConcludedHypothesis> concluded;
  final int hypotheses;
  final int experimentsDone;
  final int observations;
  final int interviews;
  final List<Competitor> competitors;
  final FinanceSnapshot finance;

  /// The trimmed text of a section field; null when empty.
  String? field(String section, String key) {
    final t = sections[section]?[key]?.toString().trim();
    return t == null || t.isEmpty ? null : t;
  }

  List<ConcludedHypothesis> validated([HypothesisCategory? category]) => [
    for (final h in concluded)
      if (h.outcome == HypothesisStatus.validated &&
          (category == null || h.category == category))
        h,
  ];
}

class ProjectSynthesisService {
  ProjectSynthesisService(this._db);

  final AppDatabase _db;

  /// Null when the project does not exist (or is in the trash).
  Future<ProjectSynthesis?> of(String projectId) async {
    final projects = ProjectRepository(_db);
    final project = await projects.get(projectId);
    if (project == null || project.isDeleted) return null;
    final research = ResearchService(_db);
    final hypotheses = await research.hypothesesOf(projectId);
    final concluded = <ConcludedHypothesis>[];
    for (final h in hypotheses.where((h) => h.status.isConcluded)) {
      final conclusions = await research.conclusionsOf(h.id);
      concluded.add(
        ConcludedHypothesis(
          statement: h.statement,
          category: h.category,
          outcome: h.status,
          conclusion: conclusions.isEmpty ? null : conclusions.last.statement,
        ),
      );
    }
    final done =
        await (_db.selectOnly(_db.experiments)
              ..addColumns([_db.experiments.id.count()])
              ..where(
                _db.experiments.projectId.equals(projectId) &
                    _db.experiments.status.equals('done') &
                    _db.experiments.deletedAt.isNull(),
              ))
            .map((r) => r.read(_db.experiments.id.count())!)
            .getSingle();
    return ProjectSynthesis(
      project: project,
      sections: {
        for (final e in (await projects.sections(projectId)).entries)
          e.key: e.value.fields,
      },
      concluded: concluded,
      hypotheses: hypotheses.length,
      experimentsDone: done,
      observations: (await research.observationsOf(projectId)).length,
      interviews: (await research.interviewsOf(projectId)).length,
      competitors: await CompetitorService(_db).competitorsOf(projectId),
      finance: await FinanceService(_db).snapshot(projectId),
    );
  }

  /// Fires when anything the synthesis reads changes.
  Stream<void> watchChanges() => _db.tableUpdates(
    TableUpdateQuery.onAllTables([
      _db.projects,
      _db.projectSections,
      _db.hypotheses,
      _db.experiments,
      _db.conclusions,
      _db.observations,
      _db.interviews,
      _db.competitors,
      _db.financeItems,
      _db.financePlans,
    ]),
  );
}
