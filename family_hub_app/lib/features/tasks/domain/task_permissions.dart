import 'package:flutter/foundation.dart';

import 'package:family_hub/features/tasks/domain/family_task.dart';
import 'package:family_hub/shared/models/member.dart';

/// Client-side mirror of the contract §7 permission rules. The backend stays
/// the authority (it answers `403 FORBIDDEN`); the UI only hides actions.
///
/// * create: admin → any assignee, member → only themselves
/// * complete / reopen: the assignee or an admin
/// * edit / delete: an admin or the creator
@immutable
class TaskPermissions {
  const TaskPermissions({required this.memberId, required this.isAdmin});

  /// Permissions of [me] (no member → nothing is allowed).
  factory TaskPermissions.of(Member? me) =>
      TaskPermissions(memberId: me?.id, isAdmin: me?.isAdmin ?? false);

  /// The caller's member id (`null` when signed out / without family).
  final String? memberId;
  final bool isAdmin;

  bool get _isMember => memberId != null && memberId!.isNotEmpty;

  /// Whether the caller may create tasks at all.
  bool get canCreate => _isMember;

  /// Whether the caller may assign tasks to other members.
  bool get canAssignOthers => _isMember && isAdmin;

  /// Whether the caller may create / move a task to [assigneeId].
  bool canAssignTo(String assigneeId) =>
      _isMember && (isAdmin || assigneeId == memberId);

  /// Whether the caller may complete or reopen [task].
  bool canComplete(FamilyTask task) =>
      _isMember && (isAdmin || task.assigneeId == memberId);

  /// Whether the caller may edit [task].
  bool canEdit(FamilyTask task) =>
      _isMember && (isAdmin || task.createdById == memberId);

  /// Whether the caller may delete [task] (same rule as [canEdit]).
  bool canDelete(FamilyTask task) => canEdit(task);

  @override
  bool operator ==(Object other) =>
      other is TaskPermissions &&
      other.memberId == memberId &&
      other.isAdmin == isAdmin;

  @override
  int get hashCode => Object.hash(memberId, isAdmin);
}
