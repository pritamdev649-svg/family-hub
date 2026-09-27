import mongoose from 'mongoose';
import { LIMITS, TASK_CATEGORIES, TASK_PRIORITIES, TASK_STATUSES } from './enums.js';
import { applyToJson, defineModel, optionalRef, optionalString, requiredRef, requiredString, schemaOptions } from './schemaUtils.js';

/**
 * Family task board (contract §7). All `*Id` people references are **Member** ids.
 * `assigneeName` / `createdByName` are resolved at read time (memberDirectory).
 */
const taskSchema = new mongoose.Schema(
  {
    familyId: requiredRef('Family'),
    title: requiredString(LIMITS.TASK_TITLE_MAX),
    description: optionalString(LIMITS.TASK_DESCRIPTION_MAX),
    assigneeId: requiredRef('Member'),
    createdById: requiredRef('Member'),
    dueDate: { type: Date, default: null },
    category: { type: String, required: true, enum: TASK_CATEGORIES, default: 'other' },
    priority: { type: String, required: true, enum: TASK_PRIORITIES, default: 'medium' },
    status: { type: String, required: true, enum: TASK_STATUSES, default: 'pending' },
    completedAt: { type: Date, default: null },
    completedById: optionalRef('Member'),
  },
  schemaOptions('tasks'),
);

// Pending lists sorted by due date; overdue / today / week filters.
taskSchema.index({ familyId: 1, status: 1, dueDate: 1 });
// Per-assignee lists and dashboard counters.
taskSchema.index({ familyId: 1, assigneeId: 1, status: 1 });

/** Overdue = pending with a due date before `now` (callers pass the family-timezone start of today). */
taskSchema.methods.isOverdue = function isOverdue(now = new Date()) {
  return this.status === 'pending' && Boolean(this.dueDate) && this.dueDate.getTime() < now.getTime();
};

applyToJson(taskSchema);

export const Task = defineModel('Task', taskSchema);
export default Task;
