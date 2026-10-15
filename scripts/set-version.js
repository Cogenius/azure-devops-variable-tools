#!/usr/bin/env node
// Stamps a semantic version (MAJOR.MINOR.PATCH) into vss-extension.json and every task.json.
// Usage: node scripts/set-version.js 1.2.3
'use strict';

const fs = require('fs');
const path = require('path');

const version = process.argv[2];
const match = /^(\d+)\.(\d+)\.(\d+)$/.exec(version || '');
if (!match) {
    console.error('Usage: node scripts/set-version.js <major.minor.patch>');
    process.exit(1);
}
const [major, minor, patch] = match.slice(1).map(Number);
const root = path.resolve(__dirname, '..');

function updateJson(file, update) {
    const json = JSON.parse(fs.readFileSync(file, 'utf8'));
    update(json);
    fs.writeFileSync(file, JSON.stringify(json, null, 2) + '\n');
    console.log(`Updated ${path.relative(root, file)} -> ${version}`);
}

updateJson(path.join(root, 'vss-extension.json'), json => { json.version = version; });

const tasksDir = path.join(root, 'tasks');
for (const task of fs.readdirSync(tasksDir)) {
    const taskDir = path.join(tasksDir, task);
    if (!fs.statSync(taskDir).isDirectory()) continue;
    for (const versionDir of fs.readdirSync(taskDir)) {
        const taskJson = path.join(taskDir, versionDir, 'task.json');
        if (!fs.existsSync(taskJson)) continue;
        updateJson(taskJson, json => {
            if (json.version.Major !== major) {
                // The task major version is tied to the folder (v1, v2, ...); only minor/patch follow the extension.
                console.log(`  keeping task major ${json.version.Major} for ${task}/${versionDir}`);
            }
            json.version.Minor = minor;
            json.version.Patch = patch;
        });
    }
}
