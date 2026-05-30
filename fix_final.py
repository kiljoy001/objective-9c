with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# I need to find the definition of scan_file and remove the static keyword.
# It's at line 2029 according to the error message.
content = content.replace('static void scan_file(char *path);', 'void scan_file(char *path);')
content = content.replace('static void\nscan_file(char *path)', 'void\nscan_file(char *path)')

with open('../objective-9c/o9c/o9.y', 'w') as f:
    f.write(content)
