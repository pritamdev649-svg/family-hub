import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/shared/models/member.dart';

/// Age-appropriate quick templates offered on the new-task form, based on
/// the assignee's [AgeGroup]. Titles / descriptions are localised in
/// `presentation/tasks_labels.dart` (`TaskTemplateLabels`).
enum TaskTemplate {
  // child (< 13)
  homework(TaskCategory.study, TaskPriority.high),
  tidyRoom(TaskCategory.chore, TaskPriority.medium),
  readTwentyMinutes(TaskCategory.study, TaskPriority.medium),
  // teen (13–17)
  learnSkill(TaskCategory.skill, TaskPriority.medium),
  helpCook(TaskCategory.chore, TaskPriority.medium),
  budgetPractice(TaskCategory.skill, TaskPriority.low),
  // adult (18–59)
  payBills(TaskCategory.errand, TaskPriority.high),
  familyCheckIn(TaskCategory.other, TaskPriority.medium),
  // senior (60+)
  medicineReminder(TaskCategory.health, TaskPriority.high),
  dailyWalk(TaskCategory.health, TaskPriority.medium);

  const TaskTemplate(this.category, this.priority);

  final TaskCategory category;
  final TaskPriority priority;

  /// Templates for an assignee of [group]. Members without a date of birth
  /// (`null`) get the adult suggestions.
  static List<TaskTemplate> forAgeGroup(AgeGroup? group) => switch (group) {
    AgeGroup.child => const [homework, tidyRoom, readTwentyMinutes],
    AgeGroup.teen => const [learnSkill, helpCook, budgetPractice],
    AgeGroup.senior => const [medicineReminder, dailyWalk],
    AgeGroup.adult || null => const [payBills, familyCheckIn],
  };
}
