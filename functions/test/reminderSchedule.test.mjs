import assert from 'node:assert/strict';
import test from 'node:test';
import { dayKey, daysBetween, deliveryId, isReminderTime, reminderOffset } from '../lib/reminderSchedule.js';

test('Firestore reminder dates use Istanbul calendar days', () => {
  const now = new Date('2026-11-12T06:00:00.000Z');
  const end = new Date('2026-11-22T20:00:00.000Z');
  assert.equal(dayKey(now), '2026-11-12');
  assert.equal(reminderOffset(end, now), 10);
  assert.equal(daysBetween('2026-11-12', '2026-11-17'), 5);
});

test('scheduled function checks the configured five minute window', () => {
  assert.equal(isReminderTime(new Date('2026-11-12T06:00:00.000Z'), 540), true);
  assert.equal(isReminderTime(new Date('2026-11-12T06:05:00.000Z'), 540), false);
});

test('delivery id is stable per contract expiry and channel', () => {
  const end = new Date('2026-11-22T20:00:00.000Z');
  assert.equal(deliveryId('contract-1', end, 10, 'email'), 'contract-1_2026-11-22_10_email');
  assert.notEqual(deliveryId('contract-1', end, 10, 'email'), deliveryId('contract-1', end, 10, 'whatsapp'));
});