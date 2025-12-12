# verify_formats.py
print("Checking syndromes_formatted.txt...")
with open("syndromes_formatted.txt", 'r') as f:
    line1 = f.readline().strip()
    print(f"  First line length: {len(line1)}")
    print(f"  First 50 chars: {line1[:50]}")
    print(f"  Should be 936 chars of 0/1")

print("\nChecking golden_formatted.txt...")
with open("golden_formatted.txt", 'r') as f:
    line1 = f.readline().strip()
    print(f"  First line length: {len(line1)}")
    print(f"  First 50 chars: {line1[:50]}")
    print(f"  Should be 8784 chars of 0/1")
    print(f"  Number of 1s: {line1.count('1')}")

print("\nChecking sorted_indices.txt...")
with open("sorted_indices.txt", 'r') as f:
    lines = f.readlines()
    print(f"  Total lines: {len(lines)}")
    print(f"  First 10 indices: {[lines[i].strip() for i in range(10)]}")
    print(f"  Should be 8784 lines of decimal numbers")