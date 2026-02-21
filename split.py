import os

base_dir = '/Users/tenyi/Projects/VoiceInput/VoiceInput'
settings_view_path = os.path.join(base_dir, 'SettingsView.swift')

with open(settings_view_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

views_dir = os.path.join(base_dir, 'Settings', 'Views')
os.makedirs(views_dir, exist_ok=True)

def write_view(filename, start, end, extra_imports=[]):
    content = "import SwiftUI\n"
    for imp in extra_imports:
        content += f"import {imp}\n"
    content += "\n" + "".join(lines[start:end])
    with open(os.path.join(views_dir, filename), 'w', encoding='utf-8') as out:
        out.write(content)

# Export sections
write_view('GeneralSettingsView.swift', 54, 200)
# TranscriptionSettingsView (already manually exported or we can overwrite)
write_view('TranscriptionSettingsView.swift', 200, 220)
write_view('ModelSettingsView.swift', 220, 451)
write_view('LLMSettingsView.swift', 451, 830, ['os'])
write_view('HistorySettingsView.swift', 830, 886)
write_view('CustomProviderSheets.swift', 886, 1081)

# Keep the main SettingsView
with open(settings_view_path, 'w', encoding='utf-8') as f:
    f.write("".join(lines[:54]))
    f.write("\n")
    f.write("".join(lines[1081:]))

print("Split completed successfully")
