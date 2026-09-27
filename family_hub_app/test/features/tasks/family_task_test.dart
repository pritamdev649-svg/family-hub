import 'package:flutter_test/flutter_test.dart';

import 'package:family_hub/features/tasks/application/tasks_filter.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_grouping.dart';
import 'package:family_hub/features/tasks/domain/task_permissions.dart';
import 'package:family_hub/features/tasks/domain/task_query.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/features/tasks/domain/task_templates.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_meta.dart';
import 'package:family_hub/l10n/app_localizations_en.dart';
import 'package:family_hub/shared/models/member.dart';

import 'tasks_test_helpers.dart';

void main() {
  group('FamilyTask.fromJson', () {
    test('parses a full contract Task', () {
      final task = FamilyTask.fromJson({
        'id': '64f1a0000000000000000301',
        'title': '  Finish maths homework ',
        'description': 'Ch. 4',
        'assigneeId': 'm1',
        'assigneeName': 'Aarav',
        'createdById': 'm2',
        'createdByName': 'Amit',
        'dueDate': '2026-09-25T18:30:00.000Z',
        'category': 'study',
        'priority': 'high',
        'status': 'done',
        'completedAt': '2026-09-26T10:15:00.000Z',
        'completedById': 'm2',
        'createdAt': '2026-09-20T08:00:00.000Z',
        'updatedAt': '2026-09-26T10:15:00.000Z',
        'extra': {'ignored': true},
      });

      expect(task.id, '64f1a0000000000000000301');
      expect(task.title, 'Finish maths homework');
      expect(task.description, 'Ch. 4');
      expect(task.assigneeName, 'Aarav');
      expect(task.createdByName, 'Amit');
      expect(task.category, TaskCategory.study);
      expect(task.priority, TaskPriority.high);
      expect(task.status, TaskStatus.done);
      expect(task.isDone, isTrue);
      expect(task.completedAt, DateTime.utc(2026, 9, 26, 10, 15));
      expect(task.completedById, 'm2');
      // India local midnight of Sep 26 → calendar day Sep 26 for everyone.
      expect(task.dueDay, DateTime(2026, 9, 26));
    });

    test('never throws on missing, null or odd fields', () {
      final task = FamilyTask.fromJson({
        '_id': 'abc',
        'title': 42,
        'description': '   ',
        'dueDate': 'not a date',
        'category': 'gardening',
        'priority': null,
        'status': 'archived',
        'completedById': '',
      });

      expect(task.id, 'abc');
      expect(task.title, '42');
      expect(task.description, isNull);
      expect(task.assigneeId, '');
      expect(task.assigneeName, '');
      expect(task.dueDate, isNull);
      expect(task.dueDay, isNull);
      expect(task.category, TaskCategory.other);
      expect(task.priority, TaskPriority.medium);
      expect(task.status, TaskStatus.pending);
      expect(task.completedById, isNull);
      expect(task.createdAt, isNull);
    });

    test('toJson round-trips and uses wire names', () {
      final task = makeTask(
        't1',
        due: dueIn(2),
        category: TaskCategory.errand,
        priority: TaskPriority.low,
        status: TaskStatus.done,
      );
      final json = task.toJson();
      expect(json['category'], 'errand');
      expect(json['priority'], 'low');
      expect(json['status'], 'done');
      expect(json['dueDate'], endsWith('Z'));
      expect(FamilyTask.fromJson(json), task);
    });

    test('copyWith keeps values and clears nullable fields', () {
      final task = makeTask('t1', due: dueIn(1));
      final cleared = task.copyWith(dueDate: () => null, title: 'New');
      expect(cleared.dueDate, isNull);
      expect(cleared.title, 'New');
      expect(cleared.assigneeId, task.assigneeId);
      expect(task.copyWith(), task);
      expect(task.copyWith().hashCode, task.hashCode);
    });
  });

  group('due helpers', () {
    final now = DateTime(2026, 9, 26, 15);

    FamilyTask dueOn(int y, int m, int d, {TaskStatus? status}) => makeTask(
      'x',
      due: DateTime(y, m, d).toUtc(),
      status: status ?? TaskStatus.pending,
    );

    test('isOverdueOn: pending and due before today', () {
      expect(dueOn(2026, 9, 25).isOverdueOn(now), isTrue);
      expect(dueOn(2026, 9, 26).isOverdueOn(now), isFalse);
      expect(dueOn(2026, 9, 27).isOverdueOn(now), isFalse);
      expect(
        dueOn(2026, 9, 20, status: TaskStatus.done).isOverdueOn(now),
        isFalse,
      );
      expect(makeTask('n').isOverdueOn(now), isFalse);
    });

    test('isDueOn matches the calendar day whatever the status', () {
      expect(dueOn(2026, 9, 26).isDueOn(now), isTrue);
      expect(dueOn(2026, 9, 26, status: TaskStatus.done).isDueOn(now), isTrue);
      expect(dueOn(2026, 9, 27).isDueOn(now), isFalse);
    });

    test('isOverdue / isDueToday use the device clock', () {
      expect(makeTask('a', due: dueIn(-1)).isOverdue, isTrue);
      expect(makeTask('b', due: dueIn(0)).isDueToday, isTrue);
      expect(makeTask('c', due: dueIn(0)).isOverdue, isFalse);
    });
  });

  group('date boundaries', () {
    final l10n = AppLocalizationsEn();

    test('due days read the same in every viewer time zone', () {
      // Local midnight of Oct 1 sent from India (+05:30) and California
      // (−07:00), and UTC midnight (server seeds): always Oct 1.
      for (final instant in [
        DateTime.utc(2026, 9, 30, 18, 30),
        DateTime.utc(2026, 10, 1, 7),
        DateTime.utc(2026, 10, 1),
      ]) {
        final task = makeTask('x', due: instant);
        expect(task.dueDay, DateTime(2026, 10, 1), reason: '$instant');
      }
      expect(
        FamilyTask.fromJson(const {
          'id': 'x',
          'dueDate': '2026-09-30T18:30:00.000Z',
        }).dueDay,
        DateTime(2026, 10, 1),
      );
    });

    test('month and year boundaries: overdue, sections, labels', () {
      final newYearsEve = DateTime(2026, 12, 31, 23, 59);
      final jan1 = makeTask('a', due: DateTime(2027).toUtc());
      final dec31 = makeTask('b', due: DateTime(2026, 12, 31).toUtc());
      final nov30 = makeTask('c', due: DateTime(2026, 11, 30).toUtc());

      expect(jan1.isOverdueOn(newYearsEve), isFalse);
      expect(dec31.isOverdueOn(newYearsEve), isFalse);
      expect(nov30.isOverdueOn(newYearsEve), isTrue);
      expect(sectionOf(jan1, newYearsEve), TaskSection.upcoming);
      expect(sectionOf(dec31, newYearsEve), TaskSection.today);
      // One minute later it is a new day (and a new year).
      final midnight = DateTime(2027, 1, 1, 0, 0);
      expect(sectionOf(dec31, midnight), TaskSection.overdue);
      expect(dec31.isOverdueOn(midnight), isTrue);
      expect(sectionOf(jan1, midnight), TaskSection.today);

      expect(daysFromToday(DateTime(2027), now: newYearsEve), 1);
      expect(
        daysFromToday(DateTime(2026, 2, 28), now: DateTime(2026, 3, 1)),
        -1,
      );
      expect(
        daysFromToday(DateTime(2024, 3, 1), now: DateTime(2024, 2, 28)),
        2,
      );
      expect(
        dueDayRelative(DateTime(2027), l10n, now: newYearsEve),
        'Tomorrow',
      );
      expect(
        dueDayRelative(DateTime(2026, 11, 30), l10n, now: newYearsEve),
        '31 days ago',
      );
      expect(
        dueDayRelative(DateTime(2027, 1, 5), l10n, now: newYearsEve),
        'in 5 days',
      );
    });

    test('daysFromToday ignores the time of day and DST shifts', () {
      // Whole calendar days only, even across spring-forward / fall-back
      // weekends in zones that have them.
      final morning = DateTime(2026, 3, 28, 1);
      expect(daysFromToday(DateTime(2026, 3, 30), now: morning), 2);
      final night = DateTime(2026, 10, 24, 23, 59);
      expect(daysFromToday(DateTime(2026, 10, 26), now: night), 2);
    });

    test('the draft sends the picked calendar day as local midnight', () {
      final json = TaskDraft(
        title: 't',
        assigneeId: 'm',
        dueDate: DateTime(2026, 12, 31, 18, 45),
      ).toJson();
      expect(
        DateTime.parse(json['dueDate'] as String),
        DateTime(2026, 12, 31).toUtc(),
      );
    });

    test('former members get a placeholder name', () {
      expect(taskPersonName(null, l10n), 'Former member');
      expect(taskPersonName('  ', l10n), 'Former member');
      expect(taskPersonName(' Priya ', l10n), 'Priya');
    });
  });

  group('groupTasks', () {
    test('orders sections and keeps server order inside', () {
      final tasks = [
        makeTask('o1', due: dueIn(-3)),
        makeTask('o2', due: dueIn(-1)),
        makeTask('t1', due: dueIn(0)),
        makeTask('u1', due: dueIn(2)),
        makeTask('n1'),
        makeTask('u2', due: dueIn(9)),
      ];
      final groups = groupTasks(tasks);
      expect(groups.map((g) => g.section), [
        TaskSection.overdue,
        TaskSection.today,
        TaskSection.upcoming,
        TaskSection.noDueDate,
      ]);
      expect(groups[0].tasks.map((t) => t.id), ['o1', 'o2']);
      expect(groups[2].tasks.map((t) => t.id), ['u1', 'u2']);
      expect(groups[3].tasks.map((t) => t.id), ['n1']);
    });

    test('an optimistically completed task stays in its section', () {
      final groups = groupTasks([
        makeTask('o1', due: dueIn(-2), status: TaskStatus.done),
      ]);
      expect(groups.single.section, TaskSection.overdue);
    });

    test('empty input → no sections', () {
      expect(groupTasks(const []), isEmpty);
    });
  });

  group('TaskDraft / TaskPatch', () {
    test('draft sends trimmed fields, local midnight and omits blanks', () {
      final draft = TaskDraft(
        title: '  Tidy room ',
        description: '   ',
        assigneeId: 'm1',
        dueDate: DateTime(2026, 9, 26),
        category: TaskCategory.chore,
        priority: TaskPriority.high,
      );
      final json = draft.toJson();
      expect(json['title'], 'Tidy room');
      expect(json.containsKey('description'), isFalse);
      expect(json['dueDate'], DateTime(2026, 9, 26).toUtc().toIso8601String());
      expect(json['category'], 'chore');
      expect(json['priority'], 'high');

      final noDue = const TaskDraft(title: 'x', assigneeId: 'm1').toJson();
      expect(noDue.containsKey('dueDate'), isFalse);
      expect(noDue['category'], 'other');
      expect(noDue['priority'], 'medium');
    });

    test('diff sends only changed fields', () {
      final before = makeTask(
        't1',
        title: 'Old',
        due: dueIn(3),
        priority: TaskPriority.low,
      );
      final unchanged = TaskPatch.diff(
        before,
        title: ' Old ',
        description: '',
        assigneeId: before.assigneeId,
        dueDate: before.dueDay,
        category: before.category,
        priority: before.priority,
      );
      expect(unchanged.isEmpty, isTrue);

      final changed = TaskPatch.diff(
        before,
        title: 'New',
        description: 'Details',
        assigneeId: 'm9',
        dueDate: before.dueDay,
        category: TaskCategory.study,
        priority: TaskPriority.low,
      );
      expect(changed.fields, {
        'title': 'New',
        'description': 'Details',
        'assigneeId': 'm9',
        'category': 'study',
      });
    });

    test('diff clears description and due date with null', () {
      final before = makeTask(
        't1',
        due: dueIn(1),
      ).copyWith(description: () => 'Something');
      final patch = TaskPatch.diff(
        before,
        title: before.title,
        description: '  ',
        assigneeId: before.assigneeId,
        dueDate: null,
        category: before.category,
        priority: before.priority,
      );
      expect(patch.fields, {'description': null, 'dueDate': null});
      expect(patch.toJson().containsKey('dueDate'), isTrue);
    });
  });

  group('TaskQuery / TasksFilter', () {
    test('query parameters use wire values and value equality', () {
      const q = TaskQuery(
        assigneeId: 'm1',
        status: TaskListStatus.done,
        due: TaskDueFilter.week,
      );
      expect(q.toQueryParameters(), {
        'assigneeId': 'm1',
        'status': 'done',
        'due': 'week',
      });
      expect(
        q,
        const TaskQuery(
          assigneeId: 'm1',
          status: TaskListStatus.done,
          due: TaskDueFilter.week,
        ),
      );
      expect(const TaskQuery().toQueryParameters()['due'], isNull);
    });

    test('filters map to the right query per view', () {
      const mine = TasksFilter(due: TaskDueChoice.today, memberId: 'x');
      expect(
        mine.toQuery('me'),
        const TaskQuery(assigneeId: 'me', due: TaskDueFilter.today),
      );
      const family = TasksFilter(
        view: TasksView.family,
        due: TaskDueChoice.overdue,
        memberId: 'm2',
      );
      expect(
        family.toQuery('me'),
        const TaskQuery(assigneeId: 'm2', due: TaskDueFilter.overdue),
      );
      const done = TasksFilter(view: TasksView.done, due: TaskDueChoice.week);
      expect(done.toQuery('me'), const TaskQuery(status: TaskListStatus.done));
      expect(done.showsDueFilter, isFalse);
      expect(mine.showsMemberFilter, isFalse);
    });
  });

  group('TaskPermissions', () {
    final byAmitForAarav = makeTask('t', assignee: aarav, creator: amit);
    final byAaravForAarav = makeTask('t2', assignee: aarav, creator: aarav);

    test('admin can do everything', () {
      final p = TaskPermissions.of(amit);
      expect(p.canAssignOthers, isTrue);
      expect(p.canAssignTo(anaya.id), isTrue);
      expect(p.canComplete(byAaravForAarav), isTrue);
      expect(p.canEdit(byAaravForAarav), isTrue);
    });

    test('member: create for self, complete own, edit only own creations', () {
      final p = TaskPermissions.of(aarav);
      expect(p.canCreate, isTrue);
      expect(p.canAssignOthers, isFalse);
      expect(p.canAssignTo(aarav.id), isTrue);
      expect(p.canAssignTo(anaya.id), isFalse);
      expect(p.canComplete(byAmitForAarav), isTrue);
      expect(p.canEdit(byAmitForAarav), isFalse);
      expect(p.canDelete(byAmitForAarav), isFalse);
      expect(p.canEdit(byAaravForAarav), isTrue);
      expect(p.canComplete(makeTask('k', assignee: kamla)), isFalse);
    });

    test('no member → nothing allowed', () {
      final p = TaskPermissions.of(null);
      expect(p.canCreate, isFalse);
      expect(p.canComplete(byAmitForAarav), isFalse);
      expect(p.canEdit(byAmitForAarav), isFalse);
    });
  });

  group('TaskTemplate.forAgeGroup', () {
    test('age-appropriate suggestions', () {
      expect(TaskTemplate.forAgeGroup(AgeGroup.child), [
        TaskTemplate.homework,
        TaskTemplate.tidyRoom,
        TaskTemplate.readTwentyMinutes,
      ]);
      expect(
        TaskTemplate.forAgeGroup(AgeGroup.teen),
        contains(TaskTemplate.budgetPractice),
      );
      expect(
        TaskTemplate.forAgeGroup(AgeGroup.senior),
        contains(TaskTemplate.medicineReminder),
      );
      expect(
        TaskTemplate.forAgeGroup(null),
        TaskTemplate.forAgeGroup(AgeGroup.adult),
      );
      expect(TaskTemplate.medicineReminder.category, TaskCategory.health);
    });
  });
}
