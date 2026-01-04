#!/usr/bin/env node
/**
 * issue-worker.js - Isolated agent that processes GitHub issues
 * 
 * This worker:
 * 1. Clones the repository into its isolated workspace
 * 2. Polls GitHub for issues with a specific label
 * 3. Claims an issue by adding "in-progress" label
 * 4. Creates a working branch
 * 5. Runs Claude to work on the issue
 * 6. Creates a PR and marks issue as done
 * 7. Repeats for next issue
 * 
 * Environment:
 *   GITHUB_REPO         - Repository to clone (owner/repo)
 *   GITHUB_BRANCH       - Base branch (default: main)
 *   ISSUE_LABEL         - Label to filter issues (default: agent-ready)
 *   POLL_INTERVAL       - Seconds between polls (default: 60)
 */

const { execSync, spawn } = require('child_process');
const fs = require('fs');
const path = require('path');
const https = require('https');
const crypto = require('crypto');

// Configuration
const GITHUB_REPO = process.env.GITHUB_REPO;
const GITHUB_BRANCH = process.env.GITHUB_BRANCH || 'main';
const ISSUE_LABEL = process.env.ISSUE_LABEL || 'agent-ready';
const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || '60', 10) * 1000;
const PROJECT_DIR = '/project';

// Worker identity
const WORKER_ID = process.env.HOSTNAME || crypto.randomBytes(4).toString('hex');

// GitHub App auth
const GITHUB_APP_ID = process.env.GITHUB_APP_ID;
const GITHUB_APP_INSTALLATION_ID = process.env.GITHUB_APP_INSTALLATION_ID;
let GITHUB_APP_PRIVATE_KEY = process.env.GITHUB_APP_PRIVATE_KEY;
const GITHUB_APP_PRIVATE_KEY_PATH = process.env.GITHUB_APP_PRIVATE_KEY_PATH;

// State
let currentIssue = null;
let issuesProcessed = 0;
let githubToken = null;
let tokenExpiry = 0;

// Claim verification delay (ms) - wait for other workers to potentially claim
const CLAIM_VERIFICATION_DELAY = 3000;

/**
 * Log with worker prefix
 */
function log(message) {
    const timestamp = new Date().toISOString().replace('T', ' ').substring(0, 19);
    console.log(`[${timestamp}] [${WORKER_ID}] ${message}`);
}

/**
 * Sleep for specified milliseconds
 */
function sleep(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
}

/**
 * Load GitHub App private key
 */
function loadPrivateKey() {
    if (GITHUB_APP_PRIVATE_KEY) {
        // Base64 encoded
        return Buffer.from(GITHUB_APP_PRIVATE_KEY, 'base64').toString('utf-8');
    }
    if (GITHUB_APP_PRIVATE_KEY_PATH) {
        return fs.readFileSync(GITHUB_APP_PRIVATE_KEY_PATH, 'utf-8');
    }
    throw new Error('No GitHub App private key configured');
}

/**
 * Create JWT for GitHub App
 */
function createJWT(privateKey) {
    const now = Math.floor(Date.now() / 1000);
    const payload = {
        iat: now - 60,
        exp: now + 600,
        iss: GITHUB_APP_ID
    };
    
    // Simple JWT creation (header.payload.signature)
    const header = Buffer.from(JSON.stringify({ alg: 'RS256', typ: 'JWT' })).toString('base64url');
    const body = Buffer.from(JSON.stringify(payload)).toString('base64url');
    const signInput = `${header}.${body}`;
    
    const sign = crypto.createSign('RSA-SHA256');
    sign.update(signInput);
    const signature = sign.sign(privateKey, 'base64url');
    
    return `${signInput}.${signature}`;
}

/**
 * Make HTTPS request
 */
function request(options, body = null) {
    return new Promise((resolve, reject) => {
        const req = https.request(options, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => {
                try {
                    resolve({ status: res.statusCode, data: JSON.parse(data) });
                } catch {
                    resolve({ status: res.statusCode, data });
                }
            });
        });
        req.on('error', reject);
        if (body) req.write(JSON.stringify(body));
        req.end();
    });
}

/**
 * Get installation access token
 */
async function getInstallationToken() {
    if (githubToken && Date.now() < tokenExpiry) {
        return githubToken;
    }
    
    const privateKey = loadPrivateKey();
    const jwt = createJWT(privateKey);
    
    const response = await request({
        hostname: 'api.github.com',
        path: `/app/installations/${GITHUB_APP_INSTALLATION_ID}/access_tokens`,
        method: 'POST',
        headers: {
            'Authorization': `Bearer ${jwt}`,
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'claude-godot-agent',
            'X-GitHub-Api-Version': '2022-11-28'
        }
    });
    
    if (response.status !== 201) {
        throw new Error(`Failed to get installation token: ${JSON.stringify(response.data)}`);
    }
    
    githubToken = response.data.token;
    tokenExpiry = new Date(response.data.expires_at).getTime() - 60000; // 1 min buffer
    
    return githubToken;
}

/**
 * GitHub API call
 */
async function github(method, endpoint, body = null) {
    const token = await getInstallationToken();
    
    return request({
        hostname: 'api.github.com',
        path: endpoint,
        method,
        headers: {
            'Authorization': `Bearer ${token}`,
            'Accept': 'application/vnd.github+json',
            'User-Agent': 'claude-godot-agent',
            'X-GitHub-Api-Version': '2022-11-28',
            'Content-Type': 'application/json'
        }
    }, body);
}

/**
 * Clone repository if not already cloned
 */
async function ensureRepoCloned() {
    const gitDir = path.join(PROJECT_DIR, '.git');
    
    if (fs.existsSync(gitDir)) {
        log('Repository already cloned, pulling latest...');
        try {
            execSync(`git fetch origin && git checkout ${GITHUB_BRANCH} && git pull origin ${GITHUB_BRANCH}`, {
                cwd: PROJECT_DIR,
                stdio: 'inherit'
            });
        } catch (err) {
            log(`Warning: git pull failed: ${err.message}`);
        }
        return;
    }
    
    log(`Cloning repository: ${GITHUB_REPO}`);
    
    const token = await getInstallationToken();
    const cloneUrl = `https://x-access-token:${token}@github.com/${GITHUB_REPO}.git`;
    
    execSync(`git clone --branch ${GITHUB_BRANCH} ${cloneUrl} .`, {
        cwd: PROJECT_DIR,
        stdio: 'inherit'
    });
    
    // Configure git
    execSync('git config user.name "Godot Agent"', { cwd: PROJECT_DIR });
    execSync('git config user.email "2587725+godot-agent[bot]@users.noreply.github.com"', { cwd: PROJECT_DIR });
    
    log('Repository cloned successfully');
}

/**
 * Find an available issue to work on
 */
async function findAvailableIssue() {
    const [owner, repo] = GITHUB_REPO.split('/');
    
    // Get issues with our label, excluding ones already in progress
    const response = await github('GET', 
        `/repos/${owner}/${repo}/issues?labels=${ISSUE_LABEL}&state=open&sort=created&direction=asc`
    );
    
    if (response.status !== 200) {
        log(`Failed to fetch issues: ${JSON.stringify(response.data)}`);
        return null;
    }
    
    // Find first issue not labeled "in-progress"
    for (const issue of response.data) {
        const hasInProgress = issue.labels.some(l => l.name === 'in-progress');
        if (!hasInProgress && !issue.pull_request) {
            return issue;
        }
    }
    
    return null;
}

/**
 * Claim an issue using atomic comment verification
 * 
 * This prevents race conditions where multiple workers claim the same issue.
 * Uses a two-phase approach:
 * 1. Check if already claimed (in-progress label exists)
 * 2. Post claim comment, wait, verify we were first
 * 3. Add in-progress label BEFORE updating comment (so other workers see it)
 */
async function claimIssue(issue) {
    const [owner, repo] = GITHUB_REPO.split('/');
    const claimId = `CLAIM:${WORKER_ID}:${Date.now()}`;
    
    log(`Attempting to claim issue #${issue.number}...`);
    
    // Step 0: Double-check issue doesn't already have in-progress label
    // (might have been claimed between findAvailableIssue and now)
    const issueResponse = await github('GET',
        `/repos/${owner}/${repo}/issues/${issue.number}`
    );
    if (issueResponse.status === 200) {
        const hasInProgress = issueResponse.data.labels?.some(l => l.name === 'in-progress');
        if (hasInProgress) {
            log(`Issue #${issue.number} already has in-progress label, skipping...`);
            return false;
        }
    }
    
    // Step 1: Post claim comment atomically
    const claimResponse = await github('POST',
        `/repos/${owner}/${repo}/issues/${issue.number}/comments`,
        { body: claimId }
    );
    
    if (claimResponse.status !== 201) {
        log(`Failed to post claim comment: ${JSON.stringify(claimResponse.data)}`);
        return false;
    }
    
    const ourCommentId = claimResponse.data.id;
    log(`Posted claim comment (id: ${ourCommentId}), waiting for other claims...`);
    
    // Step 2: Wait for other workers to potentially post their claims
    await sleep(CLAIM_VERIFICATION_DELAY);
    
    // Step 3: Re-check for in-progress label (another worker might have won and added it)
    const recheckResponse = await github('GET',
        `/repos/${owner}/${repo}/issues/${issue.number}`
    );
    if (recheckResponse.status === 200) {
        const hasInProgress = recheckResponse.data.labels?.some(l => l.name === 'in-progress');
        if (hasInProgress) {
            log(`Issue #${issue.number} was claimed by another worker (in-progress label found)`);
            // Clean up our claim comment
            await github('DELETE',
                `/repos/${owner}/${repo}/issues/comments/${ourCommentId}`
            );
            return false;
        }
    }
    
    // Step 4: Fetch all comments and find CLAIM comments
    const commentsResponse = await github('GET',
        `/repos/${owner}/${repo}/issues/${issue.number}/comments?per_page=100`
    );
    
    if (commentsResponse.status !== 200) {
        log(`Failed to fetch comments: ${JSON.stringify(commentsResponse.data)}`);
        return false;
    }
    
    // Filter for CLAIM comments and sort by creation time (server timestamp)
    const claims = commentsResponse.data
        .filter(c => c.body && c.body.startsWith('CLAIM:'))
        .sort((a, b) => new Date(a.created_at) - new Date(b.created_at));
    
    // Step 5: Check if our claim was first
    if (claims.length === 0 || claims[0].id !== ourCommentId) {
        // We lost the race - another worker claimed first
        const winner = claims.length > 0 ? claims[0].body.split(':')[1] : 'unknown';
        log(`Lost claim race to worker ${winner}, skipping issue #${issue.number}`);
        
        // Clean up our claim comment
        await github('DELETE',
            `/repos/${owner}/${repo}/issues/comments/${ourCommentId}`
        );
        
        return false;
    }
    
    // Step 6: We won! Add in-progress label FIRST (before updating comment)
    // This is critical - other workers check for this label
    log(`Won claim for issue #${issue.number}!`);
    
    const labelResponse = await github('POST',
        `/repos/${owner}/${repo}/issues/${issue.number}/labels`,
        { labels: ['in-progress'] }
    );
    
    if (labelResponse.status !== 200) {
        log(`Warning: Failed to add in-progress label: ${JSON.stringify(labelResponse.data)}`);
        // Continue anyway since we have the claim
    }
    
    // Step 7: NOW update our claim comment to a nicer message
    // (only after in-progress label is set)
    await github('PATCH',
        `/repos/${owner}/${repo}/issues/comments/${ourCommentId}`,
        { body: `🤖 Agent \`${WORKER_ID}\` claimed and is now working on this issue.` }
    );
    
    return true;
}

/**
 * Create a working branch for the issue
 */
async function createWorkingBranch(issue) {
    const branchName = `claude/issue-${issue.number}-${Date.now()}`;
    
    // Ensure we're on the base branch and up to date
    execSync(`git checkout ${GITHUB_BRANCH} && git pull origin ${GITHUB_BRANCH}`, {
        cwd: PROJECT_DIR,
        stdio: 'inherit'
    });
    
    // Create and checkout new branch
    execSync(`git checkout -b ${branchName}`, {
        cwd: PROJECT_DIR,
        stdio: 'inherit'
    });
    
    return branchName;
}

/**
 * Run Claude on the issue
 */
async function runClaude(issue) {
    const prompt = `You are working on GitHub issue #${issue.number}: "${issue.title}"

Issue description:
${issue.body || 'No description provided.'}

Instructions:
1. Analyze the issue and understand what needs to be done
2. Make the necessary code changes to address this issue
3. Test your changes if possible (run Godot validation)
4. Commit your changes with a clear commit message referencing the issue

When you're done, summarize what you changed.`;

    log(`Running Claude on issue #${issue.number}...`);
    
    return new Promise((resolve) => {
        const claude = spawn('claude', ['--print', '--dangerously-skip-permissions', prompt], {
            cwd: PROJECT_DIR,
            stdio: ['ignore', 'pipe', 'pipe'],
            env: { ...process.env, TERM: 'dumb' }
        });
        
        let output = '';
        
        claude.stdout.on('data', (data) => {
            const text = data.toString();
            process.stdout.write(text);
            output += text;
        });
        
        claude.stderr.on('data', (data) => {
            process.stderr.write(data.toString());
        });
        
        claude.on('close', (code) => {
            resolve({ success: code === 0, output });
        });
        
        claude.on('error', (err) => {
            log(`Failed to run Claude: ${err.message}`);
            resolve({ success: false, output: err.message });
        });
    });
}

/**
 * Push branch and create PR
 */
async function createPullRequest(issue, branchName, claudeOutput) {
    const [owner, repo] = GITHUB_REPO.split('/');
    const token = await getInstallationToken();
    
    // Push the branch
    log('Pushing branch...');
    execSync(`git push https://x-access-token:${token}@github.com/${GITHUB_REPO}.git ${branchName}`, {
        cwd: PROJECT_DIR,
        stdio: 'inherit'
    });
    
    // Create PR
    log('Creating pull request...');
    const prBody = `## Fixes #${issue.number}

### Changes Made
${claudeOutput.substring(0, 3000)}

---
🤖 *This PR was automatically created by Claude Agent \`${WORKER_ID}\`*`;

    const prResponse = await github('POST',
        `/repos/${owner}/${repo}/pulls`,
        {
            title: `Fix: ${issue.title}`,
            body: prBody,
            head: branchName,
            base: GITHUB_BRANCH
        }
    );
    
    if (prResponse.status !== 201) {
        log(`Failed to create PR: ${JSON.stringify(prResponse.data)}`);
        return null;
    }
    
    return prResponse.data;
}

/**
 * Complete issue processing
 */
async function completeIssue(issue, pr, success) {
    const [owner, repo] = GITHUB_REPO.split('/');
    
    // Remove in-progress, add agent-complete or agent-failed
    const newLabel = success ? 'agent-complete' : 'agent-failed';
    
    // Remove in-progress label
    await github('DELETE',
        `/repos/${owner}/${repo}/issues/${issue.number}/labels/in-progress`
    );
    
    // Remove the trigger label
    await github('DELETE',
        `/repos/${owner}/${repo}/issues/${issue.number}/labels/${ISSUE_LABEL}`
    );
    
    // Add completion label
    await github('POST',
        `/repos/${owner}/${repo}/issues/${issue.number}/labels`,
        { labels: [newLabel] }
    );
    
    // Add completion comment
    const message = success && pr
        ? `✅ Agent completed work on this issue.\n\nPull request: #${pr.number}`
        : `❌ Agent encountered an error while working on this issue.`;
    
    await github('POST',
        `/repos/${owner}/${repo}/issues/${issue.number}/comments`,
        { body: message }
    );
}

/**
 * Process a single issue
 */
async function processIssue(issue) {
    currentIssue = issue;
    log(`\n${'═'.repeat(70)}`);
    log(`📋 Processing issue #${issue.number}: ${issue.title}`);
    log(`${'═'.repeat(70)}`);
    
    try {
        // Claim the issue
        const claimed = await claimIssue(issue);
        if (!claimed) {
            log('Failed to claim issue, skipping...');
            currentIssue = null;
            return false;
        }
        
        // Create working branch
        const branchName = await createWorkingBranch(issue);
        log(`Created branch: ${branchName}`);
        
        // Run Claude
        const result = await runClaude(issue);
        
        // Check if any commits were made
        let hasChanges = false;
        try {
            const status = execSync('git status --porcelain', { cwd: PROJECT_DIR }).toString();
            hasChanges = status.trim().length > 0;
            
            if (hasChanges) {
                // Commit any uncommitted changes
                execSync('git add -A', { cwd: PROJECT_DIR });
                execSync(`git commit -m "Address issue #${issue.number}" --allow-empty`, { cwd: PROJECT_DIR });
            }
            
            // Check if we have commits beyond the base branch
            const commits = execSync(`git log ${GITHUB_BRANCH}..HEAD --oneline`, { cwd: PROJECT_DIR }).toString();
            hasChanges = commits.trim().length > 0;
        } catch {
            hasChanges = false;
        }
        
        let pr = null;
        if (hasChanges && result.success) {
            pr = await createPullRequest(issue, branchName, result.output);
            if (pr) {
                log(`✅ Created PR #${pr.number}`);
            }
        }
        
        // Complete the issue
        await completeIssue(issue, pr, result.success && (pr || !hasChanges));
        
        issuesProcessed++;
        log(`✅ Completed issue #${issue.number}`);
        
        // Return to base branch for next issue
        execSync(`git checkout ${GITHUB_BRANCH}`, { cwd: PROJECT_DIR, stdio: 'inherit' });
        
        currentIssue = null;
        return true;
        
    } catch (err) {
        log(`❌ Error processing issue #${issue.number}: ${err.message}`);
        
        try {
            await completeIssue(issue, null, false);
            execSync(`git checkout ${GITHUB_BRANCH}`, { cwd: PROJECT_DIR, stdio: 'pipe' });
        } catch {}
        
        currentIssue = null;
        return false;
    }
}

/**
 * Main polling loop
 */
async function pollForIssues() {
    const issue = await findAvailableIssue();
    
    if (issue) {
        await processIssue(issue);
        // Add small random jitter before next poll to reduce collisions
        const jitter = Math.random() * 5000;
        await sleep(jitter);
        setImmediate(pollForIssues);
    } else {
        // No issues, wait and poll again with jitter
        const jitter = Math.random() * 10000;
        setTimeout(pollForIssues, POLL_INTERVAL + jitter);
    }
}

/**
 * Display startup banner
 */
function showBanner() {
    console.log('');
    console.log('╔══════════════════════════════════════════════════════════════════════╗');
    console.log('║                   Claude Issue Worker (Isolated)                     ║');
    console.log('╠══════════════════════════════════════════════════════════════════════╣');
    console.log(`║  Worker ID:   ${WORKER_ID.padEnd(52)} ║`);
    console.log(`║  Repository:  ${(GITHUB_REPO || 'NOT SET').padEnd(52)} ║`);
    console.log(`║  Branch:      ${GITHUB_BRANCH.padEnd(52)} ║`);
    console.log(`║  Issue Label: ${ISSUE_LABEL.padEnd(52)} ║`);
    console.log(`║  Poll:        ${(POLL_INTERVAL/1000 + 's').padEnd(52)} ║`);
    console.log('╠══════════════════════════════════════════════════════════════════════╣');
    console.log('║  Polls for issues labeled with ISSUE_LABEL, claims and processes.    ║');
    console.log('║  Creates PRs for completed work. Runs in complete isolation.         ║');
    console.log('╚══════════════════════════════════════════════════════════════════════╝');
    console.log('');
}

/**
 * Handle graceful shutdown
 */
function setupShutdown() {
    const shutdown = (signal) => {
        log('');
        log(`📊 Worker Statistics`);
        log(`   Issues processed: ${issuesProcessed}`);
        log(`   Current issue: ${currentIssue ? `#${currentIssue.number}` : 'none'}`);
        log(`\n👋 Received ${signal}, shutting down...`);
        process.exit(0);
    };
    
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
}

/**
 * Validate configuration
 */
function validateConfig() {
    const errors = [];
    
    if (!GITHUB_REPO) errors.push('GITHUB_REPO is required');
    if (!GITHUB_APP_ID) errors.push('GITHUB_APP_ID is required');
    if (!GITHUB_APP_INSTALLATION_ID) errors.push('GITHUB_APP_INSTALLATION_ID is required');
    if (!GITHUB_APP_PRIVATE_KEY && !GITHUB_APP_PRIVATE_KEY_PATH) {
        errors.push('GITHUB_APP_PRIVATE_KEY or GITHUB_APP_PRIVATE_KEY_PATH is required');
    }
    
    if (errors.length > 0) {
        console.error('Configuration errors:');
        errors.forEach(e => console.error(`  - ${e}`));
        process.exit(1);
    }
}

/**
 * Main entry point
 */
async function main() {
    showBanner();
    validateConfig();
    setupShutdown();
    
    // Clone/update repository
    await ensureRepoCloned();
    
    // Add startup jitter to stagger workers (0-15 seconds)
    const startupJitter = Math.random() * 15000;
    log(`⏳ Starting issue polling in ${(startupJitter/1000).toFixed(1)}s (stagger delay)`);
    log(`   Poll interval: ${POLL_INTERVAL/1000}s`);
    log(`   Looking for issues with label: "${ISSUE_LABEL}"`);
    
    await sleep(startupJitter);
    
    // Start polling
    pollForIssues();
}

// Run
main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});

