import { created, ok } from '../../lib/response.js';
import * as familyService from './family.service.js';
import * as membersService from './members.service.js';

/** HTTP layer of `/family/*` (docs/03-API_CONTRACT.md §6): read `req.valid`, call the service, send the envelope. */

export async function createFamily(req, res) {
  created(res, await familyService.createFamily(req.user, req.valid.body));
}

export async function joinFamily(req, res) {
  ok(res, await familyService.joinFamily(req.user, req.valid.body));
}

export async function getFamily(req, res) {
  ok(res, await familyService.getFamily(req.user));
}

export async function updateFamily(req, res) {
  ok(res, await familyService.updateFamily(req.user, req.valid.body));
}

export async function regenerateInviteCode(req, res) {
  ok(res, await familyService.regenerateInviteCode(req.user));
}

export async function listMembers(req, res) {
  ok(res, await membersService.listMembers(req.user));
}

export async function addMember(req, res) {
  created(res, await membersService.addMember(req.user, req.valid.body));
}

export async function getMember(req, res) {
  ok(res, await membersService.getMember(req.user, req.valid.params.id));
}

export async function updateMember(req, res) {
  ok(res, await membersService.updateMember(req.user, req.valid.params.id, req.valid.body));
}

export async function removeMember(req, res) {
  ok(res, await membersService.removeMember(req.user, req.valid.params.id));
}
