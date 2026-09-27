import { nameOf } from '../../services/memberDirectory.js';
import { idOf, iso } from '../../services/serializers.js';

/**
 * Contract `Task` shape (docs/03-API_CONTRACT.md §7). Accepts a Mongoose document or a lean /
 * aggregated object. `assigneeName` / `createdByName` come from the family's member map
 * (`services/memberDirectory.js#getMemberMap`) and are `null` when that member no longer exists
 * (done tasks outlive a removed member; the app shows a placeholder).
 *
 * Exported for other modules (e.g. the dashboard's `myTasks`) so every Task leaves the API identically.
 *
 * @param {object} task
 * @param {Map<string, object>} members memberId → member (from getMemberMap)
 */
export function serializeTask(task, members) {
  if (!task) return null;
  return {
    id: idOf(task),
    title: task.title,
    description: task.description ?? null,
    assigneeId: idOf(task.assigneeId),
    assigneeName: nameOf(members, task.assigneeId),
    createdById: idOf(task.createdById),
    createdByName: nameOf(members, task.createdById),
    dueDate: iso(task.dueDate),
    category: task.category,
    priority: task.priority,
    status: task.status,
    completedAt: iso(task.completedAt),
    completedById: idOf(task.completedById),
    createdAt: iso(task.createdAt),
    updatedAt: iso(task.updatedAt),
  };
}

/** Serializes a list with one shared member map. */
export function serializeTasks(list, members) {
  return (list ?? []).map((task) => serializeTask(task, members));
}
