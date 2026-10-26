// Tests for Jarvis' planning logic (parser + briefings).
// Runs the exact <script id="jarvis-core"> block shipped in web/index.html.
//   node --test web/tests
process.env.TZ = 'UTC';

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const source = html.match(/<script id="jarvis-core">([\s\S]*?)<\/script>/)[1];
const sandbox = { navigator: { language: 'en-US' }, Intl, Date, Math, Number, String, Object, Array, Set, Map, JSON, RegExp };
vm.createContext(sandbox);
vm.runInContext(source.replace('typeof window !== \'undefined\' ? window : globalThis', 'globalThis'), sandbox);
const { Parser, Briefing, Agenda, sampleWeek, dates } = sandbox.JarvisCore;

// Monday 26 October 2026, 08:30 (weeks start on Sunday, as in the US).
const NOW = new Date(2026, 9, 26, 8, 30);
const SUNDAY = 0;
const parse = (text, now = NOW) => Parser.parse(text, now, SUNDAY);
const interpret = (text, now = NOW) => Parser.interpret(text, now, SUNDAY);
const ymd = (d) => `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
const hm = (d) => `${d.getHours()}:${String(d.getMinutes()).padStart(2, '0')}`;

test('gym tomorrow at 7am for 1h', () => {
  const p = parse('Gym tomorrow at 7am for 1h');
  assert.equal(p.title, 'Gym');
  assert.equal(ymd(p.start), '2026-10-27');
  assert.equal(hm(p.start), '7:00');
  assert.equal(p.duration, 60);
  assert.equal(p.category, 'health');
  assert.equal(p.hasTime, true);
});

test('time range with hashtag category', () => {
  const p = parse('Team meeting friday 10:30-11:15 #work');
  assert.equal(p.title, 'Team meeting');
  assert.equal(ymd(p.start), '2026-10-30');
  assert.equal(hm(p.start), '10:30');
  assert.equal(p.duration, 45);
  assert.equal(p.category, 'work');
});

test('call mom tonight is social at 8 PM today', () => {
  const p = parse('Call mom tonight');
  assert.equal(p.title, 'Call mom');
  assert.equal(ymd(p.start), '2026-10-26');
  assert.equal(hm(p.start), '20:00');
  assert.equal(p.category, 'social');
});

test('next tuesday with trailing ! marks it important', () => {
  const p = parse('Dentist next tuesday 3pm!');
  assert.equal(p.title, 'Dentist');
  assert.equal(ymd(p.start), '2026-11-03');
  assert.equal(hm(p.start), '15:00');
  assert.equal(p.priority, 2);
  assert.equal(p.category, 'health');
});

test('month and day without a time is an anytime plan', () => {
  const p = parse('Pay rent oct 31');
  assert.equal(p.title, 'Pay rent');
  assert.equal(ymd(p.start), '2026-10-31');
  assert.equal(p.hasTime, false);
  assert.equal(p.category, 'errands');
});

test('relative offsets', () => {
  const coffee = parse('Coffee in 30 min');
  assert.equal(coffee.title, 'Coffee');
  assert.equal(hm(coffee.start), '9:00');
  const study = parse('Study physics in 2 days');
  assert.equal(study.title, 'Study physics');
  assert.equal(ymd(study.start), '2026-10-28');
  assert.equal(study.category, 'study');
});

test('ordinal day of month', () => {
  const p = parse('Exam on the 30th');
  assert.equal(p.title, 'Exam');
  assert.equal(ymd(p.start), '2026-10-30');
  const later = parse('Exam on the 2nd');
  assert.equal(ymd(later.start), '2026-11-02');
});

test('ambiguous hours resolve to sensible halves of the day', () => {
  assert.equal(hm(parse('Gym at 6').start), '18:00');
  assert.equal(hm(parse('Breakfast at 9').start), '9:00');
  const lateStandup = parse('Standup at 9', new Date(2026, 9, 26, 10, 0));
  assert.equal(ymd(lateStandup.start), '2026-10-27');
  assert.equal(hm(lateStandup.start), '9:00');
  assert.equal(hm(parse('Dinner at 7 tonight').start), '19:00');
});

test('ranges inherit the meridiem', () => {
  const a = parse('Gym 7 to 8am');
  assert.equal(a.title, 'Gym');
  assert.equal(hm(a.start), '7:00');
  assert.equal(a.duration, 60);
  const b = parse('Meeting from 2 to 4pm');
  assert.equal(b.title, 'Meeting');
  assert.equal(hm(b.start), '14:00');
  assert.equal(b.duration, 120);
  const c = parse('Workshop 3-5pm');
  assert.equal(hm(c.start), '15:00');
  assert.equal(c.duration, 120);
});

test('connector words leave the title clean', () => {
  assert.equal(parse('Lunch with Sarah at noon').title, 'Lunch with Sarah');
  assert.equal(parse('Go to the gym tomorrow').title, 'Go to the gym');
  assert.equal(parse('Yoga in the morning').title, 'Yoga');
  assert.equal(parse('Pick up kids from school at 3').title, 'Pick up kids from school');
  assert.equal(parse('Shopping for shoes').title, 'Shopping for shoes');
});

test('command prefixes are stripped', () => {
  const p = parse('remind me to take out the trash at 8pm');
  assert.equal(p.title, 'Take out the trash');
  assert.equal(hm(p.start), '20:00');
  assert.equal(p.category, 'errands');
  assert.equal(parse('I have a meeting tomorrow').title, 'Meeting');
});

test('bare numbers are not mistaken for times or durations', () => {
  const p = parse('Read 20 pages tonight');
  assert.equal(p.title, 'Read 20 pages');
  assert.equal(hm(p.start), '20:00');
  const walk = parse('Take a 20 min walk');
  assert.equal(walk.title, 'Take a walk');
  assert.equal(walk.duration, 20);
});

test('high priority words and double bang', () => {
  assert.equal(parse('Finish report by Thursday 5pm!!').priority, 2);
  assert.equal(parse('urgent call the bank').priority, 2);
  assert.equal(parse('Water plants').priority, 1);
});

test('object-prototype words are ordinary words', () => {
  const p = parse('constructor toString valueOf');
  assert.equal(p.title, 'Constructor toString valueOf');
  assert.equal(p.category, 'personal');
});

test('questions become briefings, free time and week summaries', () => {
  assert.deepEqual(pick(interpret("What's on tomorrow?")), ['day', '2026-10-27']);
  assert.deepEqual(pick(interpret('Am I free friday afternoon?')), ['free', '2026-10-30']);
  assert.deepEqual(pick(interpret('Brief me on my week')), ['week', '2026-10-26']);
  assert.deepEqual(pick(interpret('What do I have next week?')), ['week', '2026-11-01']);
  assert.equal(interpret('Call me Joel').name, 'Joel');
  assert.equal(interpret('call me back tomorrow').type, 'add');
  assert.equal(interpret('   ').type, 'empty');
});
function pick(intent) { return [intent.type, ymd(intent.day)]; }

test('briefing for a sample day mentions what is next', () => {
  const plans = sampleWeek(NOW);
  const items = Agenda.on(NOW, plans);
  assert.ok(items.length >= 6);
  const text = Briefing.today(items, NOW);
  assert.match(text, /^You have \d+ plans today, 1 already done\./);
  assert.match(text, /Next up is Team stand-up/);
  assert.match(text, /Design review is marked important/);
  const week = dates.weekDays(NOW, SUNDAY).map((day) => ({ day, items: Agenda.on(day, plans) }));
  assert.match(Briefing.week(week, NOW), /this week/);
});

test('free slots never overlap busy plans', () => {
  const items = Agenda.on(NOW, sampleWeek(NOW));
  const slots = Briefing.freeSlots(NOW, items, NOW);
  assert.ok(slots.length > 0);
  for (const s of slots) {
    assert.ok(s.end - s.start >= 30 * 60000);
    for (const i of items.filter((x) => !x.anytime && !x.done)) {
      assert.ok(s.end <= i.start || s.start >= i.end, `slot overlaps ${i.title}`);
    }
  }
});

test('free time can be asked for part of a day', () => {
  const intent = interpret('Am I free tomorrow afternoon?');
  assert.equal(intent.type, 'free');
  assert.equal(intent.period, 14);
  const tomorrow = dates.addDays(dates.startOfDay(NOW), 1);
  const items = Agenda.on(tomorrow, sampleWeek(NOW));
  const answer = Briefing.freeTime(tomorrow, items, NOW, intent.period);
  assert.match(answer, /^Tomorrow afternoon you/);
  for (const slot of Briefing.freeSlots(tomorrow, items, NOW, 12, 17)) {
    assert.ok(slot.start.getHours() >= 12 && slot.end.getHours() <= 17);
  }
  assert.match(Briefing.freeTime(dates.startOfDay(NOW), [], NOW, 20), /^Tonight you're free/);
});

test('compact durations', () => {
  assert.equal(Parser.compactMinutes('1h30'), 90);
  assert.equal(Parser.compactMinutes('1.5hrs'), 90);
  assert.equal(Parser.compactMinutes('45min'), 45);
  assert.equal(Parser.compactMinutes('5pm'), null);
  assert.equal(Parser.compactMinutes('30'), null);
});
