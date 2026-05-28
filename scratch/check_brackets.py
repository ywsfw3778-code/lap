import re
import sys

def check_brackets(code, script_num):
    stack = []
    lines = code.split('\n')
    for line_idx, line in enumerate(lines):
        for char_idx, char in enumerate(line):
            if char in '({[':
                stack.append((char, line_idx + 1, char_idx + 1))
            elif char in ')}]':
                if not stack:
                    print(f"Error in script {script_num}: Extra closing '{char}' at line {line_idx + 1}, col {char_idx + 1}")
                    print(f"Line content: {line.strip()}")
                    return False
                top, l, c = stack.pop()
                if (char == ')' and top != '(') or (char == '}' and top != '{') or (char == ']' and top != '['):
                    print(f"Error in script {script_num}: Mismatched '{char}' at line {line_idx + 1}, col {char_idx + 1} matching '{top}' from line {l}, col {c}")
                    print(f"Line content: {line.strip()}")
                    return False
    if stack:
        print(f"Error in script {script_num}: Unclosed brackets left:")
        for top, l, c in stack:
            print(f"Unclosed '{top}' from line {l}, col {c}")
        return False
    return True

with open('chat-prototype_1.html', 'r', encoding='utf-8') as f:
    html = f.read()

scripts = re.findall(r'<script\b[^>]*>([\s\S]*?)<\/script>', html, re.IGNORECASE)
print(f"Found {len(scripts)} script tags.")

all_ok = True
for idx, script in enumerate(scripts):
    print(f"Checking script block {idx + 1}...")
    if not check_brackets(script, idx + 1):
        all_ok = False

if all_ok:
    print("All script blocks bracket matching is perfectly OK!")
else:
    sys.exit(1)
