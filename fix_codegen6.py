with open('../objective-9c/o9c/o9.y', 'r') as f:
    content = f.read()

# Fix the python replacement syntax error in the typecheck block
# The previous python script messed up the newlines in the C string literals. Let's fix them manually.
# In `fix_codegen4.py`: I replaced things but there are still issues.
# The error says: missing terminating " character at line 2150.
import re
content = re.sub(r'print\("; *\n"\);', r'print(";\\n");', content)
content = re.sub(r'print\("\); *\n"\);', r'print(");\\n");', content)
content = re.sub(r'print\(" o9_dict_set\(&"\);', r'print("\\to9_dict_set(&");', content)
content = re.sub(r'print\(" o9_array_set\(&"\);', r'print("\\to9_array_set(&");', content)
content = re.sub(r'print\("     \{ %s_Client \*__c = \(%s_Client\*\)&", cname, cname\);', r'print("\\t{ %s_Client *__c = (%s_Client*)&", cname, cname);', content)

# I should use git to restore the file from before I broke it with python replacement scripts.
