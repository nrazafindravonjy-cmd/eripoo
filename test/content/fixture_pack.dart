/// A small valid pack (as decoded JSON) for content tests. Tests copy and
/// mutate it to check what the parser and validator refuse.
Map<String, Object?> lt(
  String fr, {
  String? mg,
  String? en,
  String? mgStatus,
}) => {
  'fr': fr,
  'mg': ?mg,
  'en': ?en,
  if (mgStatus != null) 'status': {'mg': mgStatus},
};

Map<String, Object?> help() => {
  'rephrase': [lt('Autrement dit…'), lt('Plus simplement…')],
  'example': lt('Par exemple, Rasoa vend des brochettes.'),
  'hints': [lt('Pense à ta journée d’hier.')],
};

Map<String, Object?> question(
  String id, {
  String kind = 'text',
  List<String>? options,
  bool optional = false,
}) => {
  'id': id,
  'type': 'question',
  'prompt': lt('Question $id ?'),
  'answer': {
    'kind': kind,
    if (options != null)
      'options': [
        for (final o in options) {'value': o, 'label': lt(o)},
      ],
    if (kind == 'text') 'max_length': 300,
  },
  'help': help(),
  if (optional) 'optional': true,
};

Map<String, Object?> fixturePack() => {
  'format': 1,
  'pack_id': 'base',
  'version': '2026.10.1',
  'min_app_version': 1,
  'block_types': ['text', 'question', 'synthesis', 'mission', 'example'],
  'quests': [
    {
      'id': 'diag',
      'kind': 'diagnostic',
      'order': 0,
      'maturity': 'exploration',
      'title': lt('Diagnostic', mg: 'Fanadihadiana', mgStatus: 'needs_review'),
      'summary': lt('Faisons connaissance'),
      'steps': [
        {
          'id': 'diag.s01',
          'type': 'checkpoint',
          'title': lt('Ton idée'),
          'blocks': [
            question(
              'stage',
              kind: 'choice',
              options: ['no_idea', 'vague_idea', 'existing_activity'],
            ),
            question('hours', kind: 'number'),
            question('name'),
          ],
          'outputs': [
            {'from': 'stage', 'fact': 'diag.idea_stage'},
            {'from': 'hours', 'fact': 'diag.weekly_hours'},
            {'from': 'name', 'project_title': true},
          ],
        },
      ],
    },
    {
      'id': 'q01',
      'order': 1,
      'maturity': 'exploration',
      'priority': 10,
      'title': lt('Trouver un problème'),
      'summary': lt('Observer autour de toi'),
      'fast_track_when': {'fact': 'diag.idea_stage', 'eq': 'existing_activity'},
      'steps': [
        {
          'id': 'q01.s01',
          'type': 'learn',
          'title': lt('Pourquoi un problème ?'),
          'blocks': [
            {
              'id': 'intro',
              'type': 'text',
              'body': lt('Une entreprise résout un problème.'),
            },
            {
              'id': 'ex',
              'type': 'example',
              'body': lt('Le soir, il manque du pain.'),
            },
          ],
        },
        {
          'id': 'q01.s02',
          'type': 'reflect',
          'title': lt('Le problème que tu vois'),
          'blocks': [
            question('problem'),
            question('who', optional: true),
            {
              'id': 'recap',
              'type': 'synthesis',
              'intro': lt('Voici ce que tu as écrit'),
              'shows': ['problem', 'who'],
            },
          ],
          'outputs': [
            {
              'from': 'problem',
              'section': 'problem',
              'field': 'statement',
              'tracked': true,
            },
          ],
        },
        {
          'id': 'q01.s03',
          'type': 'act',
          'title': lt('Va observer'),
          'blocks': [
            {'id': 'go', 'type': 'mission', 'mission': 'm.observe'},
          ],
          'complete_when': {'mission': 'm.observe', 'is': 'completed'},
        },
      ],
    },
    {
      'id': 'q02',
      'order': 2,
      'maturity': 'exploration',
      'title': lt('Tes futurs clients'),
      'summary': lt('Qui a ce problème ?'),
      'available_when': {'quest': 'q01', 'is': 'completed'},
      'steps': [
        {
          'id': 'q02.s01',
          'type': 'learn',
          'title': lt('Les clients'),
          'blocks': [
            {'id': 'intro', 'type': 'text', 'body': lt('Un client paie.')},
          ],
        },
      ],
    },
  ],
  'missions': [
    {
      'id': 'm.observe',
      'title': lt('Observe ton quartier'),
      'objective': lt('Repérer un problème réel'),
      'instructions': [lt('Marche 30 minutes'), lt('Note ce qui manque')],
      'deliverable': lt('Qu’as-tu vu ?'),
      'duration_minutes': 30,
      'difficulty': 1,
    },
  ],
};
