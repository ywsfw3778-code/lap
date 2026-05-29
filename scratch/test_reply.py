text = '[reply:{"id":"2213","sender":"Jinx","text":"تبا للنت"}]معلش يا حياتي ممواههه'
end_idx = text.find('}]')
print(f"end_idx: {end_idx}")
json_str = text[7:end_idx+1]
actual_text = text[end_idx+2:]
print(f"json_str: {json_str}")
print(f"actual_text: {actual_text}")
