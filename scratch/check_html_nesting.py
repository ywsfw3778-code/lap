import re

def check_html_nesting(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # We want to find the settingsOverlay line
    lines = content.splitlines()
    settings_line_idx = -1
    for idx, line in enumerate(lines):
        if 'id="settingsOverlay"' in line:
            settings_line_idx = idx
            break
            
    if settings_line_idx == -1:
        print("Could not find settingsOverlay!")
        return
        
    print(f"settingsOverlay starts at line {settings_line_idx + 1}")
    
    # Let's count tags from settingsOverlay line onwards
    stack = []
    # Simple regex to find HTML tags
    tag_regex = re.compile(r'<(div|/div)\b[^>]*>', re.IGNORECASE)
    
    for idx in range(settings_line_idx, len(lines)):
        line = lines[idx]
        if '<script' in line.lower() and not 'src=' in line.lower():
            # Stop when we hit the main scripts region
            print(f"Stopping at line {idx + 1} because of <script> tag")
            break
            
        matches = tag_regex.findall(line)
        for match in matches:
            tag = match.lower()
            if tag == 'div':
                stack.append(idx + 1)
            elif tag == '/div':
                if stack:
                    start_line = stack.pop()
                    # If this is the closing tag for settingsOverlay
                    if len(stack) == 0:
                        print(f"settingsOverlay closed at line {idx + 1}")
                else:
                    print(f"Error: unmatched closing </div> on line {idx + 1}")
                    
    print(f"Finished parsing HTML. Unclosed divs count: {len(stack)}")
    if stack:
        print(f"Unclosed divs opened at lines: {stack}")
        for opened_line in stack:
            print(f"Line {opened_line}: {lines[opened_line-1]}")

if __name__ == '__main__':
    check_html_nesting('c:/Users/Pc/Downloads/files/chat-prototype_1.html')
