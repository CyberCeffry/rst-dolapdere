export const reminderOffsets = [10, 5, 0];
const dateFormatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: 'Europe/Istanbul',
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
});
export function dayKey(date) {
    const parts = Object.fromEntries(dateFormatter
        .formatToParts(date)
        .filter((part) => part.type !== 'literal')
        .map((part) => [part.type, part.value]));
    return `${parts.year}-${parts.month}-${parts.day}`;
}
export function daysBetween(from, to) {
    const [fromYear, fromMonth, fromDay] = from.split('-').map(Number);
    const [toYear, toMonth, toDay] = to.split('-').map(Number);
    return Math.round((Date.UTC(toYear, toMonth - 1, toDay) -
        Date.UTC(fromYear, fromMonth - 1, fromDay)) /
        86_400_000);
}
export function reminderOffset(endDate, now) {
    const days = daysBetween(dayKey(now), dayKey(endDate));
    return reminderOffsets.includes(days)
        ? days
        : null;
}
export function isReminderTime(now, reminderTimeMinutes) {
    const time = new Intl.DateTimeFormat('en-GB', {
        timeZone: 'Europe/Istanbul',
        hour: '2-digit',
        minute: '2-digit',
        hourCycle: 'h23',
    }).formatToParts(now);
    const hour = Number(time.find((part) => part.type === 'hour')?.value ?? -1);
    const minute = Number(time.find((part) => part.type === 'minute')?.value ?? -1);
    const currentMinutes = hour * 60 + minute;
    return currentMinutes >= reminderTimeMinutes && currentMinutes < reminderTimeMinutes + 5;
}
export function deliveryId(contractId, endDate, offset, channel) {
    return `${contractId}_${dayKey(endDate)}_${offset}_${channel}`;
}
