import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:family_hub/core/design/design.dart';
import 'package:family_hub/core/l10n/l10n.dart';
import 'package:family_hub/core/utils/validators.dart';
import 'package:family_hub/core/widgets/widgets.dart';
import 'package:family_hub/features/tasks/application/task_providers.dart';
import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/features/tasks/domain/task_failure.dart';
import 'package:family_hub/features/tasks/domain/task_permissions.dart';
import 'package:family_hub/features/tasks/domain/task_requests.dart';
import 'package:family_hub/features/tasks/domain/task_templates.dart';
import 'package:family_hub/features/tasks/presentation/task_errors.dart';
import 'package:family_hub/features/tasks/presentation/task_navigation.dart';
import 'package:family_hub/features/tasks/presentation/tasks_labels.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_choice_chip.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_gone_view.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_priority_selector.dart';
import 'package:family_hub/features/tasks/presentation/widgets/task_state_card.dart';
import 'package:family_hub/shared/models/member.dart';
import 'package:family_hub/shared/providers/shared_providers.dart';

/// `/tasks/new` (`?assigneeId=` pre-selects the assignee) and
/// `/tasks/:id/edit`.
///
/// A plain canvas app bar, then the fields grouped into borderless cards
/// with colourful section headers: assignee, quick ideas, the task itself,
/// due date, category chips (each in its category colour) and the colourful
/// priority picker; the gradient submit button closes the form.
///
/// Admins can assign anyone; members only themselves (the field is locked).
/// New tasks offer age-appropriate quick ideas for the chosen assignee.
///
/// Editing a task that was deleted meanwhile (`404`, discovered on load, on
/// a refresh or when saving) shows [TaskGoneView]; a task whose assignee
/// left the family can be saved without re-assigning it.
class TaskFormScreen extends ConsumerWidget {
  const TaskFormScreen({super.key, this.taskId, this.initialAssigneeId});

  /// Task to edit; `null` creates a new task.
  final String? taskId;

  /// Assignee to pre-select on a new task (ignored when not allowed).
  final String? initialAssigneeId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = context.l10n;
    final id = taskId;
    // Watch everything here: the AsyncValueView builders below run during
    // their own build, where `ref.watch` must not be called.
    final membersAsync = ref.watch(membersProvider);
    final taskAsync = id == null ? null : ref.watch(taskByIdProvider(id));
    final mutations = ref.watch(taskControllerProvider);
    final perms = ref.watch(taskPermissionsProvider);

    Widget withMembers(Widget Function(List<Member> members) builder) {
      return AsyncValueView<List<Member>>(
        value: membersAsync,
        onRetry: () => ref.invalidate(membersProvider),
        data: builder,
      );
    }

    final Widget body;
    if (id == null || taskAsync == null) {
      body = !perms.canCreate
          ? _FormMessage(
              child: TaskStateCard(
                icon: AppIcons.security,
                accent: AppAccents.warning,
                title: l10n.tasksCreateNotAllowedTitle,
                message: l10n.tasksCreateNotAllowedMessage,
              ),
            )
          : withMembers(
              (members) => _TaskForm(
                members: members,
                initialAssigneeId: initialAssigneeId,
              ),
            );
    } else if (mutations.isDeleted(id) ||
        (!taskAsync.isLoading &&
            taskAsync.error != null &&
            TaskFailure.of(taskAsync.error!) == TaskFailure.gone)) {
      body = const _FormMessage(child: TaskGoneView());
    } else {
      body = AsyncValueView<FamilyTask>(
        value: taskAsync,
        onRetry: () => ref.invalidate(taskByIdProvider(id)),
        data: (base) {
          final task = mutations.resolve(base);
          if (!perms.canEdit(task)) {
            return _FormMessage(
              child: TaskStateCard(
                icon: AppIcons.security,
                accent: AppAccents.warning,
                title: l10n.tasksEditNotAllowedTitle,
                message: l10n.tasksEditNotAllowedMessage,
              ),
            );
          }
          return withMembers(
            (members) => _TaskForm(
              key: ValueKey(task.id),
              members: members,
              initial: task,
            ),
          );
        },
      );
    }

    // Leading back button with the app's thin icon; it goes through
    // `maybePop`, so the unsaved-changes guard of the form still applies.
    final canGoBack = ModalRoute.of(context)?.impliesAppBarDismissal ?? false;
    return Scaffold(
      appBar: AppBar(
        leading: canGoBack
            ? IconButton(
                icon: const Icon(AppIcons.back),
                tooltip: MaterialLocalizations.of(context).backButtonTooltip,
                onPressed: () => Navigator.maybePop(context),
              )
            : null,
        title: Text(
          id == null ? l10n.tasksFormNewTitle : l10n.tasksFormEditTitle,
        ),
      ),
      body: ResponsiveCenter(child: body),
    );
  }
}

class _TaskForm extends ConsumerStatefulWidget {
  const _TaskForm({
    super.key,
    required this.members,
    this.initial,
    this.initialAssigneeId,
  });

  final List<Member> members;
  final FamilyTask? initial;
  final String? initialAssigneeId;

  @override
  ConsumerState<_TaskForm> createState() => _TaskFormState();
}

class _TaskFormState extends ConsumerState<_TaskForm> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _title;
  late final TextEditingController _description;
  String? _assigneeId;
  DateTime? _dueDate;
  late TaskCategory _category;
  late TaskPriority _priority;
  bool _saving = false;
  bool _dirty = false;

  /// The task as it was when the form opened: changes are computed against
  /// it, so a refetch while editing never sends fields the user left alone.
  FamilyTask? _initial;
  bool get _isEdit => _initial != null;

  @override
  void initState() {
    super.initState();
    final initial = _initial = widget.initial;
    final perms = ref.read(taskPermissionsProvider);
    _title = TextEditingController(text: initial?.title ?? '');
    _description = TextEditingController(text: initial?.description ?? '');
    _assigneeId = initial?.assigneeId ?? _defaultAssignee(perms);
    _dueDate = initial?.dueDay;
    _category = initial?.category ?? TaskCategory.other;
    _priority = initial?.priority ?? TaskPriority.medium;
    _title.addListener(_updateDirty);
    _description.addListener(_updateDirty);
    // The task names an assignee our member list does not know: the list is
    // stale (e.g. a member added on another phone), so refetch it.
    if (initial != null &&
        initial.assigneeName.trim().isNotEmpty &&
        !widget.members.any((m) => m.id == initial.assigneeId)) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) ref.markChanged({DataScope.members});
      });
    }
  }

  /// `?assigneeId=` when allowed and known, else the caller.
  String? _defaultAssignee(TaskPermissions perms) {
    final requested = widget.initialAssigneeId;
    if (requested != null &&
        perms.canAssignTo(requested) &&
        widget.members.any((m) => m.id == requested)) {
      return requested;
    }
    return perms.memberId;
  }

  @override
  void dispose() {
    _title.dispose();
    _description.dispose();
    super.dispose();
  }

  bool _computeDirty() {
    final initial = _initial;
    final title = _title.text.trim();
    final description = _description.text.trim();
    if (initial == null) {
      return title.isNotEmpty ||
          description.isNotEmpty ||
          _dueDate != null ||
          _category != TaskCategory.other ||
          _priority != TaskPriority.medium;
    }
    return title != initial.title.trim() ||
        description != (initial.description?.trim() ?? '') ||
        _assigneeId != initial.assigneeId ||
        _dueDate != initial.dueDay ||
        _category != initial.category ||
        _priority != initial.priority;
  }

  void _updateDirty() {
    final dirty = _computeDirty();
    if (dirty != _dirty && mounted) setState(() => _dirty = dirty);
  }

  void _change(VoidCallback update) {
    setState(update);
    _updateDirty();
  }

  void _applyTemplate(TaskTemplate template) {
    final l10n = context.l10n;
    _title.text = template.title(l10n);
    if (_description.text.trim().isEmpty) {
      _description.text = template.description(l10n);
    }
    _change(() {
      _category = template.category;
      _priority = template.priority;
    });
  }

  Future<void> _submit() async {
    if (_saving) return;
    FocusScope.of(context).unfocus();
    final form = _formKey.currentState;
    if (form == null || !form.validate()) return;
    final assigneeId = _assigneeId;
    if (assigneeId == null) return;

    final l10n = context.l10n;
    final controller = ref.read(taskControllerProvider.notifier);
    final myId = ref.read(taskPermissionsProvider).memberId;
    final initial = _initial;
    var action = initial == null ? TaskAction.create : TaskAction.update;
    setState(() => _saving = true);
    try {
      if (initial == null) {
        await controller.create(
          TaskDraft(
            title: _title.text,
            description: _description.text,
            assigneeId: assigneeId,
            dueDate: _dueDate,
            category: _category,
            priority: _priority,
          ),
        );
        if (!mounted) return;
        context.showSuccess(l10n.tasksCreated);
      } else {
        final patch = TaskPatch.diff(
          initial,
          title: _title.text,
          description: _description.text,
          assigneeId: assigneeId,
          dueDate: _dueDate,
          category: _category,
          priority: _priority,
        );
        if (patch.fields.containsKey('assigneeId') && assigneeId != myId) {
          action = TaskAction.reassign;
        }
        if (!patch.isEmpty) {
          await controller.update(initial.id, patch);
          if (!mounted) return;
          context.showSuccess(l10n.tasksUpdated);
        }
      }
      if (!mounted) return;
      // Saved: leaving must not ask to discard changes any more.
      setState(() => _dirty = false);
      closeTaskScreen(context);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      context.showTaskError(e, action);
    }
  }

  Future<void> _confirmDiscard() async {
    final l10n = context.l10n;
    final discard = await showConfirmDialog(
      context,
      title: l10n.commonDiscardChangesTitle,
      message: l10n.commonDiscardChangesMessage,
      confirmLabel: l10n.commonDiscard,
      destructive: true,
    );
    if (!discard || !mounted) return;
    setState(() => _dirty = false);
    closeTaskScreen(context);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final perms = ref.watch(taskPermissionsProvider);
    final myId = perms.memberId;

    // The assignee of an edited task may be missing from the member list:
    // they left the family (done tasks outlive removed members; the API then
    // sends no name) or the list is stale. Keeping them is allowed, the
    // server only checks the assignee when it changes.
    final initial = _initial;
    final keepsFormerAssignee =
        initial != null &&
        _assigneeId == initial.assigneeId &&
        !widget.members.any((m) => m.id == _assigneeId);
    final assigneeLeft =
        keepsFormerAssignee && initial.assigneeName.trim().isEmpty;

    // Admins pick anyone. Members may only choose themselves: locked on new
    // tasks; when editing, the current assignee or themselves.
    final isAdmin = perms.canAssignOthers;
    final options = isAdmin
        ? widget.members
        : [
            for (final m in widget.members)
              if (m.id == _assigneeId || m.id == myId) m,
          ];
    final canChangeAssignee =
        isAdmin ||
        options.length > 1 ||
        (keepsFormerAssignee && options.isNotEmpty);
    Member? selected;
    for (final m in options) {
      if (m.id == _assigneeId) selected = m;
    }
    final templates = _isEdit
        ? const <TaskTemplate>[]
        : TaskTemplate.forAgeGroup(selected?.ageGroup);
    final today = DateUtils.dateOnly(DateTime.now());
    final initialDue = _initial?.dueDay;
    final firstDate = initialDue != null && initialDue.isBefore(today)
        ? initialDue
        : today;

    return PopScope(
      canPop: !_dirty || _saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _confirmDiscard();
      },
      child: Form(
        key: _formKey,
        child: ListView(
          padding: EdgeInsetsDirectional.fromSTEB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
          children: [
            _FormSection(
              title: l10n.tasksFieldAssignee,
              icon: AppIcons.member,
              accent: AppAccents.family,
              children: [
                AppDropdownField<Member>(
                  label: l10n.tasksFieldAssignee,
                  value: selected,
                  items: options,
                  itemLabel: (m) =>
                      m.id == myId ? l10n.tasksAssigneeMe(m.name) : m.name,
                  leading: (m) => MemberAvatar(
                    name: m.name,
                    avatarUrl: m.avatarUrl,
                    radius: AppSizes.avatarSm,
                  ),
                  validator: canChangeAssignee
                      ? (m) => m == null && !keepsFormerAssignee
                            ? l10n.tasksFieldAssigneeRequired
                            : null
                      : null,
                  onChanged: canChangeAssignee && !_saving
                      ? (m) => _change(() => _assigneeId = m?.id)
                      : null,
                ),
                if (assigneeLeft) ...[
                  AppGap.sm,
                  _FieldHelper(l10n.tasksAssigneeFormer),
                ],
                if (!isAdmin) ...[
                  AppGap.sm,
                  _FieldHelper(l10n.tasksAssigneeSelfOnly),
                ],
              ],
            ),
            if (templates.isNotEmpty) ...[
              AppGap.md,
              _TemplatePicker(
                templates: templates,
                assigneeName: selected?.name,
                onSelected: _saving ? null : _applyTemplate,
              ),
            ],
            AppGap.md,
            _FormSection(
              title: l10n.tasksFormSectionTask,
              icon: AppIcons.task,
              accent: AppAccents.tasks,
              children: [
                AppTextField(
                  controller: _title,
                  label: l10n.tasksFieldTitle,
                  hint: l10n.tasksFieldTitleHint,
                  maxLength: TaskLimits.titleMax,
                  textCapitalization: TextCapitalization.sentences,
                  textInputAction: TextInputAction.next,
                  enabled: !_saving,
                  validator: Validators.compose([
                    Validators.required(l10n),
                    // Only zero-width / format characters count as blank too.
                    (v) => TaskLimits.hasVisibleText(v ?? '')
                        ? null
                        : l10n.validationRequired,
                    Validators.maxLength(l10n, TaskLimits.titleMax),
                  ]),
                ),
                AppGap.md,
                AppTextField(
                  controller: _description,
                  label: l10n.tasksFieldDescription,
                  hint: l10n.tasksFieldDescriptionHint,
                  maxLines: 5,
                  maxLength: TaskLimits.descriptionMax,
                  textCapitalization: TextCapitalization.sentences,
                  enabled: !_saving,
                  validator: Validators.maxLength(
                    l10n,
                    TaskLimits.descriptionMax,
                  ),
                ),
              ],
            ),
            AppGap.md,
            _FormSection(
              title: l10n.tasksInfoDue,
              icon: AppIcons.dueDate,
              accent: AppAccent.blue,
              children: [
                DatePickerField(
                  label: l10n.tasksFieldDueDate,
                  value: _dueDate,
                  firstDate: firstDate,
                  lastDate: DateTime(
                    today.year + TaskLimits.dueDateMaxYearsAhead,
                    today.month,
                    today.day,
                  ),
                  onChanged: (d) => _change(() => _dueDate = d),
                ),
              ],
            ),
            AppGap.md,
            _FormSection(
              title: l10n.tasksFieldCategory,
              icon: AppIcons.category,
              accent: _category.accent,
              children: [
                Wrap(
                  spacing: AppSpacing.sm,
                  runSpacing: AppSpacing.sm,
                  children: [
                    for (final c in TaskCategory.values)
                      TaskChoiceChip(
                        label: c.label(l10n),
                        icon: c.icon,
                        accent: c.accent,
                        selected: c == _category,
                        onSelected: _saving
                            ? null
                            : () => _change(() => _category = c),
                      ),
                  ],
                ),
              ],
            ),
            AppGap.md,
            _FormSection(
              title: l10n.tasksFieldPriority,
              icon: AppIcons.priority,
              accent: _priority.accent,
              children: [
                TaskPrioritySelector(
                  selected: _priority,
                  onSelected: _saving
                      ? null
                      : (p) => _change(() => _priority = p),
                ),
              ],
            ),
            AppGap.xl,
            AppButton(
              label: _isEdit ? l10n.tasksSaveChanges : l10n.tasksCreate,
              icon: _isEdit ? AppIcons.save : AppIcons.add,
              isLoading: _saving,
              onPressed: _submit,
            ),
          ],
        ),
      ),
    );
  }
}

/// One group of fields: a borderless card with a colourful section header.
class _FormSection extends StatelessWidget {
  const _FormSection({
    required this.title,
    required this.icon,
    required this.accent,
    required this.children,
  });

  final String title;
  final IconData icon;
  final AppAccent accent;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionHeader(title: title, icon: icon, accent: accent),
          AppGap.xs,
          ...children,
        ],
      ),
    );
  }
}

/// A state card (not allowed, gone) at the top of the form page.
class _FormMessage extends StatelessWidget {
  const _FormMessage({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: EdgeInsetsDirectional.fromSTEB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
      ),
      children: [child],
    );
  }
}

/// Muted helper text under a form field.
class _FieldHelper extends StatelessWidget {
  const _FieldHelper(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
      child: Text(
        text,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

/// "Quick ideas" for the chosen assignee's age group: soft colourful chips,
/// each in its category's accent. Tapping one fills in the form.
class _TemplatePicker extends StatelessWidget {
  const _TemplatePicker({
    required this.templates,
    required this.assigneeName,
    required this.onSelected,
  });

  final List<TaskTemplate> templates;
  final String? assigneeName;
  final ValueChanged<TaskTemplate>? onSelected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final name = assigneeName;
    final select = onSelected;
    return _FormSection(
      title: name == null
          ? l10n.tasksTemplatesTitle
          : l10n.tasksTemplatesFor(name),
      icon: TaskIcons.template,
      accent: AppAccent.amber,
      children: [
        Wrap(
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (final t in templates)
              Builder(
                builder: (context) {
                  final shades = context.accent(t.category.accent);
                  return ActionChip(
                    avatar: Icon(
                      t.category.icon,
                      size: AppSizes.iconSm,
                      color: shades.foreground,
                    ),
                    label: Text(t.title(l10n)),
                    labelStyle: theme.textTheme.labelLarge?.copyWith(
                      color: shades.onContainer,
                    ),
                    backgroundColor: shades.container,
                    side: BorderSide.none,
                    elevation: 0,
                    pressElevation: 0,
                    tooltip: t.description(l10n),
                    onPressed: select == null ? null : () => select(t),
                  );
                },
              ),
          ],
        ),
      ],
    );
  }
}
