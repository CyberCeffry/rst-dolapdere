export type AssignmentRole = 'admin' | 'manager' | 'supervisor';

export function canAssignResponsible(
  actorRole: AssignmentRole,
  actorUid: string,
  targetUid: string,
  currentResponsibleUid?: string,
): boolean {
  if (actorRole === 'admin' || actorRole === 'manager') return true;
  return actorRole === 'supervisor' &&
    actorUid === targetUid &&
    (!currentResponsibleUid || currentResponsibleUid === actorUid);
}
