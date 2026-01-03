#!/usr/bin/env node
/**
 * queue-watcher.js - Async task queue processor for Claude
 * 
 * Monitors /project/.claude/queue/ for task files and processes them
 * sequentially using Claude Code CLI.
 * 
 * Directory Structure:
 *   /project/.claude/
 *   ├── queue/           # Drop task files here (*.md or *.txt)
 *   ├── processing/      # Currently being processed
 *   ├── completed/       # Successfully completed tasks
 *   ├── failed/          # Failed tasks
 *   └── results/         # Execution logs
 * 
 * Task files are processed in alphabetical order.
 * Use numeric prefixes for ordering: 001-task.md, 002-task.md
 * 
 * Usage:
 *   node queue-watcher.js              # Run with defaults
 *   POLL_INTERVAL=10000 node queue-watcher.js  # Poll every 10s
 */

const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');

// Configuration
const PROJECT_DIR = process.env.PROJECT_DIR || '/project';
const CLAUDE_DIR = path.join(PROJECT_DIR, '.claude');
const QUEUE_DIR = path.join(CLAUDE_DIR, 'queue');
const PROCESSING_DIR = path.join(CLAUDE_DIR, 'processing');
const COMPLETED_DIR = path.join(CLAUDE_DIR, 'completed');
const FAILED_DIR = path.join(CLAUDE_DIR, 'failed');
const RESULTS_DIR = path.join(CLAUDE_DIR, 'results');

const POLL_INTERVAL = parseInt(process.env.POLL_INTERVAL || '5000', 10);
const TASK_EXTENSIONS = ['.md', '.txt'];

// State
let isProcessing = false;
let tasksProcessed = 0;
let tasksFailed = 0;

/**
 * Ensure all required directories exist
 */
function ensureDirectories() {
    const dirs = [CLAUDE_DIR, QUEUE_DIR, PROCESSING_DIR, COMPLETED_DIR, FAILED_DIR, RESULTS_DIR];
    dirs.forEach(dir => {
        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
            console.log(`Created directory: ${dir}`);
        }
    });
}

/**
 * Get list of pending task files sorted alphabetically
 */
function getPendingTasks() {
    try {
        const files = fs.readdirSync(QUEUE_DIR);
        return files
            .filter(f => TASK_EXTENSIONS.some(ext => f.endsWith(ext)))
            .sort();
    } catch (err) {
        if (err.code !== 'ENOENT') {
            console.error('Error reading queue directory:', err.message);
        }
        return [];
    }
}

/**
 * Format timestamp for logs
 */
function timestamp() {
    return new Date().toISOString();
}

/**
 * Process a single task file
 */
async function processTask(filename) {
    const taskPath = path.join(QUEUE_DIR, filename);
    const processingPath = path.join(PROCESSING_DIR, filename);
    const baseName = filename.replace(/\.(md|txt)$/, '');
    const resultPath = path.join(RESULTS_DIR, `${baseName}.log`);
    
    console.log('');
    console.log('═'.repeat(70));
    console.log(`📋 Processing: ${filename}`);
    console.log(`   Started: ${timestamp()}`);
    console.log('═'.repeat(70));
    
    // Move to processing directory
    try {
        fs.renameSync(taskPath, processingPath);
    } catch (err) {
        console.error(`Failed to move task to processing: ${err.message}`);
        return false;
    }
    
    // Read task content
    let content;
    try {
        content = fs.readFileSync(processingPath, 'utf-8').trim();
    } catch (err) {
        console.error(`Failed to read task file: ${err.message}`);
        fs.renameSync(processingPath, path.join(FAILED_DIR, filename));
        return false;
    }
    
    // Open result file for streaming output
    const resultStream = fs.createWriteStream(resultPath);
    resultStream.write(`Task: ${filename}\n`);
    resultStream.write(`Started: ${timestamp()}\n`);
    resultStream.write(`${'─'.repeat(70)}\n`);
    resultStream.write(`Content:\n${content}\n`);
    resultStream.write(`${'─'.repeat(70)}\n\n`);
    resultStream.write(`Claude Output:\n`);
    resultStream.write(`${'─'.repeat(70)}\n`);
    
    return new Promise((resolve) => {
        // Spawn claude process
        // Using --print flag for non-interactive mode if available
        // Otherwise pass the prompt directly
        const claude = spawn('claude', [content], {
            cwd: PROJECT_DIR,
            stdio: ['ignore', 'pipe', 'pipe'],
            env: { ...process.env, TERM: 'dumb' }
        });
        
        let output = '';
        
        claude.stdout.on('data', (data) => {
            const text = data.toString();
            process.stdout.write(text);
            resultStream.write(text);
            output += text;
        });
        
        claude.stderr.on('data', (data) => {
            const text = data.toString();
            process.stderr.write(text);
            resultStream.write(`[STDERR] ${text}`);
            output += text;
        });
        
        claude.on('error', (err) => {
            console.error(`Failed to start Claude: ${err.message}`);
            resultStream.write(`\n[ERROR] Failed to start Claude: ${err.message}\n`);
            resultStream.end();
            fs.renameSync(processingPath, path.join(FAILED_DIR, filename));
            tasksFailed++;
            resolve(false);
        });
        
        claude.on('close', (code) => {
            const endTime = timestamp();
            const success = code === 0;
            
            resultStream.write(`\n${'─'.repeat(70)}\n`);
            resultStream.write(`Completed: ${endTime}\n`);
            resultStream.write(`Exit code: ${code}\n`);
            resultStream.write(`Status: ${success ? 'SUCCESS' : 'FAILED'}\n`);
            resultStream.end();
            
            // Move to appropriate directory
            const destDir = success ? COMPLETED_DIR : FAILED_DIR;
            const destPath = path.join(destDir, filename);
            
            try {
                fs.renameSync(processingPath, destPath);
            } catch (err) {
                console.error(`Failed to move completed task: ${err.message}`);
            }
            
            if (success) {
                console.log(`\n✅ Completed: ${filename}`);
                tasksProcessed++;
            } else {
                console.log(`\n❌ Failed: ${filename} (exit code: ${code})`);
                tasksFailed++;
            }
            
            resolve(success);
        });
    });
}

/**
 * Process all pending tasks
 */
async function processQueue() {
    if (isProcessing) {
        return;
    }
    
    const tasks = getPendingTasks();
    if (tasks.length === 0) {
        return;
    }
    
    isProcessing = true;
    
    console.log(`\n📬 Found ${tasks.length} task(s) in queue`);
    
    for (const task of tasks) {
        await processTask(task);
    }
    
    isProcessing = false;
    console.log(`\n⏳ Waiting for new tasks... (poll interval: ${POLL_INTERVAL}ms)`);
}

/**
 * Display startup banner
 */
function showBanner() {
    console.log('');
    console.log('╔══════════════════════════════════════════════════════════════════════╗');
    console.log('║                    Claude Task Queue Watcher                         ║');
    console.log('╠══════════════════════════════════════════════════════════════════════╣');
    console.log(`║  Queue:     ${QUEUE_DIR.padEnd(54)} ║`);
    console.log(`║  Results:   ${RESULTS_DIR.padEnd(54)} ║`);
    console.log(`║  Interval:  ${(POLL_INTERVAL + 'ms').padEnd(54)} ║`);
    console.log('╠══════════════════════════════════════════════════════════════════════╣');
    console.log('║  Drop .md or .txt files in the queue directory.                      ║');
    console.log('║  Files are processed in alphabetical order.                          ║');
    console.log('║  Use numeric prefixes: 001-task.md, 002-task.md                      ║');
    console.log('╚══════════════════════════════════════════════════════════════════════╝');
    console.log('');
}

/**
 * Handle graceful shutdown
 */
function setupShutdown() {
    const shutdown = (signal) => {
        console.log(`\n\n📊 Queue Watcher Statistics`);
        console.log(`   Tasks processed: ${tasksProcessed}`);
        console.log(`   Tasks failed: ${tasksFailed}`);
        console.log(`\n👋 Received ${signal}, shutting down...`);
        process.exit(0);
    };
    
    process.on('SIGINT', () => shutdown('SIGINT'));
    process.on('SIGTERM', () => shutdown('SIGTERM'));
}

/**
 * Main entry point
 */
async function main() {
    showBanner();
    setupShutdown();
    ensureDirectories();
    
    // Process any existing tasks immediately
    await processQueue();
    
    console.log(`⏳ Waiting for new tasks... (poll interval: ${POLL_INTERVAL}ms)`);
    
    // Start polling
    setInterval(processQueue, POLL_INTERVAL);
}

// Run
main().catch(err => {
    console.error('Fatal error:', err);
    process.exit(1);
});

