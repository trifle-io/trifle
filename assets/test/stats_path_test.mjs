import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import test from 'node:test';
import {joinPath, parsePath, pathHasWildcard, renderPath, pathTextSegments, siblingSegments} from '../js/utils/stats_path.mjs';

const fixtures = JSON.parse(readFileSync(new URL('./fixtures/stats-paths-v1.json', import.meta.url)));

test('autocomplete groups literal dots and stars without changing editable text', () => {
  const paths = [String.raw`jobs.test\.rb.count`, 'jobs.test.rb.count', String.raw`jobs.\*.count`];
  assert.deepEqual(siblingSegments(paths, ['jobs']).sort(), ['*', 'test', 'test.rb']);
  assert.deepEqual(siblingSegments(paths, ['jobs', 'test.rb']), ['count']);
  assert.deepEqual(pathTextSegments(String.raw`jobs.test\.rb.\*`), ['jobs', String.raw`test\.rb`, String.raw`\*`]);
  for (const fixture of fixtures.path_cases) {
    assert.equal(pathTextSegments(fixture.input).join('.'), fixture.input);
  }
});

for (const fixture of fixtures.path_cases) {
  test(`path contract: ${fixture.name}`, () => {
    const parsed = parsePath(fixture.input);
    assert.deepEqual(parsed, fixture.segments);
    assert.equal(renderPath(parsed), fixture.rendered);
    assert.deepEqual(parsePath(fixture.input, 'legacy').map(part => part.value), fixture.legacy);
    assert.equal(pathHasWildcard(fixture.input), fixture.segments.some(part => part.unescaped_star));
    const names = parsed.map(part => part.value);
    assert.deepEqual(parsePath(joinPath(names)).map(part => part.value), names);
  });
}

test('a concrete star collected during expansion cannot become a wildcard', () => {
  const path = joinPath(['jobs', '*', 'count']);
  assert.equal(path, 'jobs.\\*.count');
  assert.equal(pathHasWildcard(path), false);
});
