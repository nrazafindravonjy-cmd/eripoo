/// Project maturity (CLAUDE.md §22). Describes the work done, never a
/// chance of success.
enum MaturityStage {
  exploration,
  validation,
  construction,
  preparation,
  launch,
}

/// The user's entrepreneurial project. It exists from the first step of
/// the quest, never only at the end (CLAUDE.md §13).
class Project {
  const Project({
    required this.id,
    required this.title,
    required this.maturityStage,
    required this.createdAt,
    required this.updatedAt,
    this.deletedAt,
  });

  final String id;
  final String title;
  final MaturityStage maturityStage;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// Set when the project is in the trash.
  final DateTime? deletedAt;

  bool get isDeleted => deletedAt != null;
}

/// Fields of one project section (problem, customers, offer...). The field
/// schema comes from content, not from code.
class ProjectSection {
  const ProjectSection({
    required this.id,
    required this.projectId,
    required this.sectionKey,
    required this.fields,
    required this.updatedAt,
  });

  final String id;
  final String projectId;
  final String sectionKey;
  final Map<String, Object?> fields;
  final DateTime updatedAt;
}

/// One recorded change of a tracked field ("before / now").
class ProjectRevision {
  const ProjectRevision({
    required this.sectionKey,
    required this.fieldKey,
    required this.previousValue,
    required this.newValue,
    required this.createdAt,
  });

  final String sectionKey;
  final String fieldKey;
  final String? previousValue;
  final String? newValue;
  final DateTime createdAt;
}

class InvalidProjectTitle implements Exception {
  const InvalidProjectTitle();
}

abstract final class ProjectRules {
  static const maxTitleLength = 120;

  /// Trimmed title, or [InvalidProjectTitle] if empty or too long.
  static String validateTitle(String title) {
    final trimmed = title.trim();
    if (trimmed.isEmpty || trimmed.length > maxTitleLength) {
      throw const InvalidProjectTitle();
    }
    return trimmed;
  }
}
