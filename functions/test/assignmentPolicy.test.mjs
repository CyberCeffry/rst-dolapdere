import assert from 'node:assert/strict';
import test from 'node:test';
import { canAssignResponsible } from '../lib/assignmentPolicy.js';

test('admin and manager can assign any active role, including themselves', () => {
  assert.equal(canAssignResponsible('admin', 'admin-1', 'supervisor-1'), true);
  assert.equal(canAssignResponsible('manager', 'manager-1', 'manager-1'), true);
  assert.equal(canAssignResponsible('manager', 'manager-1', 'admin-1'), true);
});

test('supervisor can assign only themselves to an unassigned contract', () => {
  assert.equal(canAssignResponsible('supervisor', 's1', 's1'), true);
  assert.equal(canAssignResponsible('supervisor', 's1', 's1', 's1'), true);
  assert.equal(canAssignResponsible('supervisor', 's1', 's2'), false);
  assert.equal(canAssignResponsible('supervisor', 's1', 's1', 's2'), false);
});
