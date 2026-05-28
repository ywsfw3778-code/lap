const fs = require('fs');
const vm = require('vm');
const path = require('path');

const filePath = path.join(__dirname, '..', 'chat-prototype_1.html');
const html = fs.readFileSync(filePath, 'utf8');

// Extract all scripts
const scriptRegex = /<script\b[^>]*>([\s\S]*?)<\/script>/gi;
let match;
let scriptIndex = 1;

while ((match = scriptRegex.exec(html)) !== null) {
  const scriptContent = match[1].trim();
  if (!scriptContent) continue;
  
  console.log(`Checking script block ${scriptIndex}...`);
  try {
    new vm.Script(scriptContent);
    console.log(`Script block ${scriptIndex} is syntactically correct.`);
  } catch (err) {
    console.error(`Syntax error in script block ${scriptIndex}:`);
    console.error(err.stack);
    process.exit(1);
  }
  scriptIndex++;
}

console.log("All script blocks are syntactically valid!");
