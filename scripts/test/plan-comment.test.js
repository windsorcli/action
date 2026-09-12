#!/usr/bin/env node
// Exercises plan-comment/action.yaml's github-script step against mocked
// core/github/context objects, without hitting the real GitHub API. Run via:
//
//   node scripts/test/plan-comment.test.js <path-to-wrapped-script.js>
//
// <path-to-wrapped-script.js> is the step's `script:` text extracted from the
// action.yaml and wrapped as `async function main(core, github, context) {
// ...script... }` — see the "Test plan-comment JS logic" step in ci.yaml for
// how that extraction happens. This file only holds the test scenarios so
// they're not re-derived by hand every time the script changes.

const fs = require('fs');
const path = require('path');

const wrappedPath = process.argv[2];
if (!wrappedPath) {
  console.error('usage: node plan-comment.test.js <path-to-wrapped-script.js>');
  process.exit(1);
}
const main = require(path.resolve(wrappedPath));

const PLAN_FILE = '/tmp/plan-comment-test-input.txt';

function mock({ existingComments, planText, planStatus, contextName, prNumber }) {
  fs.writeFileSync(PLAN_FILE, planText);
  process.env.PLAN_FILE = PLAN_FILE;
  process.env.PLAN_STATUS = planStatus;
  process.env.WINDSOR_CONTEXT = contextName;
  process.env.PR_NUMBER = String(prNumber);

  const state = { created: null, updated: null, outputs: {}, warnings: [] };
  const core = {
    setOutput: (k, v) => { state.outputs[k] = v; },
    setFailed: (msg) => { state.outputs.__failed = msg; },
    warning: (msg) => state.warnings.push(msg),
  };
  const github = {
    paginate: async () => existingComments,
    rest: {
      issues: {
        listComments: () => {},
        createComment: async (params) => {
          state.created = params;
          return { data: { id: 999, html_url: 'https://example/999' } };
        },
        updateComment: async (params) => {
          state.updated = params;
          return { data: { id: params.comment_id, html_url: `https://example/${params.comment_id}` } };
        },
      },
    },
  };
  const context = { repo: { owner: 'o', repo: 'r' } };
  return { core, github, context, state };
}

function assert(cond, msg) {
  if (!cond) throw new Error(msg);
}

async function run() {
  // A fresh PR with no prior comment creates one, carrying the context-scoped marker.
  {
    const m = mock({ existingComments: [], planText: 'plan output here', planStatus: 'ok', contextName: 'staging', prNumber: 42 });
    await main(m.core, m.github, m.context);
    assert(m.state.created, 'expected a new comment to be created');
    assert(!m.state.updated, 'should not update when nothing exists yet');
    assert(m.state.created.body.includes('<!-- windsorcli/action:plan-comment:staging -->'), 'marker missing from new comment body');
    assert(m.state.outputs['comment-id'] === '999', 'comment-id output not wired to the API response');
  }

  // A matching marker on an existing comment updates it in place, ignoring an unrelated one.
  {
    const marker = '<!-- windsorcli/action:plan-comment:staging -->';
    const existing = [
      { id: 1, body: 'unrelated comment' },
      { id: 2, body: marker + '\nold plan body' },
    ];
    const m = mock({ existingComments: existing, planText: 'new plan output', planStatus: 'ok', contextName: 'staging', prNumber: 42 });
    await main(m.core, m.github, m.context);
    assert(m.state.updated && m.state.updated.comment_id === 2, 'expected the sticky update to target comment id 2');
    assert(!m.state.created, 'should not create a second comment when one already matches');
  }

  // A different context's marker doesn't match — a separate comment is created rather than
  // clobbering another context's plan (this is how one PR can carry a comment per context).
  {
    const marker = '<!-- windsorcli/action:plan-comment:staging -->';
    const existing = [{ id: 2, body: marker + '\nold plan body' }];
    const m = mock({ existingComments: existing, planText: 'prod plan', planStatus: 'ok', contextName: 'prod', prNumber: 42 });
    await main(m.core, m.github, m.context);
    assert(m.state.created, 'expected a separate comment for a different context');
  }

  // No PR number (not a pull_request event, and no override) fails closed without posting.
  {
    const m = mock({ existingComments: [], planText: 'x', planStatus: 'ok', contextName: 'staging', prNumber: 0 });
    await main(m.core, m.github, m.context);
    assert(m.state.outputs.__failed, 'expected setFailed when no PR number is available');
    assert(!m.state.created && !m.state.updated, 'should not post a comment without a PR number');
  }

  // Oversized plan output is truncated to stay under GitHub's 65536-character comment cap.
  {
    const big = 'x'.repeat(70000);
    const m = mock({ existingComments: [], planText: big, planStatus: 'ok', contextName: 'staging', prNumber: 42 });
    await main(m.core, m.github, m.context);
    assert(m.state.created.body.length <= 65536, `comment body (${m.state.created.body.length} chars) exceeds GitHub's cap`);
    assert(m.state.warnings.length === 1, 'expected a truncation warning');
  }

  console.log('plan-comment.test.js: all scenarios passed');
}

run().catch((e) => {
  console.error('plan-comment.test.js FAILED:', e.message);
  process.exit(1);
});
