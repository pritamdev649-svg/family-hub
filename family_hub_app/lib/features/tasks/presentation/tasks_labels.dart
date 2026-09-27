import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/features/tasks/application/tasks_filter.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_grouping.dart';
import 'package:family_hub/features/tasks/domain/task_templates.dart';
import 'package:family_hub/l10n/app_localizations.dart';

/// Category icons of the tasks feature (`const IconData`, see
/// docs/05-FLUTTER_GUIDE.md §3 `app_icons.dart`).
abstract final class TaskIcons {
  static const IconData study = AppIcons.taskStudy;
  static const IconData chore = AppIcons.taskChore;
  static const IconData skill = AppIcons.taskSkill;
  static const IconData health = AppIcons.taskHealth;
  static const IconData errand = AppIcons.taskErrand;
  static const IconData other = AppIcons.taskOther;

  static const IconData priorityHigh = AppIcons.priorityHigh;
  static const IconData priorityMedium = AppIcons.priorityMedium;
  static const IconData priorityLow = AppIcons.priorityLow;

  static const IconData template = AppIcons.template;
}

extension TaskCategoryLabels on TaskCategory {
  String label(AppLocalizations l10n) => switch (this) {
    TaskCategory.study => l10n.tasksCategoryStudy,
    TaskCategory.chore => l10n.tasksCategoryChore,
    TaskCategory.skill => l10n.tasksCategorySkill,
    TaskCategory.health => l10n.tasksCategoryHealth,
    TaskCategory.errand => l10n.tasksCategoryErrand,
    TaskCategory.other => l10n.tasksCategoryOther,
  };

  IconData get icon => switch (this) {
    TaskCategory.study => TaskIcons.study,
    TaskCategory.chore => TaskIcons.chore,
    TaskCategory.skill => TaskIcons.skill,
    TaskCategory.health => TaskIcons.health,
    TaskCategory.errand => TaskIcons.errand,
    TaskCategory.other => TaskIcons.other,
  };

  /// Colour of the category's [IconBadge] and chips, so every category is
  /// recognisable at a glance (always paired with [icon] and the label).
  AppAccent get accent => switch (this) {
    TaskCategory.study => AppAccent.blue,
    TaskCategory.chore => AppAccent.teal,
    TaskCategory.skill => AppAccent.amber,
    TaskCategory.health => AppAccent.rose,
    TaskCategory.errand => AppAccent.orange,
    TaskCategory.other => AppAccent.indigo,
  };
}

extension TaskPriorityLabels on TaskPriority {
  String label(AppLocalizations l10n) => switch (this) {
    TaskPriority.low => l10n.tasksPriorityLow,
    TaskPriority.medium => l10n.tasksPriorityMedium,
    TaskPriority.high => l10n.tasksPriorityHigh,
  };

  IconData get icon => switch (this) {
    TaskPriority.low => TaskIcons.priorityLow,
    TaskPriority.medium => TaskIcons.priorityMedium,
    TaskPriority.high => TaskIcons.priorityHigh,
  };

  /// Accent of the priority pill / selector: high rose, medium amber, low
  /// sky (never the only signal: the icon shape and the label differ too).
  AppAccent get accent => switch (this) {
    TaskPriority.low => AppAccent.sky,
    TaskPriority.medium => AppAccent.amber,
    TaskPriority.high => AppAccent.rose,
  };

  /// Accent-coloured text / icon colour of the priority on the normal
  /// surface (AA contrast in both themes).
  Color color(BuildContext context) => context.accent(accent).foreground;
}

extension TaskStatusLabels on TaskStatus {
  String label(AppLocalizations l10n) => switch (this) {
    TaskStatus.pending => l10n.tasksStatusPending,
    TaskStatus.done => l10n.tasksStatusDone,
  };
}

extension TaskSectionLabels on TaskSection {
  String label(AppLocalizations l10n) => switch (this) {
    TaskSection.overdue => l10n.tasksSectionOverdue,
    TaskSection.today => l10n.tasksSectionToday,
    TaskSection.upcoming => l10n.tasksSectionUpcoming,
    TaskSection.noDueDate => l10n.tasksSectionNoDueDate,
  };

  /// Colour of the section's dot; matches the due-date chip of the same
  /// range ([TaskDueChoiceLabels.accent]).
  AppAccent get accent => switch (this) {
    TaskSection.overdue => AppAccent.rose,
    TaskSection.today => AppAccents.tasks,
    TaskSection.upcoming => AppAccent.blue,
    TaskSection.noDueDate => AppAccent.sky,
  };
}

extension TasksViewLabels on TasksView {
  String label(AppLocalizations l10n) => switch (this) {
    TasksView.mine => l10n.tasksViewMine,
    TasksView.family => l10n.tasksViewFamily,
    TasksView.done => l10n.tasksViewDone,
  };

  IconData get icon => switch (this) {
    TasksView.mine => AppIcons.member,
    TasksView.family => AppIcons.family,
    TasksView.done => AppIcons.doneAll,
  };
}

extension TaskDueChoiceLabels on TaskDueChoice {
  String label(AppLocalizations l10n) => switch (this) {
    TaskDueChoice.all => l10n.commonAll,
    TaskDueChoice.overdue => l10n.tasksDueOverdue,
    TaskDueChoice.today => l10n.tasksDueToday,
    TaskDueChoice.week => l10n.tasksDueWeek,
  };

  IconData get icon => switch (this) {
    TaskDueChoice.all => AppIcons.task,
    TaskDueChoice.overdue => AppIcons.overdue,
    TaskDueChoice.today => AppIcons.dueDate,
    TaskDueChoice.week => AppIcons.calendar,
  };

  AppAccent get accent => switch (this) {
    TaskDueChoice.all => AppAccents.brand,
    TaskDueChoice.overdue => AppAccent.rose,
    TaskDueChoice.today => AppAccents.tasks,
    TaskDueChoice.week => AppAccent.blue,
  };
}

extension TaskTemplateLabels on TaskTemplate {
  String title(AppLocalizations l10n) => switch (this) {
    TaskTemplate.homework => l10n.tasksTemplateHomeworkTitle,
    TaskTemplate.tidyRoom => l10n.tasksTemplateTidyRoomTitle,
    TaskTemplate.readTwentyMinutes => l10n.tasksTemplateReadTitle,
    TaskTemplate.learnSkill => l10n.tasksTemplateLearnSkillTitle,
    TaskTemplate.helpCook => l10n.tasksTemplateHelpCookTitle,
    TaskTemplate.budgetPractice => l10n.tasksTemplateBudgetTitle,
    TaskTemplate.payBills => l10n.tasksTemplatePayBillsTitle,
    TaskTemplate.familyCheckIn => l10n.tasksTemplateCheckInTitle,
    TaskTemplate.medicineReminder => l10n.tasksTemplateMedicineTitle,
    TaskTemplate.dailyWalk => l10n.tasksTemplateWalkTitle,
  };

  String description(AppLocalizations l10n) => switch (this) {
    TaskTemplate.homework => l10n.tasksTemplateHomeworkDescription,
    TaskTemplate.tidyRoom => l10n.tasksTemplateTidyRoomDescription,
    TaskTemplate.readTwentyMinutes => l10n.tasksTemplateReadDescription,
    TaskTemplate.learnSkill => l10n.tasksTemplateLearnSkillDescription,
    TaskTemplate.helpCook => l10n.tasksTemplateHelpCookDescription,
    TaskTemplate.budgetPractice => l10n.tasksTemplateBudgetDescription,
    TaskTemplate.payBills => l10n.tasksTemplatePayBillsDescription,
    TaskTemplate.familyCheckIn => l10n.tasksTemplateCheckInDescription,
    TaskTemplate.medicineReminder => l10n.tasksTemplateMedicineDescription,
    TaskTemplate.dailyWalk => l10n.tasksTemplateWalkDescription,
  };
}
