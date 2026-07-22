'use strict';

// Lightweight, dependency-free static check used by CI and `npm run check`.
// Recursively runs `node --check` on every .js file under src/ and renderer/,
// and validates that package.json parses as JSON.

const { execFileSync } = require('child_process');
const fs = require('fs');
const path = require('path');

const ROOT = path.join(__dirname, '..');
const DIRS = ['src', 'renderer', 'scripts'];

function walk(dir) {
  const out = [];
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) out.push(...walk(full));
    else if (entry.name.endsWith('.js')) out.push(full);
  }
  return out;
}

let failed = 0;
const files = DIRS.flatMap((d) => {
  const abs = path.join(ROOT, d);
  return fs.existsSync(abs) ? walk(abs) : [];
});

for (const file of files) {
  const rel = path.relative(ROOT, file);
  try {
    execFileSync(process.execPath, ['--check', file], { stdio: 'pipe' });
    console.log(`ok   ${rel}`);
  } catch (e) {
    failed++;
    console.error(`FAIL ${rel}`);
    console.error(String(e.stderr || e.message));
  }
}

// Validate package.json is well-formed.
try {
  JSON.parse(fs.readFileSync(path.join(ROOT, 'package.json'), 'utf8'));
  console.log('ok   package.json parses');
} catch (e) {
  failed++;
  console.error(`FAIL package.json: ${e.message}`);
}

if (failed > 0) {
  console.error(`\n${failed} check(s) failed.`);
  process.exit(1);
}
console.log(`\nAll ${files.length} file(s) passed.`);
