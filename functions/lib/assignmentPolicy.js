export function canAssignResponsible(actorRole, actorUid, targetUid, currentResponsibleUid) {
    if (actorRole === 'admin' || actorRole === 'manager')
        return true;
    return actorRole === 'supervisor' &&
        actorUid === targetUid &&
        (!currentResponsibleUid || currentResponsibleUid === actorUid);
}
