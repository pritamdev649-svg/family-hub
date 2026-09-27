import 'package:flutter/material.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/widgets/money_text.dart';
import 'package:family_hub/features/ledger/domain/ledger_entry.dart';
import 'package:family_hub/features/ledger/domain/ledger_summary.dart';
import 'package:family_hub/features/ledger/domain/savings_goal.dart';
import 'package:family_hub/l10n/app_localizations.dart';

// Localised labels and icons for the ledger enums
// (docs/05-FLUTTER_GUIDE.md §6). Usage: `entry.category.label(context.l10n)`.

extension LedgerTypeLabels on LedgerType {
  String label(AppLocalizations l10n) => switch (this) {
    LedgerType.income => l10n.ledgerTypeIncome,
    LedgerType.expense => l10n.ledgerTypeExpense,
  };

  /// "Add income" / "Add expense".
  String addLabel(AppLocalizations l10n) => switch (this) {
    LedgerType.income => l10n.ledgerAddIncome,
    LedgerType.expense => l10n.ledgerAddExpense,
  };

  IconData get icon => switch (this) {
    LedgerType.income => AppIcons.income,
    LedgerType.expense => AppIcons.expense,
  };

  /// Sign and colour for [MoneyText].
  LedgerFlow get flow => switch (this) {
    LedgerType.income => LedgerFlow.income,
    LedgerType.expense => LedgerFlow.expense,
  };

  /// Semantic income / expense colour.
  Color color(BuildContext context) => switch (this) {
    LedgerType.income => context.semanticColors.income,
    LedgerType.expense => context.semanticColors.expense,
  };

  /// Module accent: income emerald, expense rose
  /// (docs/12-DESIGN_LANGUAGE.md §1.2).
  AppAccent get accent => switch (this) {
    LedgerType.income => AppAccents.income,
    LedgerType.expense => AppAccents.expense,
  };
}

extension LedgerCategoryLabels on LedgerCategory {
  String label(AppLocalizations l10n) => switch (this) {
    LedgerCategory.salary => l10n.ledgerCategorySalary,
    LedgerCategory.business => l10n.ledgerCategoryBusiness,
    LedgerCategory.allowance => l10n.ledgerCategoryAllowance,
    LedgerCategory.gift => l10n.ledgerCategoryGift,
    LedgerCategory.interest => l10n.ledgerCategoryInterest,
    LedgerCategory.otherIncome => l10n.ledgerCategoryOtherIncome,
    LedgerCategory.groceries => l10n.ledgerCategoryGroceries,
    LedgerCategory.utilities => l10n.ledgerCategoryUtilities,
    LedgerCategory.rent => l10n.ledgerCategoryRent,
    LedgerCategory.education => l10n.ledgerCategoryEducation,
    LedgerCategory.health => l10n.ledgerCategoryHealth,
    LedgerCategory.transport => l10n.ledgerCategoryTransport,
    LedgerCategory.dining => l10n.ledgerCategoryDining,
    LedgerCategory.shopping => l10n.ledgerCategoryShopping,
    LedgerCategory.entertainment => l10n.ledgerCategoryEntertainment,
    LedgerCategory.householdHelp => l10n.ledgerCategoryHouseholdHelp,
    LedgerCategory.savings => l10n.ledgerCategorySavings,
    LedgerCategory.otherExpense => l10n.ledgerCategoryOtherExpense,
  };

  IconData get icon => switch (this) {
    LedgerCategory.salary => AppIcons.catSalary,
    LedgerCategory.business => AppIcons.catBusiness,
    LedgerCategory.allowance => AppIcons.catAllowance,
    LedgerCategory.gift => AppIcons.catGift,
    LedgerCategory.interest => AppIcons.catInterest,
    LedgerCategory.otherIncome => AppIcons.catOtherIncome,
    LedgerCategory.groceries => AppIcons.catGroceries,
    LedgerCategory.utilities => AppIcons.catUtilities,
    LedgerCategory.rent => AppIcons.catRent,
    LedgerCategory.education => AppIcons.catEducation,
    LedgerCategory.health => AppIcons.catHealth,
    LedgerCategory.transport => AppIcons.catTransport,
    LedgerCategory.dining => AppIcons.catDining,
    LedgerCategory.shopping => AppIcons.catShopping,
    LedgerCategory.entertainment => AppIcons.catEntertainment,
    LedgerCategory.householdHelp => AppIcons.catHouseholdHelp,
    LedgerCategory.savings => AppIcons.goal,
    LedgerCategory.otherExpense => AppIcons.catOtherExpense,
  };

  /// Fixed colour of the category's [IconBadge] and bars, so a category
  /// looks the same on every screen (groceries always orange, rent always
  /// violet, …). Savings uses the goals accent.
  AppAccent get accent => switch (this) {
    LedgerCategory.salary => AppAccent.emerald,
    LedgerCategory.business => AppAccent.teal,
    LedgerCategory.allowance => AppAccent.sky,
    LedgerCategory.gift => AppAccent.pink,
    LedgerCategory.interest => AppAccent.blue,
    LedgerCategory.otherIncome => AppAccent.indigo,
    LedgerCategory.groceries => AppAccent.orange,
    LedgerCategory.utilities => AppAccent.amber,
    LedgerCategory.rent => AppAccent.violet,
    LedgerCategory.education => AppAccent.blue,
    LedgerCategory.health => AppAccent.red,
    LedgerCategory.transport => AppAccent.sky,
    LedgerCategory.dining => AppAccent.rose,
    LedgerCategory.shopping => AppAccent.pink,
    LedgerCategory.entertainment => AppAccent.indigo,
    LedgerCategory.householdHelp => AppAccent.teal,
    LedgerCategory.savings => AppAccents.goals,
    LedgerCategory.otherExpense => AppAccent.violet,
  };
}

extension GoalStatusLabels on GoalStatus {
  String label(AppLocalizations l10n) => switch (this) {
    GoalStatus.active => l10n.ledgerGoalStatusActive,
    GoalStatus.achieved => l10n.ledgerGoalStatusAchieved,
    GoalStatus.archived => l10n.ledgerGoalStatusArchived,
  };

  IconData get icon => switch (this) {
    GoalStatus.active => AppIcons.goalOutlined,
    GoalStatus.achieved => AppIcons.goalAchieved,
    GoalStatus.archived => AppIcons.archive,
  };

  /// Theme / semantic colour for chips and progress bars.
  Color color(BuildContext context) => switch (this) {
    GoalStatus.active => context.accent(AppAccents.goals).foreground,
    GoalStatus.achieved => context.semanticColors.success,
    GoalStatus.archived => Theme.of(context).colorScheme.onSurfaceVariant,
  };
}

/// Gradients the goal cards cycle through (pink / violet / teal, like a
/// wallet of payment cards).
const List<AppAccent> goalCardAccents = [
  AppAccents.goals,
  AppAccent.violet,
  AppAccent.teal,
];

extension SavingsGoalStyle on SavingsGoal {
  /// Stable card accent for this goal (same colour on every screen and every
  /// app start), used when the caller does not pick one by position.
  AppAccent get cardAccent {
    var hash = 0;
    for (final unit in id.codeUnits) {
      hash = (hash * 31 + unit) & 0x3fffffff;
    }
    return goalCardAccents[hash % goalCardAccents.length];
  }
}

extension SummaryScopeLabels on SummaryScope {
  String label(AppLocalizations l10n) => switch (this) {
    SummaryScope.family => l10n.ledgerScopeFamily,
    SummaryScope.personal => l10n.ledgerScopePersonal,
  };

  /// One-line explanation for screen readers / tooltips.
  String description(AppLocalizations l10n) => switch (this) {
    SummaryScope.family => l10n.ledgerScopeFamilyHint,
    SummaryScope.personal => l10n.ledgerScopePersonalHint,
  };

  IconData get icon => switch (this) {
    SummaryScope.family => AppIcons.family,
    SummaryScope.personal => AppIcons.member,
  };
}
